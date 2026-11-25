import 'package:calorie_snap/models/daily_activity.dart';
import 'package:calorie_snap/services/activity/activity_sync_coordinator.dart';
import 'package:calorie_snap/services/activity/activity_sync_source.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_activity_store.dart';

class _FakeSource implements ActivitySyncSource {
  ActivitySyncAvailability availability = ActivitySyncAvailability.available;
  bool granted = true;
  bool grantOnRequest = true;
  Object? availabilityError;
  Object? fetchError;
  List<DailyActivity> days = <DailyActivity>[];

  final List<String> calls = <String>[];
  DateTime? fetchStart;
  DateTime? fetchEnd;

  @override
  ActivitySource get source => ActivitySource.healthConnect;

  @override
  Future<ActivitySyncAvailability> checkAvailability() async {
    calls.add('checkAvailability');
    if (availabilityError != null) {
      throw availabilityError!;
    }
    return availability;
  }

  @override
  Future<bool> hasPermissions() async {
    calls.add('hasPermissions');
    return granted;
  }

  @override
  Future<bool> requestPermissions() async {
    calls.add('requestPermissions');
    granted = grantOnRequest;
    return grantOnRequest;
  }

  @override
  Future<List<DailyActivity>> fetchDays(
    DateTime startInclusive,
    DateTime endExclusive,
  ) async {
    calls.add('fetchDays');
    fetchStart = startInclusive;
    fetchEnd = endExclusive;
    if (fetchError != null) {
      throw fetchError!;
    }
    return days;
  }

  @override
  Future<bool> openProviderSetup() async => false;
}

DailyActivity _hc(
  DateTime date, {
  double? activeKcal,
  double? totalKcal,
  int? steps,
  ActivitySource source = ActivitySource.healthConnect,
}) {
  return DailyActivity(
    date: date,
    source: source,
    updatedAt: DateTime(2026, 3, 12, 8),
    activeKcal: activeKcal,
    totalKcal: totalKcal,
    steps: steps,
    origin: 'com.example.watch',
  );
}

void main() {
  late FakeActivityStore store;
  late _FakeSource source;
  late DateTime now;
  late ActivitySyncCoordinator coordinator;

  setUp(() {
    store = FakeActivityStore();
    source = _FakeSource();
    now = DateTime(2026, 3, 12, 18, 40);
    coordinator = ActivitySyncCoordinator(
      store: store,
      source: source,
      now: () => now,
    );
  });

  Future<ActivitySyncState?> state() {
    return store.loadSyncState(ActivitySource.healthConnect);
  }

  test('exposes its source, availability and last state', () async {
    expect(coordinator.source, same(source));
    expect(ActivitySyncCoordinator.defaultDays, 14);

    source.availability = ActivitySyncAvailability.providerUpdateRequired;
    expect(
      await coordinator.checkAvailability(),
      ActivitySyncAvailability.providerUpdateRequired,
    );

    expect(await coordinator.lastState(), isNull);
    await store.saveSyncState(
      const ActivitySyncState(
        source: ActivitySource.healthConnect,
        lastImportedDays: 3,
      ),
    );
    expect((await coordinator.lastState())!.lastImportedDays, 3);
  });

  group('successful sync', () {
    test('fetches the last 14 local days including today', () async {
      source.days = <DailyActivity>[
        _hc(DateTime(2026, 3, 11), activeKcal: 350, totalKcal: 2250),
        _hc(DateTime(2026, 3, 12), steps: 4200),
      ];

      final outcome = await coordinator.sync();

      expect(outcome.status, ActivitySyncStatus.success);
      expect(outcome.isSuccess, isTrue);
      expect(outcome.importedDays, 2);
      expect(outcome.syncedAt, now);
      expect(outcome.message, isNull);

      expect(source.fetchStart, DateTime(2026, 2, 27));
      expect(source.fetchEnd, DateTime(2026, 3, 13));
      expect(source.calls, <String>[
        'checkAvailability',
        'hasPermissions',
        'fetchDays',
      ]);

      final stored = await store.effectiveForRange(
        DateTime(2026, 2, 27),
        DateTime(2026, 3, 13),
      );
      expect(stored.keys.toSet(), <DateTime>{
        DateTime(2026, 3, 11),
        DateTime(2026, 3, 12),
      });
      expect(stored[DateTime(2026, 3, 11)]!.totalKcal, 2250);
      expect(stored[DateTime(2026, 3, 12)]!.steps, 4200);
      expect(stored[DateTime(2026, 3, 12)]!.activeKcal, isNull);
      expect(stored[DateTime(2026, 3, 12)]!.origin, 'com.example.watch');

      final saved = (await state())!;
      expect(saved.lastAttemptAt, now);
      expect(saved.lastSuccessAt, now);
      expect(saved.lastImportedDays, 2);
      expect(saved.lastError, isNull);
    });

    test('honours a custom day count and month boundaries', () async {
      now = DateTime(2026, 3, 2, 0, 5);
      await coordinator.sync(days: 3);
      expect(source.fetchStart, DateTime(2026, 2, 28));
      expect(source.fetchEnd, DateTime(2026, 3, 3));

      await coordinator.sync(days: 1);
      expect(source.fetchStart, DateTime(2026, 3, 2));
      expect(source.fetchEnd, DateTime(2026, 3, 3));

      // Nonsense counts fall back to "today only".
      await coordinator.sync(days: 0);
      expect(source.fetchStart, DateTime(2026, 3, 2));
    });

    test('requests permissions when they are missing', () async {
      source.granted = false;
      source.grantOnRequest = true;
      source.days = <DailyActivity>[_hc(DateTime(2026, 3, 12), steps: 1)];

      final outcome = await coordinator.sync();

      expect(outcome.status, ActivitySyncStatus.success);
      expect(source.calls, <String>[
        'checkAvailability',
        'hasPermissions',
        'requestPermissions',
        'fetchDays',
      ]);
    });

    test(
      'replaces stale days of the range, keeps older and other data',
      () async {
        // Stale Health Connect day inside the window, one before it, and a
        // manual record that must survive.
        await store.upsert(_hc(DateTime(2026, 3, 5), steps: 555));
        await store.upsert(_hc(DateTime(2026, 2, 20), steps: 222));
        await store.upsert(
          _hc(DateTime(2026, 3, 5), steps: 1, source: ActivitySource.manual),
        );
        source.days = <DailyActivity>[_hc(DateTime(2026, 3, 12), steps: 4200)];

        await coordinator.sync();

        final march5 = await store.recordsForDay(DateTime(2026, 3, 5));
        expect(march5.single.source, ActivitySource.manual);
        expect(
          (await store.recordsForDay(DateTime(2026, 2, 20))).single.steps,
          222,
        );
        expect(
          (await store.recordsForDay(DateTime(2026, 3, 12))).single.steps,
          4200,
        );
      },
    );

    test('an empty answer is a success with zero days', () async {
      await store.upsert(_hc(DateTime(2026, 3, 10), steps: 10));

      final outcome = await coordinator.sync();

      expect(outcome.status, ActivitySyncStatus.success);
      expect(outcome.importedDays, 0);
      expect(await store.recordsForDay(DateTime(2026, 3, 10)), isEmpty);
      expect((await state())!.lastImportedDays, 0);
    });

    test('drops unusable records instead of failing', () async {
      source.days = <DailyActivity>[
        _hc(DateTime(2026, 3, 12, 15, 30), steps: 4200),
        // Negative metric.
        _hc(DateTime(2026, 3, 11), activeKcal: -5),
        // Active above total.
        _hc(DateTime(2026, 3, 10), activeKcal: 900, totalKcal: 800),
        // No metric at all.
        _hc(DateTime(2026, 3, 9)),
        // Wrong source.
        _hc(DateTime(2026, 3, 8), steps: 10, source: ActivitySource.manual),
        // Outside of the requested range.
        _hc(DateTime(2026, 1, 1), steps: 10),
        _hc(DateTime(2026, 3, 13), steps: 10),
        // Second record for an already accepted day.
        _hc(DateTime(2026, 3, 12), steps: 9999),
      ];

      final outcome = await coordinator.sync();

      expect(outcome.status, ActivitySyncStatus.success);
      expect(outcome.importedDays, 1);
      expect(store.records, hasLength(1));
      final record = store.records.values.single;
      expect(record.date, DateTime(2026, 3, 12));
      expect(record.source, ActivitySource.healthConnect);
      expect(record.steps, 4200);
    });
  });

  group('status mapping', () {
    test('unsupported platform: no fetch, nothing persisted', () async {
      source.availability = ActivitySyncAvailability.unsupportedPlatform;

      final outcome = await coordinator.sync();

      expect(outcome.status, ActivitySyncStatus.unsupportedPlatform);
      expect(outcome.importedDays, 0);
      expect(outcome.syncedAt, isNull);
      expect(source.calls, <String>['checkAvailability']);
      expect(store.savedSyncStates, 0);
      expect(await state(), isNull);
    });

    test('provider missing or outdated', () async {
      final expected = <ActivitySyncAvailability, ActivitySyncStatus>{
        ActivitySyncAvailability.providerNotInstalled:
            ActivitySyncStatus.providerNotInstalled,
        ActivitySyncAvailability.providerUpdateRequired:
            ActivitySyncStatus.providerUpdateRequired,
      };
      for (final entry in expected.entries) {
        source.calls.clear();
        source.availability = entry.key;

        final outcome = await coordinator.sync();

        expect(outcome.status, entry.value);
        expect(outcome.isSuccess, isFalse);
        expect(source.calls, <String>['checkAvailability']);
        final saved = (await state())!;
        expect(saved.lastError, entry.value.name);
        expect(saved.lastAttemptAt, now);
        expect(saved.lastSuccessAt, isNull);
      }
    });

    test('permission refusal', () async {
      source.granted = false;
      source.grantOnRequest = false;
      await store.upsert(_hc(DateTime(2026, 3, 10), steps: 10));

      final outcome = await coordinator.sync();

      expect(outcome.status, ActivitySyncStatus.permissionDenied);
      expect(source.calls, <String>[
        'checkAvailability',
        'hasPermissions',
        'requestPermissions',
      ]);
      // Existing data is left as it was.
      expect(
        (await store.recordsForDay(DateTime(2026, 3, 10))).single.steps,
        10,
      );
      expect((await state())!.lastError, 'permissionDenied');
    });

    test('provider failure keeps its message and the stored data', () async {
      source.fetchError = const ActivitySyncException('remote exception');
      await store.upsert(_hc(DateTime(2026, 3, 10), steps: 10));

      final outcome = await coordinator.sync();

      expect(outcome.status, ActivitySyncStatus.failed);
      expect(outcome.message, 'remote exception');
      expect(outcome.importedDays, 0);
      expect(
        (await store.recordsForDay(DateTime(2026, 3, 10))).single.steps,
        10,
      );
      expect((await state())!.lastError, 'failed');
    });

    test('any other error is a failure too, never an exception', () async {
      source.fetchError = StateError('boom');
      var outcome = await coordinator.sync();
      expect(outcome.status, ActivitySyncStatus.failed);
      expect(outcome.message, contains('boom'));

      source.fetchError = null;
      source.availabilityError = Exception('channel missing');
      outcome = await coordinator.sync();
      expect(outcome.status, ActivitySyncStatus.failed);
      expect(outcome.message, contains('channel missing'));

      source.availabilityError = null;
      store.failReplaceRange = true;
      outcome = await coordinator.sync();
      expect(outcome.status, ActivitySyncStatus.failed);
      expect(outcome.message, contains('disk full'));
      expect((await state())!.lastError, 'failed');
    });

    test('a state that cannot be saved does not break the sync', () async {
      store.failSaveSyncState = true;
      source.days = <DailyActivity>[_hc(DateTime(2026, 3, 12), steps: 4200)];

      final outcome = await coordinator.sync();

      expect(outcome.status, ActivitySyncStatus.success);
      expect(outcome.importedDays, 1);
    });
  });

  group('sync state history', () {
    test(
      'a failure keeps the previous success and updates the attempt',
      () async {
        source.days = <DailyActivity>[
          _hc(DateTime(2026, 3, 11), steps: 100),
          _hc(DateTime(2026, 3, 12), steps: 200),
        ];
        final firstAttempt = now;
        await coordinator.sync();

        now = DateTime(2026, 3, 13, 7);
        source.fetchError = const ActivitySyncException('timeout');
        await coordinator.sync();

        var saved = (await state())!;
        expect(saved.lastAttemptAt, DateTime(2026, 3, 13, 7));
        expect(saved.lastSuccessAt, firstAttempt);
        expect(saved.lastImportedDays, 2);
        expect(saved.lastError, 'failed');

        now = DateTime(2026, 3, 13, 9);
        source.fetchError = null;
        source.days = <DailyActivity>[_hc(DateTime(2026, 3, 13), steps: 300)];
        await coordinator.sync();

        saved = (await state())!;
        expect(saved.lastAttemptAt, DateTime(2026, 3, 13, 9));
        expect(saved.lastSuccessAt, DateTime(2026, 3, 13, 9));
        expect(saved.lastImportedDays, 1);
        expect(saved.lastError, isNull);
      },
    );

    test(
      'an unsupported attempt leaves the previous state untouched',
      () async {
        await coordinator.sync();
        final before = (await state())!;

        now = DateTime(2026, 3, 14);
        source.availability = ActivitySyncAvailability.unsupportedPlatform;
        await coordinator.sync();

        final after = (await state())!;
        expect(after.lastAttemptAt, before.lastAttemptAt);
        expect(after.lastError, isNull);
      },
    );
  });
}
