/// Intake targets set by the user. Both are optional and independent: the
/// weekly goal is never derived from the daily one (or the other way round).
class CalorieGoals {
  const CalorieGoals({this.dailyKcal, this.weeklyKcal});

  static const empty = CalorieGoals();

  /// Largest value accepted for either goal, as a typo guard.
  static const maxDailyKcal = 20000.0;
  static const maxWeeklyKcal = 140000.0;

  final double? dailyKcal;
  final double? weeklyKcal;

  static bool isValidDaily(double? value) =>
      value == null || (value.isFinite && value > 0 && value <= maxDailyKcal);

  static bool isValidWeekly(double? value) =>
      value == null || (value.isFinite && value > 0 && value <= maxWeeklyKcal);

  bool get isValid => isValidDaily(dailyKcal) && isValidWeekly(weeklyKcal);
}
