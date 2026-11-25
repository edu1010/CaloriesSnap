import 'calorie_goals.dart';
import 'daily_activity.dart';

/// Intake and expenditure of one local calendar day.
class DayEnergy {
  const DayEnergy({
    required this.date,
    required this.consumedKcal,
    required this.mealsCount,
    this.activity,
    this.goalKcal,
  });

  final DateTime date;
  final double consumedKcal;
  final int mealsCount;

  /// The single activity record used for this day (see [ActivitySource] for
  /// the priority), or null when no source has data.
  final DailyActivity? activity;
  final double? goalKcal;

  bool get hasMeals => mealsCount > 0;
  double? get activeBurnedKcal => activity?.activeKcal;
  double? get totalBurnedKcal => activity?.totalKcal;

  /// Goal minus intake; negative when the goal was exceeded. Null without goal.
  double? get remainingKcal => goalKcal == null ? null : goalKcal! - consumedKcal;

  /// Intake minus total expenditure. Null unless total expenditure is known:
  /// active calories alone are not enough to state an energy balance.
  double? get netKcal =>
      totalBurnedKcal == null ? null : consumedKcal - totalBurnedKcal!;
}

/// Monday-to-Sunday aggregate. Sums only cover days that have the metric, and
/// each sum is paired with a day count so a partial week is never presented as
/// a complete one.
class WeekEnergy {
  WeekEnergy({
    required this.weekStart,
    required List<DayEnergy> days,
    required this.today,
    this.goalKcal,
  }) : assert(days.length == 7),
       days = List<DayEnergy>.unmodifiable(days);

  /// Local midnight of the Monday.
  final DateTime weekStart;

  /// Exactly seven entries, Monday first.
  final List<DayEnergy> days;

  /// Local midnight of the current day, used to tell elapsed from future days.
  final DateTime today;
  final double? goalKcal;

  /// Days of this week that have started (1..7; 7 for past weeks, 0 for
  /// future weeks).
  int get elapsedDays => days.where((d) => !d.date.isAfter(today)).length;

  double get consumedKcal => days.fold(0, (sum, d) => sum + d.consumedKcal);
  int get daysWithMeals => days.where((d) => d.hasMeals).length;

  double? get remainingKcal => goalKcal == null ? null : goalKcal! - consumedKcal;

  int get daysWithActiveBurned =>
      days.where((d) => d.activeBurnedKcal != null).length;
  double? get activeBurnedKcal => _sum((d) => d.activeBurnedKcal);

  int get daysWithTotalBurned =>
      days.where((d) => d.totalBurnedKcal != null).length;
  double? get totalBurnedKcal => _sum((d) => d.totalBurnedKcal);

  /// Intake minus total expenditure restricted to the [daysWithTotalBurned]
  /// days where expenditure is known. Null when no day has it.
  double? get netKcal => _sum((d) => d.netKcal);

  /// True when every elapsed day has total expenditure, i.e. [netKcal]
  /// describes the whole week so far.
  bool get isNetComplete =>
      elapsedDays > 0 &&
      days
          .where((d) => !d.date.isAfter(today))
          .every((d) => d.totalBurnedKcal != null);

  int get daysWithSteps => days.where((d) => d.activity?.steps != null).length;
  int? get steps => _sum((d) => d.activity?.steps?.toDouble())?.round();

  int get daysWithDistance =>
      days.where((d) => d.activity?.distanceMeters != null).length;
  double? get distanceMeters => _sum((d) => d.activity?.distanceMeters);

  int get daysWithActiveMinutes =>
      days.where((d) => d.activity?.activeMinutes != null).length;
  int? get activeMinutes =>
      _sum((d) => d.activity?.activeMinutes?.toDouble())?.round();

  double? _sum(double? Function(DayEnergy day) pick) {
    double? total;
    for (final day in days) {
      final value = pick(day);
      if (value != null) {
        total = (total ?? 0) + value;
      }
    }
    return total;
  }
}

class EnergyDashboardData {
  const EnergyDashboardData({
    required this.goals,
    required this.day,
    required this.week,
  });

  final CalorieGoals goals;
  final DayEnergy day;

  /// The Monday-to-Sunday week containing [day].
  final WeekEnergy week;
}
