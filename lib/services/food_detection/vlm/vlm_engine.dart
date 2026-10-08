import 'dart:io';

import 'package:llamadart/llamadart.dart';

/// Local files of one downloaded vision-language model.
class VlmModelFiles {
  const VlmModelFiles({required this.modelPath, required this.projectorPath});

  final String modelPath;

  /// Vision encoder ("mmproj") matching the model.
  final String projectorPath;
}

/// Runtime that answers a text prompt about one image, fully on the device.
abstract class VlmEngine {
  /// Loads [files] unless they already are the loaded model.
  Future<void> load(VlmModelFiles files);

  Future<String> describeImage({
    required String imagePath,
    required String system,
    required String prompt,
    required int maxTokens,
    Map<String, dynamic>? responseFormat,
  });

  /// Stops a running [describeImage]; it then completes with partial text.
  void cancel();

  /// Frees the model's memory. The engine can be loaded again afterwards.
  Future<void> unload();
}

/// llama.cpp through `llamadart`. One model is kept in memory at a time.
class LlamadartVlmEngine implements VlmEngine {
  LlamadartVlmEngine({int contextSize = 4096, bool? useGpu})
    : _contextSize = contextSize,
      // Vulkan drivers on phones are too uneven to trust by default; desktop
      // GPUs are used when present.
      _useGpu = useGpu ?? !(Platform.isAndroid || Platform.isIOS);

  final int _contextSize;
  final bool _useGpu;

  LlamaEngine? _engine;
  String? _loadedModelPath;

  @override
  Future<void> load(VlmModelFiles files) async {
    if (_engine != null && _loadedModelPath == files.modelPath) return;
    await unload();

    final engine = LlamaEngine(LlamaBackend());
    try {
      await engine.setLogLevel(LlamaLogLevel.none);
      await engine.loadModel(
        files.modelPath,
        modelParams: ModelParams(
          contextSize: _contextSize,
          gpuLayers: _useGpu ? ModelParams.maxGpuLayers : 0,
          preferredBackend: _useGpu ? GpuBackend.auto : GpuBackend.cpu,
        ),
      );
      await engine.loadMultimodalProjector(files.projectorPath);
      if (!await engine.supportsVision) {
        throw StateError('The loaded model has no vision support.');
      }
    } catch (_) {
      await engine.dispose();
      rethrow;
    }
    _engine = engine;
    _loadedModelPath = files.modelPath;
  }

  @override
  Future<String> describeImage({
    required String imagePath,
    required String system,
    required String prompt,
    required int maxTokens,
    Map<String, dynamic>? responseFormat,
  }) async {
    final engine = _engine;
    if (engine == null) throw StateError('No vision model is loaded.');

    final output = StringBuffer();
    final chunks = engine.create(
      <LlamaChatMessage>[
        LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system),
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: <LlamaContentPart>[
            LlamaImageContent(path: imagePath),
            LlamaTextContent(prompt),
          ],
        ),
      ],
      // Near-greedy: the answer is data, not prose. No repetition penalty,
      // which would fight the repeated JSON keys.
      params: GenerationParams(
        maxTokens: maxTokens,
        temp: 0.1,
        penalty: 1.0,
        reusePromptPrefix: false,
      ),
      enableThinking: false,
      responseFormat: responseFormat,
    );
    await for (final chunk in chunks) {
      if (chunk.choices.isEmpty) continue;
      final text = chunk.choices.first.delta.content;
      if (text != null) output.write(text);
    }
    return output.toString();
  }

  @override
  void cancel() => _engine?.cancelGeneration();

  @override
  Future<void> unload() async {
    final engine = _engine;
    _engine = null;
    _loadedModelPath = null;
    await engine?.dispose();
  }
}
