import '../../core/utils/app_date_utils.dart';
import '../../models/daily_activity.dart';
import '../../models/daily_summary.dart';
import '../../models/energy_summary.dart';
import 'activity_store.dart';

/// Loads the meal totals of every day with meals in
/// [startInclusive, endExclusive), keyed by local midnight.
typedef IntakeLoader =
    Future<Map<DateTime, DailySummary>> Function(
      DateTime startInclusive,
      DateTime endExclusive,
    );

/// Combines logged intake, goals and the effective activity record of each
/// day into the day + week view shown by the activity dashboard.
///
/// Nothing is estimated here: a day without activity data keeps a null
/// activity, and a day without meals counts as zero intake with no meals.
class EnergyDashboardService {
  EnergyDashboardService({
    required IntakeLoader loadIntake,
    required ActivityStore store,
    DateTime Function()? now,
  }) : _loadIntake = loadIntake,
       _store = store,
       _now = now ?? DateTime.now;

  final IntakeLoader _loadIntake;
  final ActivityStore _store;
  final DateTime Function() _now;

  ActivityStore get store => _store;

  /// Monday (local midnight) of the week containing [day].
  static DateTime startOfWeek(DateTime day) {
    return DateTime(day.year, day.month, day.day - (day.weekday - 1));
  }

  /// [day] defaults to today. Returns that day plus its Monday–Sunday week.
  Future<EnergyDashboardData> load({DateTime? day}) async {
    final today = AppDateUtils.startOfDay(_now());
    final selected = AppDateUtils.startOfDay(day ?? today);
    final weekStart = startOfWeek(selected);
    final weekEnd = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day + 7,
    );

    final goals = await _store.loadGoals();
    final intake = await _loadIntake(weekStart, weekEnd);
    final activity = await _store.effectiveForRange(weekStart, weekEnd);

    final intakeByKey = <String, DailySummary>{
      for (final entry in intake.entries)
        AppDateUtils.toDateKey(entry.key): entry.value,
    };
    final activityByKey = <String, DailyActivity>{
      for (final entry in activity.entries)
        AppDateUtils.toDateKey(entry.key): entry.value,
    };

    final days = <DayEnergy>[];
    for (var i = 0; i < 7; i++) {
      final date = DateTime(weekStart.year, weekStart.month, weekStart.day + i);
      final key = AppDateUtils.toDateKey(date);
      final summary = intakeByKey[key];
      days.add(
        DayEnergy(
          date: date,
          consumedKcal: summary?.totalKcal ?? 0,
          mealsCount: summary?.mealsCount ?? 0,
          activity: activityByKey[key],
          goalKcal: goals.dailyKcal,
        ),
      );
    }

    return EnergyDashboardData(
      goals: goals,
      day: days[selected.weekday - 1],
      week: WeekEnergy(
        weekStart: weekStart,
        days: days,
        today: today,
        goalKcal: goals.weeklyKcal,
      ),
    );
  }
}
