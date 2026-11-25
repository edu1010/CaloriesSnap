import 'package:calorie_snap/core/utils/app_date_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily boundaries stay at local midnight across calendar changes', () {
    for (final date in <DateTime>[
      DateTime(2026, 3, 29, 12),
      DateTime(2026, 10, 25, 12),
      DateTime(2026, 12, 31, 23, 59),
      DateTime(2028, 2, 28, 18),
      DateTime(2028, 2, 29, 18),
    ]) {
      final next = AppDateUtils.startOfNextDay(date);
      expect(next, DateTime(date.year, date.month, date.day + 1));
      expect(next.hour, 0);
      expect(next.minute, 0);
      expect(next.isUtc, isFalse);
    }
  });
}
