class AppDateUtils {
  const AppDateUtils._();

  static DateTime startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static DateTime startOfNextDay(DateTime date) {
    return startOfDay(date).add(const Duration(days: 1));
  }

  static DateTime startOfMonth(DateTime date) {
    return DateTime(date.year, date.month, 1);
  }

  static DateTime startOfNextMonth(DateTime date) {
    return DateTime(date.year, date.month + 1, 1);
  }

  static String toDateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static DateTime fromDateKey(String dateKey) {
    final parts = dateKey.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }
}
