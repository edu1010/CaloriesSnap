// Widget tests for the goals & activity dashboard, driven by an in-memory
// store and a fake sync source so no plugin or database is touched.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calorie_snap/core/l10n/app_localizations.dart';
import 'package:calorie_snap/features/activity/activity_dashboard_screen.dart';
import 'package:calorie_snap/features/activity/csv_import_card.dart';
import 'package:calorie_snap/models/calorie_goals.dart';
import 'package:calorie_snap/models/daily_activity.dart';
import 'package:calorie_snap/models/daily_summary.dart';
import 'package:calorie_snap/services/activity/activity_store.dart';
import 'package:calorie_snap/services/activity/activity_sync_coordinator.dart';
import 'package:calorie_snap/services/activity/activity_sync_source.dart';
import 'package:calorie_snap/services/activity/energy_dashboard_service.dart';

/// Wednesday; its week is Monday 2 – Sunday 8 March 2026, three days elapsed.
final DateTime _now = DateTime(2026, 3, 4, 10, 30);
final DateTime _monday = DateTime(2026, 3, 2);
final DateTime _tuesday = DateTime(2026, 3, 3);
final DateTime _today = DateTime(2026, 3, 4);

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

class FakeActivityStore implements ActivityStore {
  CalorieGoals goals = CalorieGoals.empty;
  final List<DailyActivity> records = <DailyActivity>[];
  final Map<ActivitySource, ActivitySyncState> syncStates =
      <ActivitySource, ActivitySyncState>{};

  DailyActivity? record(DateTime day, ActivitySource source) {
    for (final record in records) {
      if (_day(record.date) == _day(day) && record.source == source) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<CalorieGoals> loadGoals() async => goals;

  @override
  Future<void> saveGoals(CalorieGoals goals) async {
    if (!goals.isValid) {
      throw ArgumentError('invalid goals');
    }
    this.goals = goals;
  }

  @override
  Future<void> upsert(DailyActivity activity) async {
    if (activity.invalidField != null || !activity.hasAnyMetric) {
      throw ArgumentError('invalid activity');
    }
    records.removeWhere(
      (r) => _day(r.date) == _day(activity.date) && r.source == activity.source,
    );
    records.add(activity);
  }

  @override
  Future<void> replaceRange(
    ActivitySource source,
    DateTime startInclusive,
    DateTime endExclusive,
    List<DailyActivity> days,
  ) async {
    records.removeWhere(
      (r) =>
          r.source == source &&
          !r.date.isBefore(startInclusive) &&
          r.date.isBefore(endExclusive),
    );
    records.addAll(days);
  }

  @override
  Future<void> delete(DateTime day, ActivitySource source) async {
    records.removeWhere((r) => _day(r.date) == _day(day) && r.source == source);
  }

  @override
  Future<List<DailyActivity>> recordsForDay(DateTime day) async {
    return records.where((r) => _day(r.date) == _day(day)).toList();
  }

  @override
  Future<Map<DateTime, DailyActivity>> effectiveForRange(
    DateTime startInclusive,
    DateTime endExclusive,
  ) async {
    final result = <DateTime, DailyActivity>{};
    for (final record in records) {
      final date = _day(record.date);
      if (date.isBefore(startInclusive) || !date.isBefore(endExclusive)) {
        continue;
      }
      final current = result[date];
      if (current == null || record.source.index < current.source.index) {
        result[date] = record;
      }
    }
    return result;
  }

  @override
  Future<ActivitySyncState?> loadSyncState(ActivitySource source) async {
    return syncStates[source];
  }

  @override
  Future<void> saveSyncState(ActivitySyncState state) async {
    syncStates[state.source] = state;
  }
}

class FakeSyncSource implements ActivitySyncSource {
  FakeSyncSource({
    this.availability = ActivitySyncAvailability.available,
    this.permissionsGranted = true,
    this.grantOnRequest = false,
  });

  ActivitySyncAvailability availability;
  bool permissionsGranted;
  bool grantOnRequest;
  List<DailyActivity> days = <DailyActivity>[];
  String? failure;
  Completer<void>? gate;
  int setupOpened = 0;
  int fetchCalls = 0;

  @override
  ActivitySource get source => ActivitySource.healthConnect;

  @override
  Future<ActivitySyncAvailability> checkAvailability() async => availability;

  @override
  Future<bool> hasPermissions() async => permissionsGranted;

  @override
  Future<bool> requestPermissions() async {
    permissionsGranted = grantOnRequest;
    return grantOnRequest;
  }

  @override
  Future<List<DailyActivity>> fetchDays(
    DateTime startInclusive,
    DateTime endExclusive,
  ) async {
    fetchCalls++;
    await gate?.future;
    if (failure != null) {
      throw ActivitySyncException(failure!);
    }
    return days;
  }

  @override
  Future<bool> openProviderSetup() async {
    setupOpened++;
    return true;
  }
}

DailyActivity _activity(
  DateTime date,
  ActivitySource source, {
  double? active,
  double? total,
  int? steps,
  double? meters,
  int? minutes,
  String? origin,
}) {
  return DailyActivity(
    date: date,
    source: source,
    updatedAt: _now,
    activeKcal: active,
    totalKcal: total,
    steps: steps,
    distanceMeters: meters,
    activeMinutes: minutes,
    origin: origin,
  );
}

Map<DateTime, DailySummary> _intake(Map<DateTime, (int, double)> values) {
  return <DateTime, DailySummary>{
    for (final entry in values.entries)
      entry.key: DailySummary(
        date: entry.key,
        mealsCount: entry.value.$1,
        totalKcal: entry.value.$2,
      ),
  };
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required FakeActivityStore store,
  FakeSyncSource? source,
  Map<DateTime, DailySummary> intake = const <DateTime, DailySummary>{},
  Locale locale = const Locale('en'),
  Size size = const Size(1200, 800),
  double textScale = 1,
  CsvFilePicker? pickCsvFile,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final service = EnergyDashboardService(
    loadIntake: (start, end) async {
      return <DateTime, DailySummary>{
        for (final entry in intake.entries)
          if (!entry.key.isBefore(start) && entry.key.isBefore(end))
            entry.key: entry.value,
      };
    },
    store: store,
    now: () => _now,
  );
  final coordinator = ActivitySyncCoordinator(
    store: store,
    source:
        source ??
        FakeSyncSource(
          availability: ActivitySyncAvailability.unsupportedPlatform,
        ),
    now: () => _now,
  );

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        );
      },
      home: ActivityDashboardScreen(
        dashboardService: service,
        syncCoordinator: coordinator,
        pickCsvFile: pickCsvFile,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _in(String key, String text) {
  return find.descendant(
    of: find.byKey(Key(key)),
    matching: find.text(text),
    matchRoot: true,
  );
}

Finder _inContaining(String key, String text) {
  return find.descendant(
    of: find.byKey(Key(key)),
    matching: find.textContaining(text),
    matchRoot: true,
  );
}

PickedCsvFile _csvFile(String content, {String name = 'activity.csv'}) {
  final bytes = utf8.encode(content);
  return PickedCsvFile(
    name: name,
    size: bytes.length,
    readBytes: () async => bytes,
  );
}

void main() {
  group('missing data', () {
    testWidgets('no goals and no activity read as missing, never as zero', (
      tester,
    ) async {
      await _pumpDashboard(tester, store: FakeActivityStore());

      expect(_in('daily_goal_line', 'Not set'), findsOneWidget);
      expect(_in('weekly_goal_line', 'Not set'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      expect(find.byKey(const Key('today_no_activity')), findsOneWidget);
      expect(find.text('No activity data for today'), findsOneWidget);
      expect(_in('today_panel', 'No daily goal set.'), findsOneWidget);
      expect(find.byKey(const Key('today_net')), findsNothing);
      expect(find.byKey(const Key('week_net')), findsNothing);
      expect(
        _in(
          'today_panel',
          'Net energy unavailable: total expenditure unknown.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('week_net_unavailable')), findsOneWidget);

      expect(_in('week_active', '— No data'), findsOneWidget);
      expect(_in('week_active', 'Data for 0 of 3 days'), findsOneWidget);
      expect(_in('week_total', '— No data'), findsOneWidget);
      expect(
        _in('week_consumed', 'Meals logged on 0 of 7 days'),
        findsOneWidget,
      );
      expect(_in('week_panel', 'No weekly goal set.'), findsOneWidget);

      // Burned kcal is never rendered as a number when there is no record.
      expect(_inContaining('week_active', '0 kcal'), findsNothing);
      expect(_inContaining('week_total', '0 kcal'), findsNothing);
      expect(_in('week_day_1', '—'), findsNWidgets(2));
      // Future days are blank.
      expect(_in('week_day_7', '—'), findsNothing);
    });

    testWidgets('activity with only active kcal has no net energy', (
      tester,
    ) async {
      final store = FakeActivityStore();
      store.records.add(
        _activity(
          _today,
          ActivitySource.healthConnect,
          active: 320,
          steps: 8500,
          meters: 6240,
          minutes: 45,
          origin: 'com.mi.health',
        ),
      );
      await _pumpDashboard(
        tester,
        store: store,
        intake: _intake(<DateTime, (int, double)>{_today: (3, 1240)}),
      );

      expect(find.byKey(const Key('today_no_activity')), findsNothing);
      expect(_in('today_panel', '320 kcal'), findsOneWidget);
      expect(_in('today_panel', '1,240 kcal'), findsOneWidget);
      expect(_in('today_panel', '3 meals'), findsOneWidget);
      expect(_in('today_panel', 'Total burned'), findsNothing);
      expect(find.byKey(const Key('today_net')), findsNothing);
      expect(
        _in(
          'today_panel',
          'Net energy unavailable: total expenditure unknown.',
        ),
        findsOneWidget,
      );
      expect(_in('today_panel', '8,500'), findsOneWidget);
      expect(_in('today_panel', '6.24 km'), findsOneWidget);
      expect(_in('today_panel', '45 min'), findsOneWidget);
      expect(_in('today_panel', 'Data source: Health Connect'), findsOneWidget);
      expect(_in('today_panel', 'From: com.mi.health'), findsOneWidget);

      expect(_in('week_active', '320 kcal'), findsOneWidget);
      expect(_in('week_active', 'Data for 1 of 3 days'), findsOneWidget);
      expect(_in('week_total', '— No data'), findsOneWidget);
      expect(find.byKey(const Key('week_net')), findsNothing);
    });

    testWidgets('net energy is shown with total burned and flagged partial', (
      tester,
    ) async {
      final store = FakeActivityStore();
      store.records.addAll(<DailyActivity>[
        _activity(_today, ActivitySource.manual, active: 400, total: 2300),
        _activity(_tuesday, ActivitySource.csvImport, active: 250),
      ]);
      await _pumpDashboard(
        tester,
        store: store,
        intake: _intake(<DateTime, (int, double)>{
          _today: (2, 1240),
          _monday: (1, 800),
        }),
      );

      expect(_in('today_panel', '2,300 kcal'), findsOneWidget);
      expect(_in('today_net', '−1,060 kcal'), findsOneWidget);
      expect(_in('today_panel', 'Data source: Manual'), findsOneWidget);

      expect(_in('week_consumed', '2,040 kcal'), findsOneWidget);
      expect(
        _in('week_consumed', 'Meals logged on 2 of 7 days'),
        findsOneWidget,
      );
      expect(_in('week_active', '650 kcal'), findsOneWidget);
      expect(_in('week_active', 'Data for 2 of 3 days'), findsOneWidget);
      expect(_in('week_total', '2,300 kcal'), findsOneWidget);
      expect(_in('week_total', 'Data for 1 of 3 days'), findsOneWidget);
      expect(_in('week_net', '−1,060 kcal'), findsOneWidget);
      expect(
        _in('week_net', 'Partial: over 1 of 3 days with total expenditure'),
        findsOneWidget,
      );
    });

    testWidgets('net energy covers the week when every elapsed day has total', (
      tester,
    ) async {
      final store = FakeActivityStore();
      store.records.addAll(<DailyActivity>[
        _activity(_monday, ActivitySource.manual, total: 2000),
        _activity(_tuesday, ActivitySource.manual, total: 2000),
        _activity(_today, ActivitySource.manual, total: 2000),
      ]);
      await _pumpDashboard(
        tester,
        store: store,
        intake: _intake(<DateTime, (int, double)>{_today: (1, 6500)}),
      );

      expect(_in('week_net', '+500 kcal'), findsOneWidget);
      expect(_in('week_net', 'Covers all 3 elapsed days'), findsOneWidget);
      expect(_in('week_day_1', '2,000 total'), findsOneWidget);
    });
  });

  group('goals', () {
    testWidgets('remaining intake is shown for daily and weekly goals', (
      tester,
    ) async {
      final store =
          FakeActivityStore()
            ..goals = const CalorieGoals(dailyKcal: 2000, weeklyKcal: 13000);
      await _pumpDashboard(
        tester,
        store: store,
        intake: _intake(<DateTime, (int, double)>{
          _today: (3, 1240),
          _monday: (2, 800),
        }),
      );

      expect(_in('daily_goal_line', '2,000 kcal'), findsOneWidget);
      expect(_in('weekly_goal_line', '13,000 kcal'), findsOneWidget);
      expect(_in('today_panel', '760 kcal left'), findsOneWidget);
      expect(_in('today_panel', '1,240 of 2,000 kcal'), findsOneWidget);
      expect(_in('week_panel', '10,960 kcal left'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    });

    testWidgets('exceeding the goal is worded and marked with an icon', (
      tester,
    ) async {
      final store =
          FakeActivityStore()..goals = const CalorieGoals(dailyKcal: 1000);
      await _pumpDashboard(
        tester,
        store: store,
        intake: _intake(<DateTime, (int, double)>{_today: (3, 1240)}),
      );

      expect(_in('today_panel', 'Over goal by 240 kcal'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('today_panel')),
          matching: find.byIcon(Icons.warning_amber_outlined),
        ),
        findsOneWidget,
      );
      expect(_in('week_panel', 'No weekly goal set.'), findsOneWidget);
    });

    testWidgets('editor rejects invalid values and saves independent goals', (
      tester,
    ) async {
      final store = FakeActivityStore();
      await _pumpDashboard(tester, store: store);

      await _tap(tester, find.byKey(const Key('edit_goals_button')));
      final daily = find.byKey(const Key('goal_daily_field'));
      final weekly = find.byKey(const Key('goal_weekly_field'));
      final save = find.byKey(const Key('goal_save_button'));

      // Nothing is suggested.
      expect(tester.widget<TextFormField>(daily).controller!.text, isEmpty);
      expect(tester.widget<TextFormField>(weekly).controller!.text, isEmpty);

      const error = 'Enter a whole number greater than 0 and at most 20,000.';
      for (final bad in <String>['0', '-5', 'abc', '1.5', '20001']) {
        await tester.enterText(daily, bad);
        await _tap(tester, save);
        expect(find.text(error), findsOneWidget, reason: bad);
        expect(store.goals.dailyKcal, isNull, reason: bad);
      }

      await tester.enterText(daily, '2000');
      await tester.enterText(weekly, '0');
      await _tap(tester, save);
      expect(
        find.text('Enter a whole number greater than 0 and at most 140,000.'),
        findsOneWidget,
      );
      expect(store.goals.dailyKcal, isNull);

      await tester.enterText(weekly, '');
      await _tap(tester, save);

      expect(find.byType(AlertDialog), findsNothing);
      expect(store.goals.dailyKcal, 2000);
      // The weekly goal is not derived from the daily one.
      expect(store.goals.weeklyKcal, isNull);
      expect(_in('daily_goal_line', '2,000 kcal'), findsOneWidget);
      expect(_in('weekly_goal_line', 'Not set'), findsOneWidget);

      // Set the weekly goal and clear the daily one.
      await _tap(tester, find.byKey(const Key('edit_goals_button')));
      expect(tester.widget<TextFormField>(daily).controller!.text, '2000');
      await tester.enterText(daily, '');
      await tester.enterText(weekly, '15000');
      await _tap(tester, save);
      expect(store.goals.dailyKcal, isNull);
      expect(store.goals.weeklyKcal, 15000);
      expect(_in('daily_goal_line', 'Not set'), findsOneWidget);
      expect(_in('weekly_goal_line', '15,000 kcal'), findsOneWidget);
    });
  });

  group('manual activity', () {
    testWidgets('adds, validates and deletes a manual entry for today', (
      tester,
    ) async {
      final store = FakeActivityStore();
      await _pumpDashboard(tester, store: store);

      await _tap(tester, find.byKey(const Key('today_manual_button')));
      expect(find.byKey(const Key('manual_delete_button')), findsNothing);
      expect(
        find.text('Only if your device reports total expenditure'),
        findsOneWidget,
      );
      expect(
        find.textContaining('A manual entry is used instead of imported data'),
        findsOneWidget,
      );

      final save = find.byKey(const Key('manual_save_button'));
      await _tap(tester, save);
      expect(find.text('Enter at least one value.'), findsOneWidget);
      expect(store.records, isEmpty);

      final active = find.byKey(const Key('manual_activeKcal_field'));
      final total = find.byKey(const Key('manual_totalKcal_field'));
      await tester.enterText(active, '-3');
      await _tap(tester, save);
      expect(find.text('Enter a whole number, 0 or more.'), findsOneWidget);

      await tester.enterText(active, '300');
      await tester.enterText(total, '200');
      await _tap(tester, save);
      expect(
        find.text('Active burned cannot exceed total burned.'),
        findsOneWidget,
      );

      await tester.enterText(total, '99999');
      await _tap(tester, save);
      expect(find.text('Value outside the accepted range.'), findsOneWidget);
      expect(store.records, isEmpty);

      await tester.enterText(total, '2200');
      await tester.enterText(
        find.byKey(const Key('manual_distanceMeters_field')),
        '5,5',
      );
      await _tap(tester, save);

      expect(find.byType(AlertDialog), findsNothing);
      final saved = store.record(_today, ActivitySource.manual)!;
      expect(saved.activeKcal, 300);
      expect(saved.totalKcal, 2200);
      expect(saved.distanceMeters, 5500);
      expect(saved.steps, isNull);
      expect(saved.activeMinutes, isNull);
      expect(_in('today_panel', 'Data source: Manual'), findsOneWidget);
      expect(_in('today_panel', '5.5 km'), findsOneWidget);
      expect(find.text('Edit manual entry'), findsOneWidget);

      await _tap(tester, find.byKey(const Key('today_manual_button')));
      expect(tester.widget<TextField>(active).controller!.text, '300');
      await _tap(tester, find.byKey(const Key('manual_delete_button')));
      await _tap(tester, find.byKey(const Key('manual_delete_confirm_button')));

      expect(find.byType(AlertDialog), findsNothing);
      expect(store.records, isEmpty);
      expect(find.byKey(const Key('today_no_activity')), findsOneWidget);
    });

    testWidgets(
      'manual entry replaces imported data and deleting restores it',
      (tester) async {
        final store = FakeActivityStore();
        store.records.add(
          _activity(_today, ActivitySource.healthConnect, active: 320),
        );
        await _pumpDashboard(tester, store: store);
        expect(
          _in('today_panel', 'Data source: Health Connect'),
          findsOneWidget,
        );

        await _tap(tester, find.byKey(const Key('today_manual_button')));
        expect(
          find.textContaining('This day also has data from Health Connect'),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const Key('manual_activeKcal_field')),
          '500',
        );
        await _tap(tester, find.byKey(const Key('manual_save_button')));

        expect(store.records, hasLength(2));
        expect(_in('today_panel', 'Data source: Manual'), findsOneWidget);
        expect(_in('today_panel', '500 kcal'), findsOneWidget);
        // Sources are not added together.
        expect(_in('week_active', '500 kcal'), findsOneWidget);

        await _tap(tester, find.byKey(const Key('today_manual_button')));
        await _tap(tester, find.byKey(const Key('manual_delete_button')));
        await _tap(
          tester,
          find.byKey(const Key('manual_delete_confirm_button')),
        );

        expect(store.records, hasLength(1));
        expect(
          _in('today_panel', 'Data source: Health Connect'),
          findsOneWidget,
        );
        expect(_in('today_panel', '320 kcal'), findsOneWidget);
      },
    );

    testWidgets('a past day of the week can be edited from the day list', (
      tester,
    ) async {
      final store = FakeActivityStore();
      await _pumpDashboard(tester, store: store);

      await _tap(tester, find.byKey(const Key('week_day_1')));
      expect(find.textContaining('Monday, March 2'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('manual_steps_field')),
        '4000',
      );
      await _tap(tester, find.byKey(const Key('manual_save_button')));

      expect(store.record(_monday, ActivitySource.manual)!.steps, 4000);
      expect(find.byKey(const Key('today_no_activity')), findsOneWidget);
      expect(_in('week_panel', '4,000'), findsOneWidget);
      expect(_in('week_panel', 'Data for 1 of 3 days'), findsOneWidget);

      // Future days cannot be tapped.
      expect(
        tester.widget(find.byKey(const Key('week_day_7'))),
        isNot(isA<InkWell>()),
      );
    });
  });

  group('week navigation', () {
    testWidgets('moves back and forth but never past the current week', (
      tester,
    ) async {
      final store = FakeActivityStore();
      store.records.add(
        _activity(DateTime(2026, 2, 25), ActivitySource.csvImport, active: 111),
      );
      await _pumpDashboard(
        tester,
        store: store,
        intake: _intake(<DateTime, (int, double)>{
          _today: (1, 500),
          DateTime(2026, 2, 24): (2, 900),
        }),
      );

      IconButton next() {
        return tester.widget<IconButton>(
          find.byKey(const Key('next_week_button')),
        );
      }

      expect(_inContaining('week_panel', 'Mar 2 – '), findsOneWidget);
      expect(next().onPressed, isNull);

      await _tap(tester, find.byKey(const Key('previous_week_button')));
      expect(_inContaining('week_panel', 'Feb 23 – '), findsOneWidget);
      expect(next().onPressed, isNotNull);
      expect(_in('week_consumed', '900 kcal'), findsOneWidget);
      expect(_in('week_active', '111 kcal'), findsOneWidget);
      expect(_in('week_active', 'Data for 1 of 7 days'), findsOneWidget);
      // The day panel stays on today.
      expect(_in('today_panel', '500 kcal'), findsOneWidget);
      expect(_inContaining('today_panel', 'March 4'), findsOneWidget);

      await _tap(tester, find.byKey(const Key('next_week_button')));
      expect(_inContaining('week_panel', 'Mar 2 – '), findsOneWidget);
      expect(next().onPressed, isNull);
    });
  });

  group('synchronisation', () {
    testWidgets('unsupported platform explains the fallbacks', (tester) async {
      final store = FakeActivityStore();
      await _pumpDashboard(tester, store: store);

      expect(find.byKey(const Key('sync_unsupported')), findsOneWidget);
      expect(find.textContaining('only available on Android'), findsOneWidget);
      expect(find.byKey(const Key('sync_button')), findsNothing);
      expect(find.byKey(const Key('today_sync_button')), findsNothing);
      expect(_in('sync_card', 'Never synchronised'), findsOneWidget);
      expect(find.textContaining('connected'), findsNothing);

      await _tap(tester, find.text('Which apps?'));
      expect(find.textContaining('Mi Fitness (Xiaomi)'), findsOneWidget);
      expect(
        find.textContaining('does not connect directly to these service accounts'),
        findsOneWidget,
      );
    });

    testWidgets('success imports days and records the time', (tester) async {
      final store = FakeActivityStore();
      final source =
          FakeSyncSource()
            ..gate = Completer<void>()
            ..days = <DailyActivity>[
              _activity(
                _today,
                ActivitySource.healthConnect,
                active: 410,
                total: 2250,
              ),
              _activity(_tuesday, ActivitySource.healthConnect, active: 150),
            ];
      await _pumpDashboard(tester, store: store, source: source);

      expect(_in('sync_card', 'Never synchronised'), findsOneWidget);
      expect(find.byKey(const Key('today_sync_button')), findsOneWidget);

      final button = find.byKey(const Key('sync_button'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Synchronising…'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('today_sync_button')))
            .onPressed,
        isNull,
      );
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
      expect(source.fetchCalls, 1);

      source.gate!.complete();
      await tester.pumpAndSettle();

      expect(
        _in('sync_outcome', 'Synchronisation finished: data for 2 days.'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Synchronisation finished: data for 2 days.'),
        ),
        findsOneWidget,
      );
      expect(
        _inContaining('sync_card', 'Last synchronised: Mar 4, 2026'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sync_last_error')), findsNothing);
      expect(find.text('Synchronise now'), findsOneWidget);
      expect(_in('today_panel', 'Data source: Health Connect'), findsOneWidget);
      expect(_in('today_net', '−2,250 kcal'), findsOneWidget);
      expect(_in('week_active', '560 kcal'), findsOneWidget);
    });

    testWidgets('permission denied can be retried or sent to settings', (
      tester,
    ) async {
      final store = FakeActivityStore();
      final source = FakeSyncSource(permissionsGranted: false);
      await _pumpDashboard(tester, store: store, source: source);

      await _tap(tester, find.byKey(const Key('sync_button')));

      expect(
        _inContaining('sync_outcome', 'Permission denied'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('Permission denied'),
        ),
        findsOneWidget,
      );
      expect(_in('sync_card', 'Never synchronised'), findsOneWidget);
      expect(source.fetchCalls, 0);
      expect(store.records, isEmpty);
      expect(
        store.syncStates[ActivitySource.healthConnect]!.lastError,
        'permissionDenied',
      );

      await _tap(tester, find.byKey(const Key('sync_open_settings_button')));
      expect(source.setupOpened, 1);

      source
        ..grantOnRequest = true
        ..days = <DailyActivity>[
          _activity(_today, ActivitySource.healthConnect, active: 90),
        ];
      await _tap(tester, find.byKey(const Key('sync_button')));

      expect(
        _in('sync_outcome', 'Synchronisation finished: data for 1 day.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sync_open_settings_button')), findsNothing);
      expect(_in('today_panel', '90 kcal'), findsOneWidget);
    });

    testWidgets('a failed sync shows the reason and keeps the last success', (
      tester,
    ) async {
      final store = FakeActivityStore();
      store.syncStates[ActivitySource.healthConnect] = ActivitySyncState(
        source: ActivitySource.healthConnect,
        lastSuccessAt: DateTime(2026, 3, 1, 8, 15),
        lastAttemptAt: DateTime(2026, 3, 3, 9),
        lastError: 'permissionDenied',
      );
      final source = FakeSyncSource()..failure = 'provider timeout';
      await _pumpDashboard(tester, store: store, source: source);

      expect(
        _inContaining('sync_card', 'Last synchronised: Mar 1, 2026'),
        findsOneWidget,
      );
      expect(
        _inContaining(
          'sync_last_error',
          'The last attempt failed. Permission denied',
        ),
        findsOneWidget,
      );

      await _tap(tester, find.byKey(const Key('sync_button')));

      expect(
        _in('sync_outcome', 'Synchronisation failed: provider timeout'),
        findsOneWidget,
      );
      expect(
        _inContaining('sync_card', 'Last synchronised: Mar 1, 2026'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('today_no_activity')), findsOneWidget);
    });

    testWidgets('a missing provider offers its setup page', (tester) async {
      final store = FakeActivityStore();
      final source = FakeSyncSource(
        availability: ActivitySyncAvailability.providerNotInstalled,
      );
      await _pumpDashboard(tester, store: store, source: source);

      expect(
        find.text('Health Connect is not installed on this phone.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sync_button')), findsNothing);
      await _tap(tester, find.byKey(const Key('sync_setup_button')));
      expect(source.setupOpened, 1);
    });
  });

  group('CSV import', () {
    testWidgets('summarises, confirms and stores valid rows', (tester) async {
      final store = FakeActivityStore();
      await _pumpDashboard(
        tester,
        store: store,
        pickCsvFile:
            () async => _csvFile(
              'date,active_kcal,total_kcal,steps,distance_km,active_minutes\n'
              '2026-03-02,420,2310,8500,6.2,45\n'
              '2026-03-03,,,10250,,\n'
              '2026-03-04,abc,,,,\n',
            ),
      );

      await _tap(tester, find.byKey(const Key('csv_import_button')));

      expect(find.text('Confirm import'), findsOneWidget);
      expect(find.text('2 valid days'), findsOneWidget);
      expect(find.text('1 row rejected'), findsOneWidget);
      expect(find.textContaining('Line 4: '), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('manual entry or Health Connect data'),
        ),
        findsOneWidget,
      );
      expect(store.records, isEmpty);

      await _tap(tester, find.byKey(const Key('csv_confirm_button')));

      expect(store.records, hasLength(2));
      final monday = store.record(_monday, ActivitySource.csvImport)!;
      expect(monday.activeKcal, 420);
      expect(monday.origin, 'activity.csv');
      expect(find.text('Imported 2 days.'), findsOneWidget);
      expect(_in('week_active', '420 kcal'), findsOneWidget);
      expect(_in('week_active', 'Data for 1 of 3 days'), findsOneWidget);
      expect(find.byKey(const Key('today_no_activity')), findsOneWidget);
    });

    testWidgets('an invalid header shows the expected columns', (tester) async {
      final store = FakeActivityStore();
      await _pumpDashboard(
        tester,
        store: store,
        pickCsvFile: () async => _csvFile('day,kcal\n2026-03-02,420\n'),
      );

      await _tap(tester, find.byKey(const Key('csv_import_button')));

      expect(find.text('Invalid header'), findsOneWidget);
      expect(
        find.text(
          'date,active_kcal,total_kcal,steps,distance_km,active_minutes',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('csv_confirm_button')), findsNothing);
      expect(store.records, isEmpty);
    });

    testWidgets('files over 2 MB are rejected without being read', (
      tester,
    ) async {
      final store = FakeActivityStore();
      var read = false;
      await _pumpDashboard(
        tester,
        store: store,
        pickCsvFile:
            () async => PickedCsvFile(
              name: 'big.csv',
              size: 3 * 1024 * 1024,
              readBytes: () async {
                read = true;
                return <int>[];
              },
            ),
      );

      await _tap(tester, find.byKey(const Key('csv_import_button')));

      expect(
        find.text('The file is larger than 2 MB and was not imported.'),
        findsOneWidget,
      );
      expect(read, isFalse);
    });
  });

  group('localisation and layout', () {
    FakeActivityStore richStore() {
      final store =
          FakeActivityStore()
            ..goals = const CalorieGoals(dailyKcal: 2000, weeklyKcal: 14000);
      store.records.addAll(<DailyActivity>[
        _activity(
          _today,
          ActivitySource.healthConnect,
          active: 12345,
          total: 23456,
          steps: 123456,
          meters: 123456,
          minutes: 1234,
          origin: 'com.mi.health, com.strava, com.huawei.health',
        ),
        _activity(_tuesday, ActivitySource.csvImport, active: 300),
        _activity(_monday, ActivitySource.manual, total: 2100, steps: 4000),
      ]);
      return store;
    }

    final richIntake = _intake(<DateTime, (int, double)>{
      _today: (4, 18765),
      _tuesday: (3, 2100),
      _monday: (1, 950),
    });

    testWidgets('Spanish strings and number formats', (tester) async {
      final store =
          FakeActivityStore()..goals = const CalorieGoals(dailyKcal: 20000);
      await _pumpDashboard(
        tester,
        store: store,
        locale: const Locale('es'),
        intake: _intake(<DateTime, (int, double)>{_today: (1, 12400)}),
      );

      expect(find.text('Objetivos y actividad'), findsOneWidget);
      expect(_in('daily_goal_line', '20.000 kcal'), findsOneWidget);
      expect(_in('weekly_goal_line', 'Sin definir'), findsOneWidget);
      expect(_in('today_panel', 'Quedan 7.600 kcal'), findsOneWidget);
      expect(_in('today_panel', '1 comida'), findsOneWidget);
      expect(find.text('No hay datos de actividad para hoy'), findsOneWidget);
      expect(
        _in(
          'today_panel',
          'Balance neto no disponible: se desconoce el gasto total.',
        ),
        findsOneWidget,
      );
      expect(_in('week_active', '— Sin datos'), findsOneWidget);
      expect(_in('week_active', 'Datos de 0 de 3 días'), findsOneWidget);
      expect(
        _in('week_consumed', 'Comidas registradas en 1 de 7 días'),
        findsOneWidget,
      );
      expect(_in('sync_card', 'Nunca sincronizado'), findsOneWidget);
      expect(
        find.textContaining('solo está disponible en Android'),
        findsOneWidget,
      );
      expect(find.text('Importar CSV'), findsOneWidget);

      await _tap(tester, find.byKey(const Key('edit_goals_button')));
      await tester.enterText(find.byKey(const Key('goal_daily_field')), '0');
      await _tap(tester, find.byKey(const Key('goal_save_button')));
      expect(
        find.text(
          'Introduce un número entero mayor que 0 y como máximo 20.000.',
        ),
        findsOneWidget,
      );
    });

    for (final locale in const <Locale>[Locale('en'), Locale('es')]) {
      testWidgets('narrow 320x640 layout does not overflow ($locale)', (
        tester,
      ) async {
        final source = FakeSyncSource(permissionsGranted: false);
        await _pumpDashboard(
          tester,
          store: richStore(),
          source: source,
          intake: richIntake,
          locale: locale,
          size: const Size(320, 640),
          textScale: 1.6,
        );
        expect(tester.takeException(), isNull);

        final panelTop = tester.getTopLeft(
          find.byKey(const Key('today_panel')),
        );
        final weekTop = tester.getTopLeft(find.byKey(const Key('week_panel')));
        expect(weekTop.dy, greaterThan(panelTop.dy));
        expect(weekTop.dx, panelTop.dx);

        await _tap(tester, find.byKey(const Key('sync_button')));
        expect(tester.takeException(), isNull);
        ScaffoldMessenger.of(
          tester.element(find.byKey(const Key('sync_card'))),
        ).removeCurrentSnackBar();
        await tester.pumpAndSettle();

        await _tap(tester, find.byKey(const Key('sync_which_apps')));
        expect(tester.takeException(), isNull);

        await _tap(tester, find.byKey(const Key('edit_goals_button')));
        await tester.enterText(find.byKey(const Key('goal_daily_field')), 'x');
        await _tap(tester, find.byKey(const Key('goal_save_button')));
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);

        await _tap(tester, find.byKey(const Key('week_day_1')));
        expect(find.byKey(const Key('manual_delete_button')), findsOneWidget);
        await _tap(tester, find.byKey(const Key('manual_save_button')));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('wide 1200x800 layout puts today and week side by side', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        store: richStore(),
        source: FakeSyncSource(),
        intake: richIntake,
        size: const Size(1200, 800),
      );
      expect(tester.takeException(), isNull);

      final todayRect = tester.getRect(find.byKey(const Key('today_panel')));
      final weekRect = tester.getRect(find.byKey(const Key('week_panel')));
      expect(weekRect.left, greaterThan(todayRect.right));
      expect(weekRect.right - todayRect.left, lessThanOrEqualTo(980));

      expect(_in('today_net', '−4,691 kcal'), findsOneWidget);
      expect(_in('today_panel', '123.46 km'), findsOneWidget);
      expect(
        _in('week_net', 'Partial: over 2 of 3 days with total expenditure'),
        findsOneWidget,
      );
    });
  });
}
