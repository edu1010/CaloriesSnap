import 'package:calorie_snap/models/calorie_goals.dart';
import 'package:calorie_snap/models/daily_activity.dart';
import 'package:calorie_snap/models/energy_summary.dart';
import 'package:flutter_test/flutter_test.dart';

final _monday = DateTime(2026, 3, 9);

DayEnergy _day(
  int offset, {
  double consumed = 0,
  int meals = 0,
  double? goal,
  double? activeKcal,
  double? totalKcal,
  int? steps,
  double? distanceMeters,
  int? activeMinutes,
}) {
  final date = DateTime(_monday.year, _monday.month, _monday.day + offset);
  final hasActivity =
      activeKcal != null ||
      totalKcal != null ||
      steps != null ||
      distanceMeters != null ||
      activeMinutes != null;
  return DayEnergy(
    date: date,
    consumedKcal: consumed,
    mealsCount: meals,
    goalKcal: goal,
    activity:
        hasActivity
            ? DailyActivity(
              date: date,
              source: ActivitySource.manual,
              updatedAt: date,
              activeKcal: activeKcal,
              totalKcal: totalKcal,
              steps: steps,
              distanceMeters: distanceMeters,
              activeMinutes: activeMinutes,
            )
            : null,
  );
}

WeekEnergy _week(
  List<DayEnergy> days, {
  required int todayOffset,
  double? goal,
}) {
  return WeekEnergy(
    weekStart: _monday,
    days: days,
    today: DateTime(_monday.year, _monday.month, _monday.day + todayOffset),
    goalKcal: goal,
  );
}

void main() {
  group('CalorieGoals', () {
    test('validates each goal on its own', () {
      expect(CalorieGoals.empty.isValid, isTrue);
      expect(const CalorieGoals(dailyKcal: 2000).isValid, isTrue);
      expect(const CalorieGoals(weeklyKcal: 14000).isValid, isTrue);
      expect(const CalorieGoals(dailyKcal: 0).isValid, isFalse);
      expect(const CalorieGoals(weeklyKcal: -5).isValid, isFalse);
      expect(const CalorieGoals(dailyKcal: double.nan).isValid, isFalse);
      expect(
        const CalorieGoals(dailyKcal: 2000, weeklyKcal: 140001).isValid,
        isFalse,
      );
    });
  });

  group('ActivitySource', () {
    test('is declared in priority order with stable keys', () {
      expect(ActivitySource.values, <ActivitySource>[
        ActivitySource.manual,
        ActivitySource.healthConnect,
        ActivitySource.csvImport,
      ]);
      for (final source in ActivitySource.values) {
        expect(ActivitySource.fromStorageKey(source.storageKey), source);
      }
      expect(ActivitySource.fromStorageKey('nope'), isNull);
      expect(ActivitySource.fromStorageKey(null), isNull);
    });
  });

  group('DayEnergy', () {
    test('remaining needs a goal and can go negative', () {
      expect(_day(0, consumed: 1500).remainingKcal, isNull);
      expect(_day(0, consumed: 1500, goal: 2000).remainingKcal, 500);
      expect(_day(0, consumed: 2400, goal: 2000).remainingKcal, -400);
    });

    test('net needs total expenditure, active alone is not enough', () {
      expect(_day(0, consumed: 2000).netKcal, isNull);
      expect(_day(0, consumed: 2000, activeKcal: 500).netKcal, isNull);
      expect(
        _day(0, consumed: 2000, activeKcal: 500, totalKcal: 2300).netKcal,
        -300,
      );
      // No meals logged but expenditure known: net is still defined.
      expect(_day(0, totalKcal: 2300).netKcal, -2300);
    });
  });

  group('WeekEnergy', () {
    test('partial week: sums come with the number of days behind them', () {
      final week = _week(
        <DayEnergy>[
          _day(
            0,
            consumed: 2000,
            meals: 3,
            activeKcal: 400,
            totalKcal: 2400,
            steps: 8000,
            distanceMeters: 6000,
            activeMinutes: 40,
          ),
          _day(1, consumed: 1800, meals: 2, activeKcal: 300, steps: 5000),
          _day(2, consumed: 2200, meals: 3),
          _day(3, totalKcal: 2100),
          _day(4),
          _day(5),
          _day(6),
        ],
        todayOffset: 3,
        goal: 13000,
      );

      expect(week.elapsedDays, 4);
      expect(week.consumedKcal, 6000);
      expect(week.daysWithMeals, 3);
      expect(week.remainingKcal, 7000);

      expect(week.daysWithActiveBurned, 2);
      expect(week.activeBurnedKcal, 700);
      expect(week.daysWithTotalBurned, 2);
      expect(week.totalBurnedKcal, 4500);
      // (2000 - 2400) + (0 - 2100): only the two days with a total.
      expect(week.netKcal, -2500);
      expect(week.isNetComplete, isFalse);

      expect(week.daysWithSteps, 2);
      expect(week.steps, 13000);
      expect(week.daysWithDistance, 1);
      expect(week.distanceMeters, 6000);
      expect(week.daysWithActiveMinutes, 1);
      expect(week.activeMinutes, 40);
    });

    test('a reported zero is data, a missing value is not', () {
      final week = _week(<DayEnergy>[
        _day(0, activeKcal: 0, steps: 0),
        for (var i = 1; i < 7; i++) _day(i),
      ], todayOffset: 6);

      expect(week.daysWithActiveBurned, 1);
      expect(week.activeBurnedKcal, 0);
      expect(week.daysWithSteps, 1);
      expect(week.steps, 0);
      expect(week.daysWithTotalBurned, 0);
      expect(week.totalBurnedKcal, isNull);
      expect(week.netKcal, isNull);
      expect(week.distanceMeters, isNull);
      expect(week.activeMinutes, isNull);
    });

    test('net is complete once every elapsed day has a total', () {
      final days = <DayEnergy>[
        _day(0, consumed: 2000, meals: 1, totalKcal: 2500),
        _day(1, consumed: 2000, meals: 1, totalKcal: 2500),
        for (var i = 2; i < 7; i++) _day(i),
      ];

      // Tuesday: both elapsed days covered, future days do not count.
      expect(_week(days, todayOffset: 1).isNetComplete, isTrue);
      // Wednesday has started without a total.
      expect(_week(days, todayOffset: 2).isNetComplete, isFalse);
      // Week not started yet.
      expect(_week(days, todayOffset: -1).elapsedDays, 0);
      expect(_week(days, todayOffset: -1).isNetComplete, isFalse);
      // Past week.
      expect(_week(days, todayOffset: 30).elapsedDays, 7);
      expect(_week(days, todayOffset: 30).isNetComplete, isFalse);
    });

    test('remaining is null without a weekly goal', () {
      final week = _week(<DayEnergy>[
        for (var i = 0; i < 7; i++)
          _day(i, consumed: 2000, meals: 1, goal: 2000),
      ], todayOffset: 6);

      expect(week.consumedKcal, 14000);
      expect(week.goalKcal, isNull);
      expect(week.remainingKcal, isNull);
    });

    test('days cannot be modified after construction', () {
      final week = _week(<DayEnergy>[
        for (var i = 0; i < 7; i++) _day(i),
      ], todayOffset: 0);
      expect(() => week.days.add(_day(0)), throwsUnsupportedError);
    });
  });
}
