import 'package:calorie_snap/models/daily_activity.dart';
import 'package:calorie_snap/services/activity/activity_sync_source.dart';
import 'package:calorie_snap/services/activity/health_connect_activity_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(HealthConnectActivitySource.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final syncedAt = DateTime(2026, 10, 11, 9, 30);

  void respond(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  HealthConnectActivitySource androidSource() =>
      HealthConnectActivitySource(isAndroid: true, clock: () => syncedAt);

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('reports the Health Connect source', () {
    expect(androidSource().source, ActivitySource.healthConnect);
  });

  group('outside Android', () {
    for (final source
        in <String, HealthConnectActivitySource>{
          'explicit flag': HealthConnectActivitySource(isAndroid: false),
          // The test host is never Android, so the default must stay off too.
          'default constructor': HealthConnectActivitySource(),
        }.entries) {
      test('${source.key} never calls the channel', () async {
        respond((call) async => fail('channel called: ${call.method}'));
        final sut = source.value;

        expect(
          await sut.checkAvailability(),
          ActivitySyncAvailability.unsupportedPlatform,
        );
        expect(await sut.hasPermissions(), isFalse);
        expect(await sut.requestPermissions(), isFalse);
        expect(await sut.openProviderSetup(), isFalse);
        await expectLater(
          sut.fetchDays(DateTime(2026, 10, 1), DateTime(2026, 10, 15)),
          throwsA(isA<ActivitySyncException>()),
        );
        expect(calls, isEmpty);
      });
    }
  });

  group('availability', () {
    const expected = <String?, ActivitySyncAvailability>{
      'available': ActivitySyncAvailability.available,
      'notInstalled': ActivitySyncAvailability.providerNotInstalled,
      'updateRequired': ActivitySyncAvailability.providerUpdateRequired,
      'unsupported': ActivitySyncAvailability.unsupportedPlatform,
      'somethingNew': ActivitySyncAvailability.unsupportedPlatform,
      null: ActivitySyncAvailability.unsupportedPlatform,
    };
    for (final entry in expected.entries) {
      test('maps ${entry.key} to ${entry.value.name}', () async {
        respond((_) async => entry.key);
        expect(await androidSource().checkAvailability(), entry.value);
        expect(calls.single.method, 'getSdkStatus');
      });
    }

    test('a failing or missing native side is unsupported', () async {
      respond((_) async => throw PlatformException(code: 'unknown'));
      expect(
        await androidSource().checkAvailability(),
        ActivitySyncAvailability.unsupportedPlatform,
      );

      messenger.setMockMethodCallHandler(channel, null);
      expect(
        await androidSource().checkAvailability(),
        ActivitySyncAvailability.unsupportedPlatform,
      );
    });
  });

  group('permissions', () {
    test(
      'hasPermissions accepts energy access without optional metrics',
      () async {
        respond((_) async => HealthConnectReply.allMetrics);
        expect(await androidSource().hasPermissions(), isTrue);
        expect(calls.single.method, 'getGrantedPermissions');

        respond(
          (_) async => <String>['activeKcal', 'totalKcal', 'steps', 'distance'],
        );
        expect(await androidSource().hasPermissions(), isTrue);

        respond((_) async => <String>['totalKcal']);
        expect(await androidSource().hasPermissions(), isTrue);

        respond((_) async => <String>['activeKcal']);
        expect(await androidSource().hasPermissions(), isTrue);

        respond((_) async => <String>['steps']);
        expect(await androidSource().hasPermissions(), isFalse);

        respond((_) async => <String>[]);
        expect(await androidSource().hasPermissions(), isFalse);

        respond((_) async => null);
        expect(await androidSource().hasPermissions(), isFalse);
      },
    );

    test('requestPermissions needs at least one energy metric', () async {
      respond((_) async => <String>['totalKcal']);
      expect(await androidSource().requestPermissions(), isTrue);
      expect(calls.single.method, 'requestPermissions');

      respond((_) async => <String>['activeKcal', 'steps']);
      expect(await androidSource().requestPermissions(), isTrue);

      respond((_) async => <String>['steps', 'distanceMeters']);
      expect(await androidSource().requestPermissions(), isFalse);

      respond((_) async => <String>[]);
      expect(await androidSource().requestPermissions(), isFalse);
    });

    test('native errors count as not granted', () async {
      respond((_) async => throw PlatformException(code: 'requestInProgress'));
      expect(await androidSource().requestPermissions(), isFalse);
      expect(await androidSource().hasPermissions(), isFalse);
    });
  });

  group('openProviderSetup', () {
    test('returns what the native side opened', () async {
      respond((_) async => true);
      expect(await androidSource().openProviderSetup(), isTrue);
      expect(calls.single.method, 'openSetup');

      respond((_) async => false);
      expect(await androidSource().openProviderSetup(), isFalse);

      respond((_) async => throw PlatformException(code: 'unknown'));
      expect(await androidSource().openProviderSetup(), isFalse);
    });
  });

  group('fetchDays', () {
    final start = DateTime(2026, 10, 1);
    final end = DateTime(2026, 10, 15);

    test('sends local day keys and parses the reply', () async {
      respond(
        (_) async => <Object?>[
          <String, Object?>{
            'date': '2026-10-03',
            'steps': 0,
            'origins': <String>[],
          },
          <String, Object?>{
            'date': '2026-10-02',
            'activeKcal': 412.5,
            'totalKcal': 2210,
            'steps': 9034,
            'distanceMeters': 6540.25,
            'activeMinutes': 47,
            'origins': <String>['com.xiaomi.wearable', 'com.huawei.health'],
          },
        ],
      );

      final days = await androidSource().fetchDays(
        // Time of day is ignored: the range is whole local days.
        DateTime(2026, 10, 1, 18, 45),
        end,
      );

      expect(calls.single.method, 'aggregateDays');
      expect(calls.single.arguments, <String, Object?>{
        'start': '2026-10-01',
        'end': '2026-10-15',
      });
      expect(days, hasLength(2));

      final full = days.first;
      expect(full.date, DateTime(2026, 10, 2));
      expect(full.date.isUtc, isFalse);
      expect(full.source, ActivitySource.healthConnect);
      expect(full.updatedAt, syncedAt);
      expect(full.activeKcal, 412.5);
      expect(full.totalKcal, 2210.0);
      expect(full.steps, 9034);
      expect(full.distanceMeters, 6540.25);
      expect(full.activeMinutes, 47);
      expect(full.origin, 'com.huawei.health,com.xiaomi.wearable');
      expect(full.invalidField, isNull);

      // A reported zero is data; everything not reported stays null.
      final sparse = days.last;
      expect(sparse.date, DateTime(2026, 10, 3));
      expect(sparse.steps, 0);
      expect(sparse.activeKcal, isNull);
      expect(sparse.totalKcal, isNull);
      expect(sparse.distanceMeters, isNull);
      expect(sparse.activeMinutes, isNull);
      expect(sparse.origin, isNull);
    });

    test('drops days without metrics or outside the range', () async {
      respond(
        (_) async => <Object?>[
          <String, Object?>{
            'date': '2026-10-04',
            'origins': <String>['com.strava'],
          },
          <String, Object?>{'date': '2026-09-30', 'steps': 10},
          <String, Object?>{'date': '2026-10-15', 'steps': 10},
          <String, Object?>{'date': '2026-10-14', 'steps': 10},
        ],
      );

      final days = await androidSource().fetchDays(start, end);

      expect(days.map((d) => d.date), <DateTime>[DateTime(2026, 10, 14)]);
    });

    test('an empty or null reply means no data', () async {
      respond((_) async => <Object?>[]);
      expect(await androidSource().fetchDays(start, end), isEmpty);

      respond((_) async => null);
      expect(await androidSource().fetchDays(start, end), isEmpty);
    });

    test('an empty range does not call the channel', () async {
      respond((call) async => fail('channel called: ${call.method}'));
      expect(await androidSource().fetchDays(end, start), isEmpty);
      expect(await androidSource().fetchDays(start, start), isEmpty);
      expect(calls, isEmpty);
    });

    test('rejects invalid values', () async {
      final invalidEntries = <Object?>[
        <String, Object?>{'date': '2026-10-02', 'activeKcal': -1.0},
        <String, Object?>{'date': '2026-10-02', 'totalKcal': double.nan},
        <String, Object?>{
          'date': '2026-10-02',
          'distanceMeters': double.infinity,
        },
        <String, Object?>{'date': '2026-10-02', 'steps': 12.5},
        <String, Object?>{'date': '2026-10-02', 'steps': -3},
        <String, Object?>{'date': '2026-10-02', 'activeMinutes': '47'},
        <String, Object?>{'date': '02/10/2026', 'steps': 10},
        <String, Object?>{'date': '2026-02-31', 'steps': 10},
        <String, Object?>{'date': '2026-10-02T00:00:00', 'steps': 10},
        <String, Object?>{'steps': 10},
        'not a map',
      ];
      for (final entry in invalidEntries) {
        respond((_) async => <Object?>[entry]);
        await expectLater(
          androidSource().fetchDays(start, end),
          throwsA(isA<ActivitySyncException>()),
          reason: '$entry',
        );
      }

      respond((_) async => 'not a list');
      await expectLater(
        androidSource().fetchDays(start, end),
        throwsA(isA<ActivitySyncException>()),
      );
    });

    test('turns native errors into ActivitySyncException', () async {
      const expected = <String, String>{
        'permissionDenied': 'denied access',
        'unavailable': 'not available',
        'io': 'could not read',
        'remote': 'did not respond',
        'illegalState': 'could not complete',
        'somethingElse': 'somethingElse',
      };
      for (final entry in expected.entries) {
        respond(
          (_) async =>
              throw PlatformException(code: entry.key, message: 'boom'),
        );
        await expectLater(
          androidSource().fetchDays(start, end),
          throwsA(
            isA<ActivitySyncException>().having(
              (e) => e.message,
              'message',
              allOf(contains(entry.value), contains('boom')),
            ),
          ),
        );
      }
    });

    test('a missing native side is an ActivitySyncException', () async {
      messenger.setMockMethodCallHandler(channel, null);
      await expectLater(
        androidSource().fetchDays(start, end),
        throwsA(isA<ActivitySyncException>()),
      );
    });
  });

  group('HealthConnectReply', () {
    test('formats and parses day keys as local midnights', () {
      expect(HealthConnectReply.formatDay(DateTime(2026, 3, 7)), '2026-03-07');
      expect(HealthConnectReply.parseDay('2026-03-07'), DateTime(2026, 3, 7));
      expect(HealthConnectReply.parseDay('2026-3-7'), isNull);
      expect(HealthConnectReply.parseDay('2026-13-01'), isNull);
      expect(HealthConnectReply.parseDay(20260307), isNull);
      expect(HealthConnectReply.parseDay(null), isNull);
    });

    test('de-duplicates and sorts origins', () {
      final days = HealthConnectReply.parseDays(
        <Object?>[
          <String, Object?>{
            'date': '2026-10-02',
            'steps': 5,
            'origins': <Object?>['b.app', ' a.app ', 'b.app', '', 7],
          },
        ],
        startInclusive: DateTime(2026, 10, 1),
        endExclusive: DateTime(2026, 10, 15),
        updatedAt: syncedAt,
      );
      expect(days.single.origin, 'a.app,b.app');
    });

    test('a total below the active part is treated as unknown', () {
      final days = HealthConnectReply.parseDays(
        <Object?>[
          <String, Object?>{
            'date': '2026-10-02',
            'activeKcal': 420.0,
            'totalKcal': 300.0,
          },
          <String, Object?>{
            'date': '2026-10-03',
            'activeKcal': 420.0,
            'totalKcal': 2300.0,
          },
        ],
        startInclusive: DateTime(2026, 10, 1),
        endExclusive: DateTime(2026, 10, 15),
        updatedAt: syncedAt,
      );
      expect(days[0].activeKcal, 420);
      expect(days[0].totalKcal, isNull);
      expect(days[0].invalidField, isNull);
      expect(days[1].totalKcal, 2300);
    });
  });
}
