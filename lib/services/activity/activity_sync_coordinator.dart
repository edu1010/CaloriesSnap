import '../../core/utils/app_date_utils.dart';
import '../../models/daily_activity.dart';
import 'activity_store.dart';
import 'activity_sync_source.dart';

/// Runs a foreground synchronisation of one [ActivitySyncSource] into the
/// [ActivityStore] and records how it went.
class ActivitySyncCoordinator {
  ActivitySyncCoordinator({
    required ActivityStore store,
    required ActivitySyncSource source,
    DateTime Function()? now,
  }) : _store = store,
       _source = source,
       _now = now ?? DateTime.now;

  static const defaultDays = 14;

  final ActivityStore _store;
  final ActivitySyncSource _source;
  final DateTime Function() _now;

  ActivitySyncSource get source => _source;

  Future<ActivitySyncAvailability> checkAvailability() {
    return _source.checkAvailability();
  }

  Future<ActivitySyncState?> lastState() {
    return _store.loadSyncState(_source.source);
  }

  /// Foreground sync on explicit user request: availability -> permissions
  /// (requested if missing) -> fetch of the last [days] local days including
  /// today -> replacement of that range in the store -> saved sync state.
  ///
  /// Never throws; every problem is reported through the outcome status.
  Future<ActivitySyncOutcome> sync({int days = defaultDays}) async {
    final attemptAt = _now();
    ActivitySyncOutcome outcome;
    try {
      outcome = await _run(attemptAt, days < 1 ? 1 : days);
    } on ActivitySyncException catch (error) {
      outcome = ActivitySyncOutcome(
        status: ActivitySyncStatus.failed,
        message: error.message,
      );
    } catch (error) {
      outcome = ActivitySyncOutcome(
        status: ActivitySyncStatus.failed,
        message: error.toString(),
      );
    }

    if (outcome.status != ActivitySyncStatus.unsupportedPlatform) {
      await _saveState(attemptAt, outcome);
    }
    return outcome;
  }

  Future<ActivitySyncOutcome> _run(DateTime attemptAt, int days) async {
    final availability = await _source.checkAvailability();
    switch (availability) {
      case ActivitySyncAvailability.available:
        break;
      case ActivitySyncAvailability.unsupportedPlatform:
        return const ActivitySyncOutcome(
          status: ActivitySyncStatus.unsupportedPlatform,
        );
      case ActivitySyncAvailability.providerNotInstalled:
        return const ActivitySyncOutcome(
          status: ActivitySyncStatus.providerNotInstalled,
        );
      case ActivitySyncAvailability.providerUpdateRequired:
        return const ActivitySyncOutcome(
          status: ActivitySyncStatus.providerUpdateRequired,
        );
    }

    if (!await _source.hasPermissions()) {
      if (!await _source.requestPermissions()) {
        return const ActivitySyncOutcome(
          status: ActivitySyncStatus.permissionDenied,
        );
      }
    }

    final today = AppDateUtils.startOfDay(attemptAt);
    final start = DateTime(today.year, today.month, today.day - (days - 1));
    final end = DateTime(today.year, today.month, today.day + 1);

    final fetched = await _source.fetchDays(start, end);
    final accepted = _accept(fetched, start, end, attemptAt);
    await _store.replaceRange(_source.source, start, end, accepted);

    return ActivitySyncOutcome(
      status: ActivitySyncStatus.success,
      importedDays: accepted.length,
      syncedAt: attemptAt,
    );
  }

  /// Keeps one usable record per day of the range, re-stamped with this
  /// coordinator's source. Unusable records are dropped, not fatal.
  List<DailyActivity> _accept(
    List<DailyActivity> fetched,
    DateTime start,
    DateTime end,
    DateTime attemptAt,
  ) {
    final byDay = <String, DailyActivity>{};
    for (final record in fetched) {
      if (record.source != _source.source) {
        continue;
      }
      if (record.invalidField != null || !record.hasAnyMetric) {
        continue;
      }
      final date = AppDateUtils.startOfDay(record.date);
      if (date.isBefore(start) || !date.isBefore(end)) {
        continue;
      }
      byDay.putIfAbsent(
        AppDateUtils.toDateKey(date),
        () => DailyActivity(
          date: date,
          source: _source.source,
          updatedAt: record.updatedAt,
          activeKcal: record.activeKcal,
          totalKcal: record.totalKcal,
          steps: record.steps,
          distanceMeters: record.distanceMeters,
          activeMinutes: record.activeMinutes,
          origin: record.origin,
        ),
      );
    }
    return byDay.values.toList();
  }

  Future<void> _saveState(
    DateTime attemptAt,
    ActivitySyncOutcome outcome,
  ) async {
    try {
      final previous = await _store.loadSyncState(_source.source);
      await _store.saveSyncState(
        ActivitySyncState(
          source: _source.source,
          lastAttemptAt: attemptAt,
          lastSuccessAt:
              outcome.isSuccess ? attemptAt : previous?.lastSuccessAt,
          lastImportedDays:
              outcome.isSuccess
                  ? outcome.importedDays
                  : previous?.lastImportedDays,
          lastError: outcome.isSuccess ? null : outcome.status.name,
        ),
      );
    } catch (_) {
      // The outcome already tells the caller what happened.
    }
  }
}
