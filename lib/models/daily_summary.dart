class DailySummary {
  const DailySummary({
    required this.date,
    required this.mealsCount,
    required this.totalKcal,
  });

  final DateTime date;
  final int mealsCount;
  final double totalKcal;
}
