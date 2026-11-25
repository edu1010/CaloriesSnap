import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'vlm_engine.dart';
import 'vlm_model_catalog.dart';

enum VlmDownloadPhase { downloading, verifying }

class VlmDownloadProgress {
  const VlmDownloadProgress({
    required this.spec,
    required this.phase,
    required this.receivedBytes,
  });

  final VlmModelSpec spec;
  final VlmDownloadPhase phase;
  final int receivedBytes;

  double get fraction =>
      spec.totalBytes == 0 ? 0 : receivedBytes / spec.totalBytes;
}

class VlmDownloadCancelled implements Exception {
  const VlmDownloadCancelled();
}

/// Downloads, verifies and keeps the on-device vision models, and remembers
/// which one the user selected. Models are far too large for the app bundle.
class VlmModelStore extends ChangeNotifier {
  VlmModelStore({
    this.catalog = VlmModelCatalog.all,
    Future<Directory> Function()? rootDirectory,
    HttpClient Function()? httpClientFactory,
  }) : _rootDirectory = rootDirectory ?? _defaultRoot,
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  static const String _settingsFile = 'settings.json';
  static const String _installedMarker = 'installed.json';
  static const String _onboardingMarker = 'onboarding-complete';

  /// Models offered for download.
  final List<VlmModelSpec> catalog;

  final Future<Directory> Function() _rootDirectory;
  final HttpClient Function() _httpClientFactory;

  Directory? _root;
  final Set<String> _installed = <String>{};
  String? _selectedId;
  VlmDownloadProgress? _progress;
  Object? _lastError;
  HttpClient? _activeClient;
  bool _cancelRequested = false;
  bool _needsOnboarding = false;

  VlmDownloadProgress? get progress => _progress;
  Object? get lastError => _lastError;
  String? get selectedId => _selectedId;
  bool get needsOnboarding => _needsOnboarding;

  /// The model photo analysis should use, or null when the vision model is
  /// off or not downloaded.
  VlmModelSpec? get activeModel {
    for (final spec in catalog) {
      if (spec.id == _selectedId && _installed.contains(spec.id)) return spec;
    }
    return null;
  }

  bool isInstalled(VlmModelSpec spec) => _installed.contains(spec.id);

  static Future<Directory> _defaultRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'vlm_models'));
  }

  Future<void> init() async {
    final root = _root = await _rootDirectory();
    await root.create(recursive: true);
    _installed.clear();
    _selectedId = null;
    for (final spec in catalog) {
      if (await _isComplete(spec)) _installed.add(spec.id);
    }
    final settings = File(p.join(root.path, _settingsFile));
    var hasExistingSelection = false;
    if (await settings.exists()) {
      try {
        final decoded = jsonDecode(await settings.readAsString());
        if (decoded is Map && decoded.containsKey('selected')) {
          final selected = decoded['selected'];
          if (selected == null || selected is String) {
            hasExistingSelection = true;
            _selectedId = selected as String?;
          }
        }
      } on FormatException {
        // A corrupt settings file only loses the selection.
      }
    }
    _needsOnboarding =
        !hasExistingSelection &&
        _installed.isEmpty &&
        !await File(p.join(root.path, _onboardingMarker)).exists();
    notifyListeners();
  }

  Future<void> finishOnboarding() async {
    await File(p.join(_requireRoot().path, _onboardingMarker)).create();
    _needsOnboarding = false;
    notifyListeners();
  }

  Future<VlmModelFiles?> filesOf(VlmModelSpec spec) async {
    if (!_installed.contains(spec.id)) return null;
    final dir = _modelDirectory(spec);
    return VlmModelFiles(
      modelPath: p.join(dir.path, spec.model.fileName),
      projectorPath: p.join(dir.path, spec.projector.fileName),
    );
  }

  /// Selects the model used for analysis; null turns the vision model off.
  Future<void> select(VlmModelSpec? spec) async {
    _selectedId = spec?.id;
    await File(
      p.join(_requireRoot().path, _settingsFile),
    ).writeAsString(jsonEncode(<String, dynamic>{'selected': _selectedId}));
    notifyListeners();
  }

  Future<void> delete(VlmModelSpec spec) async {
    final dir = _modelDirectory(spec);
    if (await dir.exists()) await dir.delete(recursive: true);
    _installed.remove(spec.id);
    notifyListeners();
  }

  /// Downloads [spec], resuming partial files, and verifies every file's
  /// SHA-256 before the model becomes usable. Selects it on success.
  Future<void> download(VlmModelSpec spec) async {
    if (_progress != null) {
      throw StateError('A model download is already running.');
    }
    _cancelRequested = false;
    _lastError = null;
    final dir = _modelDirectory(spec);
    _report(spec, VlmDownloadPhase.downloading, 0);
    try {
      await dir.create(recursive: true);
      if (_cancelRequested) throw const VlmDownloadCancelled();
      final client = _activeClient = _httpClientFactory();
      var completedBytes = 0;
      for (final file in spec.files) {
        final target = File(p.join(dir.path, file.fileName));
        if (!await _hasExpectedSize(target, file)) {
          await _downloadFile(
            client: client,
            spec: spec,
            file: file,
            target: target,
            completedBytes: completedBytes,
          );
        }
        completedBytes += file.bytes;
        _report(spec, VlmDownloadPhase.verifying, completedBytes);
        final digest = await _sha256InBackground(target.path);
        if (digest != file.sha256) {
          await target.delete();
          throw StateError(
            'Checksum mismatch for ${file.fileName}; the file was removed.',
          );
        }
        if (_cancelRequested) throw const VlmDownloadCancelled();
      }
      await File(p.join(dir.path, _installedMarker)).writeAsString(
        jsonEncode(<String, dynamic>{
          'id': spec.id,
          'files': <String, String>{
            for (final file in spec.files) file.fileName: file.sha256,
          },
        }),
      );
      _installed.add(spec.id);
      await select(spec);
    } catch (error) {
      _lastError = _cancelRequested ? const VlmDownloadCancelled() : error;
      if (_cancelRequested) throw const VlmDownloadCancelled();
      rethrow;
    } finally {
      _activeClient?.close(force: true);
      _activeClient = null;
      _progress = null;
      notifyListeners();
    }
  }

  /// Stops the running download. The partial file is kept for resuming.
  void cancelDownload() {
    if (_progress == null) return;
    _cancelRequested = true;
    _activeClient?.close(force: true);
  }

  /// Total device memory in GB, or null when it cannot be determined.
  Future<int?> deviceRamGb() async {
    try {
      final meminfo = File('/proc/meminfo');
      if (!await meminfo.exists()) return null;
      final match = RegExp(
        r'MemTotal:\s+(\d+)\s*kB',
      ).firstMatch(await meminfo.readAsString());
      if (match == null) return null;
      // Devices report slightly less than their nominal size.
      return (int.parse(match.group(1)!) / (1024 * 1024)).ceil();
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _downloadFile({
    required HttpClient client,
    required VlmModelSpec spec,
    required VlmRemoteFile file,
    required File target,
    required int completedBytes,
  }) async {
    final partial = File('${target.path}.part');
    var offset = await partial.exists() ? await partial.length() : 0;
    if (offset > file.bytes) {
      await partial.delete();
      offset = 0;
    }

    if (offset < file.bytes) {
      final request = await client.getUrl(Uri.parse(file.url));
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      }
      final response = await request.close();
      if (response.statusCode == HttpStatus.ok) {
        // The server ignored the range; start over.
        offset = 0;
      } else if (response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        throw HttpException(
          'Download failed with HTTP ${response.statusCode}',
          uri: Uri.parse(file.url),
        );
      }

      final sink = partial.openWrite(
        mode: offset == 0 ? FileMode.write : FileMode.append,
      );
      var received = offset;
      var lastReport = DateTime.fromMillisecondsSinceEpoch(0);
      try {
        await for (final chunk in response) {
          if (_cancelRequested) throw const VlmDownloadCancelled();
          sink.add(chunk);
          received += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastReport).inMilliseconds >= 200) {
            lastReport = now;
            _report(
              spec,
              VlmDownloadPhase.downloading,
              completedBytes + received,
            );
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
    }

    final length = await partial.length();
    if (length != file.bytes) {
      throw StateError(
        'Incomplete download of ${file.fileName}: $length of ${file.bytes} bytes.',
      );
    }
    await partial.rename(target.path);
  }

  void _report(VlmModelSpec spec, VlmDownloadPhase phase, int receivedBytes) {
    _progress = VlmDownloadProgress(
      spec: spec,
      phase: phase,
      receivedBytes: receivedBytes,
    );
    notifyListeners();
  }

  Future<bool> _isComplete(VlmModelSpec spec) async {
    final dir = _modelDirectory(spec);
    if (!await File(p.join(dir.path, _installedMarker)).exists()) return false;
    for (final file in spec.files) {
      if (!await _hasExpectedSize(
        File(p.join(dir.path, file.fileName)),
        file,
      )) {
        return false;
      }
    }
    return true;
  }

  static Future<bool> _hasExpectedSize(File file, VlmRemoteFile remote) async =>
      await file.exists() && await file.length() == remote.bytes;

  Directory _modelDirectory(VlmModelSpec spec) =>
      Directory(p.join(_requireRoot().path, spec.id));

  Directory _requireRoot() {
    final root = _root;
    if (root == null) throw StateError('VlmModelStore.init() was not called.');
    return root;
  }
}

// A separate function so the isolate closure captures only sendable values.
Future<String> _sha256InBackground(String path) =>
    Isolate.run(() => _sha256Of(path));

String _sha256Of(String path) {
  final output = _DigestSink<Digest>();
  final input = sha256.startChunkedConversion(output);
  final file = File(path).openSync();
  try {
    final buffer = Uint8List(1 << 20);
    while (true) {
      final read = file.readIntoSync(buffer);
      if (read <= 0) break;
      input.add(Uint8List.sublistView(buffer, 0, read));
    }
  } finally {
    file.closeSync();
  }
  input.close();
  return output.events.single.toString();
}

/// Collects the single digest a chunked hash conversion emits.
class _DigestSink<T> implements Sink<T> {
  final List<T> events = <T>[];

  @override
  void add(T event) => events.add(event);

  @override
  void close() {}
}
