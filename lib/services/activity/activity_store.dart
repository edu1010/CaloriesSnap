import '../../models/calorie_goals.dart';
import '../../models/daily_activity.dart';

/// Local persistence for calorie goals, per-day activity records and sync
/// state. Nothing here leaves the device.
///
/// Activity is keyed by (day, source): each source keeps its own record and
/// [effectiveForRange] picks one per day by [ActivitySource] priority.
abstract class ActivityStore {
  Future<CalorieGoals> loadGoals();

  /// Throws [ArgumentError] when a goal is not a positive finite number.
  /// A null field clears that goal.
  Future<void> saveGoals(CalorieGoals goals);

  /// Inserts or replaces the record for (activity.date, activity.source).
  /// Throws [ArgumentError] when [DailyActivity.invalidField] is not null or
  /// the record has no metric at all.
  Future<void> upsert(DailyActivity activity);

  /// Atomically replaces every record of [source] within
  /// [startInclusive, endExclusive) by [days]. Days of the range missing from
  /// [days] end up with no record for that source.
  Future<void> replaceRange(
    ActivitySource source,
    DateTime startInclusive,
    DateTime endExclusive,
    List<DailyActivity> days,
  );

  Future<void> delete(DateTime day, ActivitySource source);

  /// Every stored record of the day, all sources.
  Future<List<DailyActivity>> recordsForDay(DateTime day);

  /// The record to use for each day of the range, keyed by local midnight.
  /// Days without any record are absent from the map.
  Future<Map<DateTime, DailyActivity>> effectiveForRange(
    DateTime startInclusive,
    DateTime endExclusive,
  );

  Future<ActivitySyncState?> loadSyncState(ActivitySource source);
  Future<void> saveSyncState(ActivitySyncState state);
}
