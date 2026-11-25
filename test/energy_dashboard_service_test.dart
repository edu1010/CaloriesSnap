import 'package:calorie_snap/models/calorie_goals.dart';
import 'package:calorie_snap/models/daily_activity.dart';
import 'package:calorie_snap/models/daily_summary.dart';
import 'package:calorie_snap/services/activity/energy_dashboard_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_activity_store.dart';

DailyActivity _activity(
  DateTime date,
  ActivitySource source, {
  double? activeKcal,
  double? totalKcal,
  int? steps,
}) {
  return DailyActivity(
    date: date,
    source: source,
    updatedAt: date,
    activeKcal: activeKcal,
    totalKcal: totalKcal,
    steps: steps,
  );
}

void main() {
  late FakeActivityStore store;
  late Map<DateTime, DailySummary> meals;
  late List<List<DateTime>> intakeRequests;

  EnergyDashboardService serviceAt(DateTime now) {
    return EnergyDashboardService(
      store: store,
      now: () => now,
      loadIntake: (start, end) async {
        intakeRequests.add(<DateTime>[start, end]);
        return <DateTime, DailySummary>{
          for (final entry in meals.entries)
            if (!entry.key.isBefore(start) && entry.key.isBefore(end))
              entry.key: entry.value,
        };
      },
    );
  }

  void addMeals(DateTime date, double kcal, {int count = 1}) {
    meals[date] = DailySummary(date: date, mealsCount: count, totalKcal: kcal);
  }

  setUp(() {
    store = FakeActivityStore();
    meals = <DateTime, DailySummary>{};
    intakeRequests = <List<DateTime>>[];
  });

  group('startOfWeek', () {
    test('is the Monday at local midnight', () {
      // 2026-03-09 is a Monday.
      expect(DateTime(2026, 3, 9).weekday, DateTime.monday);
      for (var offset = 0; offset < 7; offset++) {
        expect(
          EnergyDashboardService.startOfWeek(
            DateTime(2026, 3, 9 + offset, 17, 45),
          ),
          DateTime(2026, 3, 9),
        );
      }
    });

    test('a Monday maps to itself and a Sunday to six days earlier', () {
      expect(
        EnergyDashboardService.startOfWeek(DateTime(2026, 3, 9)),
        DateTime(2026, 3, 9),
      );
      expect(
        EnergyDashboardService.startOfWeek(DateTime(2026, 3, 15, 23, 59, 59)),
        DateTime(2026, 3, 9),
      );
      expect(
        EnergyDashboardService.startOfWeek(DateTime(2026, 3, 16)),
        DateTime(2026, 3, 16),
      );
    });

    test('crosses month and year boundaries', () {
      // Wednesday 2026-04-01 belongs to the week of Monday 2026-03-30.
      expect(
        EnergyDashboardService.startOfWeek(DateTime(2026, 4, 1)),
        DateTime(2026, 3, 30),
      );
      // Thursday 2026-01-01 belongs to the week of Monday 2025-12-29.
      expect(
        EnergyDashboardService.startOfWeek(DateTime(2026, 1, 1)),
        DateTime(2025, 12, 29),
      );
      // Leap day: Sunday 2032-02-29.
      expect(
        EnergyDashboardService.startOfWeek(DateTime(2032, 2, 29)),
        DateTime(2032, 2, 23),
      );
    });

    test('stays on midnight around daylight saving changes', () {
      // Last Sundays of March/October (EU) and the US switch dates.
      for (final sunday in <DateTime>[
        DateTime(2026, 3, 29),
        DateTime(2026, 10, 25),
        DateTime(2026, 3, 8),
        DateTime(2026, 11, 1),
      ]) {
        final monday = EnergyDashboardService.startOfWeek(sunday);
        expect(monday.weekday, DateTime.monday);
        expect(monday.hour, 0);
        expect(monday.minute, 0);
        expect(monday, DateTime(sunday.year, sunday.month, sunday.day - 6));
        // The Monday right after belongs to the next week.
        final next = DateTime(sunday.year, sunday.month, sunday.day + 1, 12);
        expect(
          EnergyDashboardService.startOfWeek(next),
          DateTime(sunday.year, sunday.month, sunday.day + 1),
        );
      }
    });
  });

  group('load', () {
    test('defaults to today and returns its Monday-Sunday week', () async {
      // Thursday.
      final data = await serviceAt(DateTime(2026, 3, 12, 14, 30)).load();

      expect(data.day.date, DateTime(2026, 3, 12));
      expect(data.week.weekStart, DateTime(2026, 3, 9));
      expect(data.week.today, DateTime(2026, 3, 12));
      expect(data.week.days.map((d) => d.date), <DateTime>[
        for (var day = 9; day <= 15; day++) DateTime(2026, 3, day),
      ]);
      expect(data.week.days.first.date.weekday, DateTime.monday);
      expect(data.week.days.last.date.weekday, DateTime.sunday);
      expect(identical(data.day, data.week.days[3]), isTrue);
      expect(intakeRequests.single, <DateTime>[
        DateTime(2026, 3, 9),
        DateTime(2026, 3, 16),
      ]);
    });

    test('a Sunday is the last day of its week, not the first', () async {
      final data = await serviceAt(
        DateTime(2026, 3, 15, 9),
      ).load(day: DateTime(2026, 3, 15, 22));

      expect(data.week.weekStart, DateTime(2026, 3, 9));
      expect(identical(data.day, data.week.days[6]), isTrue);
      expect(data.week.elapsedDays, 7);
    });

    test('builds a week that spans two months and two years', () async {
      final data = await serviceAt(
        DateTime(2026, 1, 1, 10),
      ).load(day: DateTime(2026, 1, 1));

      expect(data.week.days.map((d) => d.date), <DateTime>[
        DateTime(2025, 12, 29),
        DateTime(2025, 12, 30),
        DateTime(2025, 12, 31),
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 2),
        DateTime(2026, 1, 3),
        DateTime(2026, 1, 4),
      ]);
      expect(data.day.date, DateTime(2026, 1, 1));
    });

    test(
      'weeks containing a clock change still have seven midnights',
      () async {
        for (final day in <DateTime>[
          DateTime(2026, 3, 29),
          DateTime(2026, 10, 25),
          DateTime(2026, 3, 8),
          DateTime(2026, 11, 1),
        ]) {
          final data = await serviceAt(day).load(day: day);
          final dates = data.week.days.map((d) => d.date).toList();
          expect(dates, hasLength(7));
          for (var i = 0; i < 7; i++) {
            expect(dates[i].hour, 0, reason: '${dates[i]}');
            expect(dates[i].weekday, i + 1);
          }
          expect(dates.map((d) => d.day).toSet(), hasLength(7));
          expect(data.day.date, day);
        }
      },
    );

    test('combines intake, goals and the effective activity', () async {
      store.goals = const CalorieGoals(dailyKcal: 2000, weeklyKcal: 13000);
      addMeals(DateTime(2026, 3, 9), 1800, count: 3);
      addMeals(DateTime(2026, 3, 10), 2300, count: 4);
      // Outside of the week: must not leak in.
      addMeals(DateTime(2026, 3, 8), 5000);
      addMeals(DateTime(2026, 3, 16), 5000);

      await store.upsert(
        _activity(
          DateTime(2026, 3, 9),
          ActivitySource.healthConnect,
          activeKcal: 400,
          totalKcal: 2200,
          steps: 8000,
        ),
      );
      // Manual wins over Health Connect on Tuesday, and is not summed.
      await store.upsert(
        _activity(
          DateTime(2026, 3, 10),
          ActivitySource.healthConnect,
          activeKcal: 500,
          totalKcal: 2400,
        ),
      );
      await store.upsert(
        _activity(
          DateTime(2026, 3, 10),
          ActivitySource.manual,
          activeKcal: 300,
        ),
      );

      final data = await serviceAt(
        DateTime(2026, 3, 10, 20),
      ).load(day: DateTime(2026, 3, 9));

      expect(data.goals.dailyKcal, 2000);
      expect(data.goals.weeklyKcal, 13000);

      final monday = data.day;
      expect(monday.consumedKcal, 1800);
      expect(monday.mealsCount, 3);
      expect(monday.goalKcal, 2000);
      expect(monday.remainingKcal, 200);
      expect(monday.activeBurnedKcal, 400);
      expect(monday.totalBurnedKcal, 2200);
      expect(monday.netKcal, -400);

      final tuesday = data.week.days[1];
      expect(tuesday.activity!.source, ActivitySource.manual);
      expect(tuesday.activeBurnedKcal, 300);
      expect(tuesday.totalBurnedKcal, isNull);
      expect(tuesday.netKcal, isNull);
      expect(tuesday.remainingKcal, -300);

      final week = data.week;
      expect(week.goalKcal, 13000);
      expect(week.consumedKcal, 4100);
      expect(week.remainingKcal, 8900);
      expect(week.daysWithMeals, 2);
      expect(week.elapsedDays, 2);
      expect(week.daysWithActiveBurned, 2);
      expect(week.activeBurnedKcal, 700);
      expect(week.daysWithTotalBurned, 1);
      expect(week.totalBurnedKcal, 2200);
      // Net only covers Monday, the single day with total expenditure.
      expect(week.netKcal, -400);
      expect(week.isNetComplete, isFalse);
      expect(week.daysWithSteps, 1);
      expect(week.steps, 8000);
    });

    test('missing data stays missing instead of becoming zero', () async {
      final data = await serviceAt(DateTime(2026, 3, 12)).load();

      expect(data.goals.dailyKcal, isNull);
      expect(data.day.goalKcal, isNull);
      expect(data.day.remainingKcal, isNull);
      expect(data.day.hasMeals, isFalse);
      expect(data.day.consumedKcal, 0);
      expect(data.day.activity, isNull);
      expect(data.day.activeBurnedKcal, isNull);
      expect(data.day.totalBurnedKcal, isNull);
      expect(data.day.netKcal, isNull);

      final week = data.week;
      expect(week.goalKcal, isNull);
      expect(week.remainingKcal, isNull);
      expect(week.daysWithMeals, 0);
      expect(week.daysWithActiveBurned, 0);
      expect(week.activeBurnedKcal, isNull);
      expect(week.daysWithTotalBurned, 0);
      expect(week.totalBurnedKcal, isNull);
      expect(week.netKcal, isNull);
      expect(week.isNetComplete, isFalse);
      expect(week.steps, isNull);
      expect(week.distanceMeters, isNull);
      expect(week.activeMinutes, isNull);
    });

    test('daily and weekly goals are applied independently', () async {
      store.goals = const CalorieGoals(weeklyKcal: 12000);
      addMeals(DateTime(2026, 3, 9), 1500);

      var data = await serviceAt(DateTime(2026, 3, 9)).load();
      expect(data.day.goalKcal, isNull);
      expect(data.day.remainingKcal, isNull);
      expect(data.week.goalKcal, 12000);
      expect(data.week.remainingKcal, 10500);

      store.goals = const CalorieGoals(dailyKcal: 1800);
      data = await serviceAt(DateTime(2026, 3, 9)).load();
      expect(data.day.remainingKcal, 300);
      expect(data.week.days.every((d) => d.goalKcal == 1800), isTrue);
      // No weekly goal is derived from the daily one.
      expect(data.week.goalKcal, isNull);
      expect(data.week.remainingKcal, isNull);
    });

    test('a past week is fully elapsed, a future week not at all', () async {
      final now = DateTime(2026, 3, 12);

      final past = await serviceAt(now).load(day: DateTime(2026, 3, 4));
      expect(past.week.weekStart, DateTime(2026, 3, 2));
      expect(past.week.elapsedDays, 7);
      expect(past.week.today, now);

      final future = await serviceAt(now).load(day: DateTime(2026, 3, 18));
      expect(future.week.weekStart, DateTime(2026, 3, 16));
      expect(future.week.elapsedDays, 0);
      expect(future.week.isNetComplete, isFalse);
    });

    test('net is complete only when every elapsed day has a total', () async {
      // Wednesday: Monday..Wednesday elapsed.
      final now = DateTime(2026, 3, 11, 21);
      for (var day = 9; day <= 11; day++) {
        addMeals(DateTime(2026, 3, day), 2000);
      }
      await store.upsert(
        _activity(DateTime(2026, 3, 9), ActivitySource.manual, totalKcal: 2500),
      );
      await store.upsert(
        _activity(
          DateTime(2026, 3, 10),
          ActivitySource.manual,
          totalKcal: 2100,
        ),
      );

      var week = (await serviceAt(now).load()).week;
      expect(week.elapsedDays, 3);
      expect(week.daysWithTotalBurned, 2);
      expect(week.netKcal, -600);
      expect(week.isNetComplete, isFalse);

      await store.upsert(
        _activity(
          DateTime(2026, 3, 11),
          ActivitySource.manual,
          totalKcal: 1900,
        ),
      );
      week = (await serviceAt(now).load()).week;
      expect(week.daysWithTotalBurned, 3);
      expect(week.netKcal, -500);
      expect(week.isNetComplete, isTrue);
    });

    test('accepts intake keyed by any time of the day', () async {
      meals[DateTime(2026, 3, 9, 13, 5)] = DailySummary(
        date: DateTime(2026, 3, 9),
        mealsCount: 2,
        totalKcal: 900,
      );
      final service = EnergyDashboardService(
        store: store,
        now: () => DateTime(2026, 3, 9),
        loadIntake: (start, end) async => meals,
      );

      final data = await service.load();
      expect(data.day.consumedKcal, 900);
      expect(data.day.mealsCount, 2);
    });

    test('exposes the store it was built with', () {
      expect(serviceAt(DateTime(2026, 3, 9)).store, same(store));
    });
  });
}
