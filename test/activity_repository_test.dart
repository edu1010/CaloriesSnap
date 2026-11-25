import 'package:calorie_snap/data/repositories/activity_repository.dart';
import 'package:calorie_snap/models/calorie_goals.dart';
import 'package:calorie_snap/models/daily_activity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DailyActivity _activity(
  DateTime date,
  ActivitySource source, {
  double? activeKcal,
  double? totalKcal,
  int? steps,
  double? distanceMeters,
  int? activeMinutes,
  String? origin,
}) {
  return DailyActivity(
    date: date,
    source: source,
    updatedAt: DateTime(2026, 3, 10, 12, 30),
    activeKcal: activeKcal,
    totalKcal: totalKcal,
    steps: steps,
    distanceMeters: distanceMeters,
    activeMinutes: activeMinutes,
    origin: origin,
  );
}

void main() {
  sqfliteFfiInit();

  late Database database;
  late SqliteActivityStore store;

  setUp(() async {
    store = SqliteActivityStore(
      openDatabaseOverride: () async {
        database = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: SqliteActivityStore.schemaVersion,
            onCreate: SqliteActivityStore.createSchema,
            singleInstance: false,
          ),
        );
        return database;
      },
    );
    await store.init();
  });

  tearDown(() async {
    await store.close();
  });

  group('schema', () {
    test('is created when the override opens a bare database', () async {
      final bare = SqliteActivityStore(
        openDatabaseOverride:
            () => databaseFactoryFfi.openDatabase(
              inMemoryDatabasePath,
              options: OpenDatabaseOptions(singleInstance: false),
            ),
      );
      await bare.init();
      await bare.saveGoals(const CalorieGoals(dailyKcal: 1800));
      expect((await bare.loadGoals()).dailyKcal, 1800);
      await bare.close();
    });

    test('init is idempotent and lazy', () async {
      var opened = 0;
      final lazy = SqliteActivityStore(
        openDatabaseOverride: () {
          opened++;
          return databaseFactoryFfi.openDatabase(
            inMemoryDatabasePath,
            options: OpenDatabaseOptions(singleInstance: false),
          );
        },
      );
      expect((await lazy.loadGoals()).dailyKcal, isNull);
      await lazy.init();
      expect(opened, 1);
      await lazy.close();
    });
  });

  group('goals', () {
    test('are empty by default', () async {
      final goals = await store.loadGoals();
      expect(goals.dailyKcal, isNull);
      expect(goals.weeklyKcal, isNull);
    });

    test('persist both values independently', () async {
      await store.saveGoals(
        const CalorieGoals(dailyKcal: 2000, weeklyKcal: 13000),
      );
      final goals = await store.loadGoals();
      expect(goals.dailyKcal, 2000);
      // Not 7 x daily: the weekly goal is its own number.
      expect(goals.weeklyKcal, 13000);
    });

    test('weekly goal can exist without a daily goal', () async {
      await store.saveGoals(const CalorieGoals(weeklyKcal: 12500.5));
      final goals = await store.loadGoals();
      expect(goals.dailyKcal, isNull);
      expect(goals.weeklyKcal, 12500.5);
    });

    test('a null field clears only that goal', () async {
      await store.saveGoals(
        const CalorieGoals(dailyKcal: 2000, weeklyKcal: 13000),
      );
      await store.saveGoals(const CalorieGoals(weeklyKcal: 13000));
      var goals = await store.loadGoals();
      expect(goals.dailyKcal, isNull);
      expect(goals.weeklyKcal, 13000);

      await store.saveGoals(CalorieGoals.empty);
      goals = await store.loadGoals();
      expect(goals.dailyKcal, isNull);
      expect(goals.weeklyKcal, isNull);
    });

    test('rejects invalid values and keeps the stored ones', () async {
      await store.saveGoals(
        const CalorieGoals(dailyKcal: 2000, weeklyKcal: 13000),
      );

      for (final bad in const <CalorieGoals>[
        CalorieGoals(dailyKcal: 0),
        CalorieGoals(dailyKcal: -100),
        CalorieGoals(dailyKcal: double.nan),
        CalorieGoals(dailyKcal: double.infinity),
        CalorieGoals(dailyKcal: CalorieGoals.maxDailyKcal + 1),
        CalorieGoals(weeklyKcal: 0),
        CalorieGoals(weeklyKcal: -1),
        CalorieGoals(weeklyKcal: CalorieGoals.maxWeeklyKcal + 1),
        CalorieGoals(dailyKcal: 2000, weeklyKcal: double.nan),
      ]) {
        await expectLater(store.saveGoals(bad), throwsArgumentError);
      }

      final goals = await store.loadGoals();
      expect(goals.dailyKcal, 2000);
      expect(goals.weeklyKcal, 13000);
    });
  });

  group('activity records', () {
    final day = DateTime(2026, 3, 9);

    test('round-trip every field and keep missing metrics null', () async {
      await store.upsert(
        _activity(
          day,
          ActivitySource.healthConnect,
          activeKcal: 412.5,
          totalKcal: 2301.25,
          steps: 9123,
          distanceMeters: 6540.5,
          activeMinutes: 47,
          origin: 'com.example.watch',
        ),
      );
      await store.upsert(
        _activity(DateTime(2026, 3, 10), ActivitySource.manual, steps: 0),
      );

      final full = (await store.recordsForDay(day)).single;
      expect(full.date, day);
      expect(full.source, ActivitySource.healthConnect);
      expect(full.updatedAt, DateTime(2026, 3, 10, 12, 30));
      expect(full.activeKcal, 412.5);
      expect(full.totalKcal, 2301.25);
      expect(full.steps, 9123);
      expect(full.distanceMeters, 6540.5);
      expect(full.activeMinutes, 47);
      expect(full.origin, 'com.example.watch');

      final sparse = (await store.recordsForDay(DateTime(2026, 3, 10))).single;
      expect(sparse.steps, 0);
      expect(sparse.activeKcal, isNull);
      expect(sparse.totalKcal, isNull);
      expect(sparse.distanceMeters, isNull);
      expect(sparse.activeMinutes, isNull);
      expect(sparse.origin, isNull);
    });

    test('normalise the date to local midnight', () async {
      await store.upsert(
        _activity(
          DateTime(2026, 3, 9, 23, 59),
          ActivitySource.manual,
          steps: 10,
        ),
      );
      final records = await store.recordsForDay(DateTime(2026, 3, 9, 7));
      expect(records.single.date, day);
      expect(await store.recordsForDay(DateTime(2026, 3, 10)), isEmpty);
    });

    test('upsert replaces the record of the same day and source', () async {
      await store.upsert(
        _activity(day, ActivitySource.manual, steps: 100, activeKcal: 50),
      );
      await store.upsert(_activity(day, ActivitySource.manual, steps: 200));

      final record = (await store.recordsForDay(day)).single;
      expect(record.steps, 200);
      expect(record.activeKcal, isNull);
    });

    test('each source keeps its own record, listed by priority', () async {
      await store.upsert(_activity(day, ActivitySource.csvImport, steps: 3));
      await store.upsert(_activity(day, ActivitySource.manual, steps: 1));
      await store.upsert(
        _activity(day, ActivitySource.healthConnect, steps: 2),
      );

      final records = await store.recordsForDay(day);
      expect(records.map((r) => r.source), <ActivitySource>[
        ActivitySource.manual,
        ActivitySource.healthConnect,
        ActivitySource.csvImport,
      ]);
      expect(records.map((r) => r.steps), <int>[1, 2, 3]);
    });

    test('rejects invalid or empty records', () async {
      final invalid = <DailyActivity>[
        _activity(day, ActivitySource.manual),
        _activity(day, ActivitySource.manual, activeKcal: -1),
        _activity(day, ActivitySource.manual, totalKcal: double.nan),
        _activity(day, ActivitySource.manual, steps: 300001),
        _activity(day, ActivitySource.manual, activeMinutes: 1441),
        _activity(day, ActivitySource.manual, distanceMeters: 1000001),
        _activity(day, ActivitySource.manual, activeKcal: 900, totalKcal: 800),
      ];
      for (final record in invalid) {
        await expectLater(store.upsert(record), throwsArgumentError);
      }
      expect(await store.recordsForDay(day), isEmpty);
    });

    test('rows with an unknown source key are ignored', () async {
      await store.upsert(_activity(day, ActivitySource.csvImport, steps: 5));
      await database.insert('daily_activity', <String, Object?>{
        'date_key': '2026-03-09',
        'source': 'some_future_source',
        'steps': 99999,
        'updated_at': DateTime(2026, 3, 9).toIso8601String(),
      });

      expect((await store.recordsForDay(day)).single.steps, 5);
      final effective = await store.effectiveForRange(
        day,
        DateTime(2026, 3, 10),
      );
      expect(effective[day]!.steps, 5);
    });
  });

  group('effectiveForRange', () {
    final monday = DateTime(2026, 3, 9);
    final nextMonday = DateTime(2026, 3, 16);

    test('picks one source per day by priority and never sums', () async {
      // Monday: all three sources.
      await store.upsert(
        _activity(monday, ActivitySource.csvImport, activeKcal: 300),
      );
      await store.upsert(
        _activity(monday, ActivitySource.healthConnect, activeKcal: 200),
      );
      await store.upsert(
        _activity(monday, ActivitySource.manual, activeKcal: 100),
      );
      // Tuesday: Health Connect and CSV.
      final tuesday = DateTime(2026, 3, 10);
      await store.upsert(
        _activity(tuesday, ActivitySource.csvImport, activeKcal: 300),
      );
      await store.upsert(
        _activity(tuesday, ActivitySource.healthConnect, activeKcal: 200),
      );
      // Wednesday: CSV only.
      final wednesday = DateTime(2026, 3, 11);
      await store.upsert(
        _activity(wednesday, ActivitySource.csvImport, activeKcal: 300),
      );

      final effective = await store.effectiveForRange(monday, nextMonday);
      expect(effective.keys, <DateTime>[monday, tuesday, wednesday]);
      expect(effective[monday]!.source, ActivitySource.manual);
      expect(effective[monday]!.activeKcal, 100);
      expect(effective[tuesday]!.source, ActivitySource.healthConnect);
      expect(effective[tuesday]!.activeKcal, 200);
      expect(effective[wednesday]!.source, ActivitySource.csvImport);
      // Days without any record stay absent.
      expect(effective.containsKey(DateTime(2026, 3, 12)), isFalse);
    });

    test('the chosen record is used whole, gaps are not back-filled', () async {
      await store.upsert(_activity(monday, ActivitySource.manual, steps: 4000));
      await store.upsert(
        _activity(
          monday,
          ActivitySource.healthConnect,
          activeKcal: 350,
          totalKcal: 2200,
        ),
      );

      final record =
          (await store.effectiveForRange(monday, nextMonday))[monday]!;
      expect(record.source, ActivitySource.manual);
      expect(record.steps, 4000);
      expect(record.activeKcal, isNull);
      expect(record.totalKcal, isNull);
    });

    test('deleting the manual record reveals the imported one', () async {
      await store.upsert(
        _activity(monday, ActivitySource.manual, activeKcal: 100),
      );
      await store.upsert(
        _activity(monday, ActivitySource.healthConnect, activeKcal: 200),
      );

      await store.delete(DateTime(2026, 3, 9, 18), ActivitySource.manual);

      final effective = await store.effectiveForRange(monday, nextMonday);
      expect(effective[monday]!.source, ActivitySource.healthConnect);
      expect(effective[monday]!.activeKcal, 200);

      await store.delete(monday, ActivitySource.healthConnect);
      expect(await store.effectiveForRange(monday, nextMonday), isEmpty);
    });

    test('start is inclusive and end is exclusive', () async {
      await store.upsert(
        _activity(DateTime(2026, 3, 8), ActivitySource.manual, steps: 1),
      );
      await store.upsert(_activity(monday, ActivitySource.manual, steps: 2));
      await store.upsert(
        _activity(DateTime(2026, 3, 15), ActivitySource.manual, steps: 3),
      );
      await store.upsert(
        _activity(nextMonday, ActivitySource.manual, steps: 4),
      );

      final effective = await store.effectiveForRange(monday, nextMonday);
      expect(effective.values.map((r) => r.steps), <int>[2, 3]);
    });

    test('works across a year boundary', () async {
      await store.upsert(
        _activity(DateTime(2025, 12, 31), ActivitySource.manual, steps: 1),
      );
      await store.upsert(
        _activity(DateTime(2026, 1, 1), ActivitySource.manual, steps: 2),
      );

      final effective = await store.effectiveForRange(
        DateTime(2025, 12, 29),
        DateTime(2026, 1, 5),
      );
      expect(effective.keys, <DateTime>[
        DateTime(2025, 12, 31),
        DateTime(2026, 1, 1),
      ]);
    });
  });

  group('replaceRange', () {
    final start = DateTime(2026, 3, 9);
    final end = DateTime(2026, 3, 16);

    test('removes stale days of that source inside the range only', () async {
      // Before the range, inside (two days), and after it.
      await store.upsert(
        _activity(DateTime(2026, 3, 8), ActivitySource.healthConnect, steps: 8),
      );
      await store.upsert(
        _activity(DateTime(2026, 3, 9), ActivitySource.healthConnect, steps: 9),
      );
      await store.upsert(
        _activity(
          DateTime(2026, 3, 12),
          ActivitySource.healthConnect,
          steps: 12,
        ),
      );
      await store.upsert(
        _activity(
          DateTime(2026, 3, 16),
          ActivitySource.healthConnect,
          steps: 16,
        ),
      );

      await store.replaceRange(ActivitySource.healthConnect, start, end, [
        _activity(
          DateTime(2026, 3, 9),
          ActivitySource.healthConnect,
          steps: 900,
        ),
        _activity(
          DateTime(2026, 3, 10),
          ActivitySource.healthConnect,
          steps: 1000,
        ),
      ]);

      final all = await store.effectiveForRange(
        DateTime(2026, 3, 1),
        DateTime(2026, 4, 1),
      );
      expect(
        all.map((date, record) => MapEntry(date.day, record.steps)),
        <int, int?>{8: 8, 9: 900, 10: 1000, 16: 16},
      );
    });

    test('leaves the other sources alone', () async {
      final day = DateTime(2026, 3, 10);
      await store.upsert(_activity(day, ActivitySource.manual, steps: 1));
      await store.upsert(_activity(day, ActivitySource.csvImport, steps: 3));
      await store.upsert(
        _activity(day, ActivitySource.healthConnect, steps: 2),
      );

      await store.replaceRange(
        ActivitySource.healthConnect,
        start,
        end,
        <DailyActivity>[],
      );

      final records = await store.recordsForDay(day);
      expect(records.map((r) => r.source), <ActivitySource>[
        ActivitySource.manual,
        ActivitySource.csvImport,
      ]);
    });

    test('is atomic: a bad batch changes nothing', () async {
      await store.upsert(
        _activity(DateTime(2026, 3, 9), ActivitySource.healthConnect, steps: 9),
      );

      final batches = <List<DailyActivity>>[
        // Invalid metric.
        [
          _activity(
            DateTime(2026, 3, 10),
            ActivitySource.healthConnect,
            steps: 10,
          ),
          _activity(
            DateTime(2026, 3, 11),
            ActivitySource.healthConnect,
            steps: -1,
          ),
        ],
        // Wrong source.
        [_activity(DateTime(2026, 3, 10), ActivitySource.manual, steps: 10)],
        // Outside of the range.
        [
          _activity(
            DateTime(2026, 3, 16),
            ActivitySource.healthConnect,
            steps: 10,
          ),
        ],
        // No metric.
        [_activity(DateTime(2026, 3, 10), ActivitySource.healthConnect)],
      ];
      for (final batch in batches) {
        await expectLater(
          store.replaceRange(ActivitySource.healthConnect, start, end, batch),
          throwsArgumentError,
        );
      }

      final all = await store.effectiveForRange(start, end);
      expect(all.keys, <DateTime>[DateTime(2026, 3, 9)]);
      expect(all.values.single.steps, 9);
    });
  });

  group('sync state', () {
    test('is null until saved', () async {
      expect(await store.loadSyncState(ActivitySource.healthConnect), isNull);
    });

    test('round-trips and is kept per source', () async {
      await store.saveSyncState(
        ActivitySyncState(
          source: ActivitySource.healthConnect,
          lastSuccessAt: DateTime(2026, 3, 9, 8, 15),
          lastAttemptAt: DateTime(2026, 3, 10, 9, 45, 30),
          lastError: 'permissionDenied',
          lastImportedDays: 12,
        ),
      );

      final state = (await store.loadSyncState(ActivitySource.healthConnect))!;
      expect(state.source, ActivitySource.healthConnect);
      expect(state.lastSuccessAt, DateTime(2026, 3, 9, 8, 15));
      expect(state.lastAttemptAt, DateTime(2026, 3, 10, 9, 45, 30));
      expect(state.lastError, 'permissionDenied');
      expect(state.lastImportedDays, 12);
      expect(await store.loadSyncState(ActivitySource.csvImport), isNull);
    });

    test('saving again replaces the previous state', () async {
      await store.saveSyncState(
        const ActivitySyncState(
          source: ActivitySource.healthConnect,
          lastError: 'failed',
        ),
      );
      await store.saveSyncState(
        ActivitySyncState(
          source: ActivitySource.healthConnect,
          lastAttemptAt: DateTime(2026, 3, 10),
        ),
      );

      final state = (await store.loadSyncState(ActivitySource.healthConnect))!;
      expect(state.lastError, isNull);
      expect(state.lastSuccessAt, isNull);
      expect(state.lastImportedDays, isNull);
      expect(state.lastAttemptAt, DateTime(2026, 3, 10));
    });
  });
}
