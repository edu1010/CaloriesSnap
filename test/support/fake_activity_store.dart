import 'package:calorie_snap/core/utils/app_date_utils.dart';
import 'package:calorie_snap/models/calorie_goals.dart';
import 'package:calorie_snap/models/daily_activity.dart';
import 'package:calorie_snap/services/activity/activity_store.dart';

/// In-memory [ActivityStore] for tests that do not need SQLite.
class FakeActivityStore implements ActivityStore {
  CalorieGoals goals = CalorieGoals.empty;
  final Map<String, DailyActivity> records = <String, DailyActivity>{};
  final Map<ActivitySource, ActivitySyncState> syncStates =
      <ActivitySource, ActivitySyncState>{};

  bool failReplaceRange = false;
  bool failSaveSyncState = false;
  int savedSyncStates = 0;

  String _key(DateTime day, ActivitySource source) =>
      '${AppDateUtils.toDateKey(day)}|${source.storageKey}';

  void _validate(DailyActivity activity) {
    if (activity.invalidField != null || !activity.hasAnyMetric) {
      throw ArgumentError.value(activity, 'activity');
    }
  }

  @override
  Future<CalorieGoals> loadGoals() async => goals;

  @override
  Future<void> saveGoals(CalorieGoals goals) async {
    if (!goals.isValid) {
      throw ArgumentError.value(goals, 'goals');
    }
    this.goals = goals;
  }

  @override
  Future<void> upsert(DailyActivity activity) async {
    _validate(activity);
    records[_key(activity.date, activity.source)] = activity;
  }

  @override
  Future<void> replaceRange(
    ActivitySource source,
    DateTime startInclusive,
    DateTime endExclusive,
    List<DailyActivity> days,
  ) async {
    if (failReplaceRange) {
      throw StateError('disk full');
    }
    for (final day in days) {
      _validate(day);
      if (day.source != source) {
        throw ArgumentError.value(day.source, 'days');
      }
    }
    final start = AppDateUtils.toDateKey(startInclusive);
    final end = AppDateUtils.toDateKey(endExclusive);
    records.removeWhere((key, value) {
      final dateKey = AppDateUtils.toDateKey(value.date);
      return value.source == source &&
          dateKey.compareTo(start) >= 0 &&
          dateKey.compareTo(end) < 0;
    });
    for (final day in days) {
      records[_key(day.date, day.source)] = day;
    }
  }

  @override
  Future<void> delete(DateTime day, ActivitySource source) async {
    records.remove(_key(day, source));
  }

  @override
  Future<List<DailyActivity>> recordsForDay(DateTime day) async {
    final dateKey = AppDateUtils.toDateKey(day);
    final result =
        records.values
            .where((r) => AppDateUtils.toDateKey(r.date) == dateKey)
            .toList();
    result.sort((a, b) => a.source.index.compareTo(b.source.index));
    return result;
  }

  @override
  Future<Map<DateTime, DailyActivity>> effectiveForRange(
    DateTime startInclusive,
    DateTime endExclusive,
  ) async {
    final start = AppDateUtils.toDateKey(startInclusive);
    final end = AppDateUtils.toDateKey(endExclusive);
    final map = <DateTime, DailyActivity>{};
    for (final record in records.values) {
      final dateKey = AppDateUtils.toDateKey(record.date);
      if (dateKey.compareTo(start) < 0 || dateKey.compareTo(end) >= 0) {
        continue;
      }
      final date = AppDateUtils.startOfDay(record.date);
      final current = map[date];
      if (current == null || record.source.index < current.source.index) {
        map[date] = record;
      }
    }
    return map;
  }

  @override
  Future<ActivitySyncState?> loadSyncState(ActivitySource source) async {
    return syncStates[source];
  }

  @override
  Future<void> saveSyncState(ActivitySyncState state) async {
    if (failSaveSyncState) {
      throw StateError('cannot save');
    }
    savedSyncStates++;
    syncStates[state.source] = state;
  }
}
