import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/daily_activity.dart';
import 'activity_sync_source.dart';

/// Reads de-duplicated daily activity totals from Android Health Connect.
///
/// Read-only and foreground-only: nothing is fetched unless a method here is
/// called, and nothing is ever written back. On every platform other than
/// Android the calls answer without touching the platform channel.
class HealthConnectActivitySource implements ActivitySyncSource {
  HealthConnectActivitySource({
    MethodChannel? channel,
    bool? isAndroid,
    DateTime Function()? clock,
  }) : _channel = channel ?? const MethodChannel(channelName),
       // The real host OS, not defaultTargetPlatform: the latter reports
       // Android under `flutter test`, where no native side exists.
       _isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid),
       _clock = clock ?? DateTime.now;

  static const String channelName = 'calorie_snap/health_connect';

  final MethodChannel _channel;
  final bool _isAndroid;
  final DateTime Function() _clock;

  @override
  ActivitySource get source => ActivitySource.healthConnect;

  @override
  Future<ActivitySyncAvailability> checkAvailability() async {
    if (!_isAndroid) {
      return ActivitySyncAvailability.unsupportedPlatform;
    }
    try {
      final status = await _channel.invokeMethod<String>('getSdkStatus');
      return HealthConnectReply.availability(status);
    } on MissingPluginException {
      return ActivitySyncAvailability.unsupportedPlatform;
    } on PlatformException {
      return ActivitySyncAvailability.unsupportedPlatform;
    }
  }

  @override
  Future<bool> hasPermissions() async {
    if (!_isAndroid) {
      return false;
    }
    try {
      final granted = await _channel.invokeListMethod<Object?>(
        'getGrantedPermissions',
      );
      // Additional metrics are optional. Respect a user who granted energy
      // access but declined steps or exercise; don't prompt on every sync.
      return HealthConnectReply.hasEnergyMetric(granted);
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> requestPermissions() async {
    if (!_isAndroid) {
      return false;
    }
    try {
      final granted = await _channel.invokeListMethod<Object?>(
        'requestPermissions',
      );
      return HealthConnectReply.hasEnergyMetric(granted);
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<List<DailyActivity>> fetchDays(
    DateTime startInclusive,
    DateTime endExclusive,
  ) async {
    if (!_isAndroid) {
      throw const ActivitySyncException(
        'Health Connect is only available on Android.',
      );
    }
    final start = _dayOf(startInclusive);
    final end = _dayOf(endExclusive);
    if (!start.isBefore(end)) {
      return <DailyActivity>[];
    }
    final Object? reply;
    try {
      reply = await _channel
          .invokeMethod<Object?>('aggregateDays', <String, Object?>{
            'start': HealthConnectReply.formatDay(start),
            'end': HealthConnectReply.formatDay(end),
          });
    } on MissingPluginException {
      throw const ActivitySyncException(
        'Health Connect is not available in this build.',
      );
    } on PlatformException catch (e) {
      throw ActivitySyncException(HealthConnectReply.describeError(e));
    }
    return HealthConnectReply.parseDays(
      reply,
      startInclusive: start,
      endExclusive: end,
      updatedAt: _clock(),
    );
  }

  @override
  Future<bool> openProviderSetup() async {
    if (!_isAndroid) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('openSetup') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static DateTime _dayOf(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

/// Pure interpretation of what the native Health Connect bridge answers.
abstract final class HealthConnectReply {
  static const String activeKcal = 'activeKcal';
  static const String totalKcal = 'totalKcal';
  static const String steps = 'steps';
  static const String distanceMeters = 'distanceMeters';
  static const String activeMinutes = 'activeMinutes';

  static const List<String> allMetrics = <String>[
    activeKcal,
    totalKcal,
    steps,
    distanceMeters,
    activeMinutes,
  ];

  static final RegExp _dayPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  static ActivitySyncAvailability availability(String? status) {
    switch (status) {
      case 'available':
        return ActivitySyncAvailability.available;
      case 'notInstalled':
        return ActivitySyncAvailability.providerNotInstalled;
      case 'updateRequired':
        return ActivitySyncAvailability.providerUpdateRequired;
      default:
        return ActivitySyncAvailability.unsupportedPlatform;
    }
  }

  static bool hasAllMetrics(List<Object?>? granted) {
    return granted != null && allMetrics.every(granted.contains);
  }

  static bool hasEnergyMetric(List<Object?>? granted) {
    return granted != null &&
        (granted.contains(activeKcal) || granted.contains(totalKcal));
  }

  static String formatDay(DateTime day) {
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Local midnight for a strict `yyyy-MM-dd` key, null when it is not one.
  static DateTime? parseDay(Object? key) {
    if (key is! String) {
      return null;
    }
    final match = _dayPattern.firstMatch(key);
    if (match == null) {
      return null;
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    // DateTime rolls 2026-02-31 over to March instead of failing.
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  /// Turns the `aggregateDays` reply into records sorted by day.
  ///
  /// Absent metrics stay null. A malformed entry or value fails the whole
  /// reply with an [ActivitySyncException] rather than being guessed at. Days
  /// outside the requested range and days without any metric are dropped.
  static List<DailyActivity> parseDays(
    Object? reply, {
    required DateTime startInclusive,
    required DateTime endExclusive,
    required DateTime updatedAt,
  }) {
    if (reply == null) {
      return <DailyActivity>[];
    }
    if (reply is! List) {
      throw const ActivitySyncException(
        'Health Connect returned an unexpected reply.',
      );
    }
    final byDay = <DateTime, DailyActivity>{};
    for (final entry in reply) {
      if (entry is! Map) {
        throw const ActivitySyncException(
          'Health Connect returned an unexpected day entry.',
        );
      }
      final date = parseDay(entry['date']);
      if (date == null) {
        throw ActivitySyncException(
          'Health Connect returned an invalid date: ${entry['date']}.',
        );
      }
      if (date.isBefore(startInclusive) || !date.isBefore(endExclusive)) {
        continue;
      }
      final active = _decimal(entry, activeKcal);
      var total = _decimal(entry, totalKcal);
      // A total below the active part means the apps only wrote total
      // expenditure for a fraction of the day: treat it as unknown instead of
      // understating the day.
      if (active != null && total != null && total < active) {
        total = null;
      }
      final day = DailyActivity(
        date: date,
        source: ActivitySource.healthConnect,
        updatedAt: updatedAt,
        activeKcal: active,
        totalKcal: total,
        steps: _integer(entry, steps),
        distanceMeters: _decimal(entry, distanceMeters),
        activeMinutes: _integer(entry, activeMinutes),
        origin: _origins(entry['origins']),
      );
      if (day.hasAnyMetric) {
        byDay[date] = day;
      }
    }
    return byDay.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  static String describeError(PlatformException e) {
    final detail =
        e.message == null || e.message!.trim().isEmpty
            ? ''
            : ' (${e.message!.trim()})';
    switch (e.code) {
      case 'permissionDenied':
        return 'Health Connect denied access to the activity data$detail.';
      case 'unavailable':
        return 'Health Connect is not available on this device$detail.';
      case 'io':
        return 'Health Connect could not read its data$detail.';
      case 'remote':
        return 'The Health Connect service did not respond$detail.';
      case 'illegalState':
        return 'Health Connect could not complete the request$detail.';
      case 'invalidArgs':
        return 'Invalid Health Connect request$detail.';
      case 'requestInProgress':
        return 'A Health Connect permission request is already open.';
      default:
        return 'Health Connect failed: ${e.code}$detail.';
    }
  }

  static double? _decimal(Map<Object?, Object?> entry, String key) {
    final value = entry[key];
    if (value == null) {
      return null;
    }
    if (value is! num || !value.isFinite || value < 0) {
      throw ActivitySyncException(
        'Health Connect returned an invalid $key value: $value.',
      );
    }
    return value.toDouble();
  }

  static int? _integer(Map<Object?, Object?> entry, String key) {
    final value = entry[key];
    if (value == null) {
      return null;
    }
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        value != value.truncateToDouble()) {
      throw ActivitySyncException(
        'Health Connect returned an invalid $key value: $value.',
      );
    }
    return value.toInt();
  }

  static String? _origins(Object? raw) {
    if (raw is! List) {
      return null;
    }
    final names =
        raw
            .whereType<String>()
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return names.isEmpty ? null : names.join(',');
  }
}
