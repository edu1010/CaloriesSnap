import 'package:calorie_snap/models/daily_activity.dart';
import 'package:calorie_snap/services/activity/activity_csv_importer.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 3, 12, 10, 15);

ActivityCsvParseResult _parse(String content, {String? origin}) {
  return ActivityCsvImporter.parse(content, origin: origin, now: () => _now);
}

/// Parses a single data row under the full header and returns its error.
String? _rowError(String row, {String delimiter = ','}) {
  final header = ActivityCsvImporter.columns.join(delimiter);
  final result = _parse('$header\n$row\n');
  expect(result.headerValid, isTrue);
  if (result.errors.isEmpty) {
    expect(result.days, hasLength(1));
    return null;
  }
  expect(result.days, isEmpty);
  expect(result.errors.single.line, 2);
  return result.errors.single.reason;
}

void main() {
  test('documents its columns', () {
    expect(ActivityCsvImporter.requiredColumn, 'date');
    expect(ActivityCsvImporter.columns, <String>[
      'date',
      'active_kcal',
      'total_kcal',
      'steps',
      'distance_km',
      'active_minutes',
    ]);
  });

  group('happy path', () {
    test('imports every column', () {
      final result = _parse(
        'date,active_kcal,total_kcal,steps,distance_km,active_minutes\n'
        '2026-03-02,420.5,2310,8500,6.2,45\n'
        '2026-03-03,0,1900,0,0,0\n',
        origin: 'mi_fitness_march.csv',
      );

      expect(result.headerValid, isTrue);
      expect(result.errors, isEmpty);
      expect(result.ignoredColumns, isEmpty);
      expect(result.days, hasLength(2));

      final first = result.days.first;
      expect(first.date, DateTime(2026, 3, 2));
      expect(first.source, ActivitySource.csvImport);
      expect(first.origin, 'mi_fitness_march.csv');
      expect(first.updatedAt, _now);
      expect(first.activeKcal, 420.5);
      expect(first.totalKcal, 2310);
      expect(first.steps, 8500);
      expect(first.distanceMeters, closeTo(6200, 1e-6));
      expect(first.activeMinutes, 45);
      expect(first.invalidField, isNull);

      // Explicit zeros are values, not missing data.
      final second = result.days.last;
      expect(second.activeKcal, 0);
      expect(second.steps, 0);
      expect(second.distanceMeters, 0);
      expect(second.activeMinutes, 0);
    });

    test('empty cells stay null and are not reported', () {
      final result = _parse(
        'date,active_kcal,total_kcal,steps,distance_km,active_minutes\n'
        '2026-03-02,,,10250,,\n'
        '2026-03-03,300\n',
      );

      expect(result.errors, isEmpty);
      final steps = result.days[0];
      expect(steps.steps, 10250);
      expect(steps.activeKcal, isNull);
      expect(steps.totalKcal, isNull);
      expect(steps.distanceMeters, isNull);
      expect(steps.activeMinutes, isNull);

      // A short row reads as trailing empty cells.
      final short = result.days[1];
      expect(short.activeKcal, 300);
      expect(short.steps, isNull);
    });

    test('accepts any column order, case and a subset of metrics', () {
      final result = _parse(
        ' Steps , DATE ,Total_Kcal\n'
        '7000, 2026-03-02 , 2100.75\n',
      );

      expect(result.headerValid, isTrue);
      expect(result.errors, isEmpty);
      final day = result.days.single;
      expect(day.date, DateTime(2026, 3, 2));
      expect(day.steps, 7000);
      expect(day.totalKcal, 2100.75);
      expect(day.activeKcal, isNull);
    });

    test('handles BOM, CRLF, blank lines and quoted fields', () {
      final result = _parse(
        '﻿"date","steps","active_kcal"\r\n'
        '\r\n'
        '"2026-03-02","8500","420"\r\n'
        '   \r\n'
        ',,\r\n'
        '2026-03-03,"9100",\r\n'
        '\r\n',
      );

      expect(result.headerValid, isTrue);
      expect(result.errors, isEmpty);
      expect(result.days.map((d) => d.date), <DateTime>[
        DateTime(2026, 3, 2),
        DateTime(2026, 3, 3),
      ]);
      expect(result.days.first.steps, 8500);
      expect(result.days.first.activeKcal, 420);
      expect(result.days.last.steps, 9100);
    });

    test('accepts lone CR line endings and no trailing newline', () {
      final result = _parse('date,steps\r2026-03-02,10\r2026-03-03,20');
      expect(result.errors, isEmpty);
      expect(result.days.map((d) => d.steps), <int>[10, 20]);
    });

    test('semicolon files may use a decimal comma or point', () {
      final result = _parse(
        'date;active_kcal;distance_km;steps\n'
        '2026-03-02;420,5;6,25;8500\n'
        '2026-03-03;380.5;5.5;7000\n',
      );

      expect(result.headerValid, isTrue);
      expect(result.errors, isEmpty);
      expect(result.days[0].activeKcal, 420.5);
      expect(result.days[0].distanceMeters, closeTo(6250, 1e-6));
      expect(result.days[1].activeKcal, 380.5);
      expect(result.days[1].distanceMeters, closeTo(5500, 1e-6));
    });

    test('a quoted decimal comma is not a number in a comma file', () {
      final result = _parse('date,active_kcal\n2026-03-02,"420,5"\n');
      expect(result.days, isEmpty);
      expect(result.errors.single.reason, 'invalid active_kcal');
    });

    test('whole-number columns accept an integral decimal', () {
      final result = _parse(
        'date,steps,active_minutes\n2026-03-02,8500.0,30.\n',
      );
      expect(result.errors, isEmpty);
      expect(result.days.single.steps, 8500);
      expect(result.days.single.activeMinutes, 30);
    });

    test('unknown columns are ignored and listed', () {
      final result = _parse(
        'date,Heart Rate,steps,notes\n'
        '2026-03-02,61,8500,"long walk, sunny"\n',
      );

      expect(result.headerValid, isTrue);
      expect(result.errors, isEmpty);
      expect(result.ignoredColumns, <String>['Heart Rate', 'notes']);
      expect(result.days.single.steps, 8500);
    });

    test('blank origin becomes null, today is accepted', () {
      final result = _parse('date,steps\n2026-03-12,1\n', origin: '  ');
      expect(result.errors, isEmpty);
      expect(result.days.single.origin, isNull);
      expect(result.days.single.date, DateTime(2026, 3, 12));
    });
  });

  group('invalid header', () {
    void expectInvalid(String content, String reason, {int line = 1}) {
      final result = _parse(content);
      expect(result.headerValid, isFalse, reason: content);
      expect(result.days, isEmpty);
      expect(result.errors.single.reason, reason);
      expect(result.errors.single.line, line);
    }

    test('empty content', () {
      expectInvalid('', 'empty file');
      expectInvalid('﻿\r\n  \r\n', 'empty file');
    });

    test('missing date column', () {
      expectInvalid('day,steps\n2026-03-02,10\n', 'missing date column');
      // A file without header: its first row is taken as the header.
      expectInvalid('2026-03-02,10\n', 'missing date column');
    });

    test('no metric column', () {
      expectInvalid('date\n2026-03-02\n', 'no metric column');
      expectInvalid('date,heart_rate\n2026-03-02,60\n', 'no metric column');
    });

    test('duplicate schema column', () {
      expectInvalid(
        'date,steps,STEPS\n2026-03-02,10,20\n',
        'duplicate column steps',
      );
    });

    test('reports the real header line after leading blank lines', () {
      expectInvalid('\n\nfoo,bar\n1,2\n', 'missing date column', line: 3);
    });
  });

  group('row errors', () {
    test('invalid dates', () {
      for (final date in <String>[
        '',
        '2026-02-30',
        '2026-13-01',
        '2026-00-10',
        '2026-3-2',
        '02/03/2026',
        '20260302',
        '2026-03-02T10:00:00',
        'yesterday',
      ]) {
        expect(_rowError('$date,100,2000,1,1,1'), 'invalid date', reason: date);
      }
      expect(_rowError('2024-02-29,100,2000,1,1,1'), isNull);
    });

    test('future dates', () {
      expect(_rowError('2026-03-13,100,2000,1,1,1'), 'future date');
      expect(_rowError('2026-03-12,100,2000,1,1,1'), isNull);
    });

    test('rows without any metric', () {
      expect(_rowError('2026-03-02,,,,,'), 'no metrics');
      expect(_rowError('2026-03-02'), 'no metrics');
    });

    test('malformed numbers', () {
      expect(_rowError('2026-03-02,abc,,,,'), 'invalid active_kcal');
      expect(_rowError('2026-03-02,,2000 kcal,,,'), 'invalid total_kcal');
      expect(_rowError('2026-03-02,,1e3,,,'), 'invalid total_kcal');
      expect(_rowError('2026-03-02,,NaN,,,'), 'invalid total_kcal');
      expect(_rowError('2026-03-02,,Infinity,,,'), 'invalid total_kcal');
      expect(_rowError('2026-03-02,,+2000,,,'), 'invalid total_kcal');
      expect(_rowError('2026-03-02,,"2,000",,,'), 'invalid total_kcal');
      expect(_rowError('2026-03-02,,,8 500,,'), 'invalid steps');
      expect(_rowError('2026-03-02,,,8500.5,,'), 'invalid steps');
      expect(_rowError('2026-03-02,,,,,12.5'), 'invalid active_minutes');
      expect(_rowError('2026-03-02,,,,1.2.3,'), 'invalid distance_km');
      // Mixed separators are ambiguous even in a semicolon file.
      expect(
        _rowError('2026-03-02;;1.234,5;;;', delimiter: ';'),
        'invalid total_kcal',
      );
      expect(
        _rowError('2026-03-02;;1,234,5;;;', delimiter: ';'),
        'invalid total_kcal',
      );
    });

    test('negative values', () {
      expect(_rowError('2026-03-02,-1,,,,'), 'negative active_kcal');
      expect(_rowError('2026-03-02,,-0.5,,,'), 'negative total_kcal');
      expect(_rowError('2026-03-02,,,-10,,'), 'negative steps');
      expect(_rowError('2026-03-02,,,,-3.5,'), 'negative distance_km');
      expect(_rowError('2026-03-02,,,,,-1'), 'negative active_minutes');
    });

    test('out-of-range values', () {
      expect(_rowError('2026-03-02,30001,,,,'), 'out of range active_kcal');
      expect(_rowError('2026-03-02,,30001,,,'), 'out of range total_kcal');
      expect(_rowError('2026-03-02,,,300001,,'), 'out of range steps');
      expect(_rowError('2026-03-02,,,,1000.5,'), 'out of range distance_km');
      expect(_rowError('2026-03-02,,,,,1441'), 'out of range active_minutes');
      // Limits themselves are fine.
      expect(_rowError('2026-03-02,30000,30000,300000,1000,1440'), isNull);
    });

    test('active above total', () {
      expect(
        _rowError('2026-03-02,900,800,,,'),
        'active_kcal greater than total_kcal',
      );
      expect(_rowError('2026-03-02,800,800,,,'), isNull);
    });

    test('too many cells', () {
      expect(_rowError('2026-03-02,1,2,3,4,5,6'), 'too many columns');
    });

    test('duplicate dates keep the first valid row', () {
      final result = _parse(
        'date,steps\n'
        '2026-03-02,100\n'
        '2026-03-03,200\n'
        '2026-03-02,999\n',
      );

      expect(result.days.map((d) => d.steps), <int>[100, 200]);
      expect(result.errors.single.line, 4);
      expect(result.errors.single.reason, 'duplicate date');
    });

    test('a rejected row does not reserve its date', () {
      final result = _parse(
        'date,steps\n'
        '2026-03-02,-5\n'
        '2026-03-02,100\n',
      );

      expect(result.days.single.steps, 100);
      expect(result.errors.single.line, 2);
      expect(result.errors.single.reason, 'negative steps');
    });

    test('valid rows still import and line numbers match the file', () {
      final result = _parse(
        'date,active_kcal,steps\r\n' // 1
        '2026-03-01,300,7000\r\n' // 2
        '\r\n' // 3
        '2026-02-30,300,7000\r\n' // 4
        '2026-03-03,-1,7000\r\n' // 5
        '2026-03-04,,\r\n' // 6
        '2026-03-05,250,\r\n' // 7
        '2026-03-01,1,1\r\n' // 8
        '2026-03-06,x,1\r\n', // 9
      );

      expect(result.headerValid, isTrue);
      expect(result.days.map((d) => d.date), <DateTime>[
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 5),
      ]);
      expect(result.errors.map((e) => '${e.line}:${e.reason}'), <String>[
        '4:invalid date',
        '5:negative active_kcal',
        '6:no metrics',
        '8:duplicate date',
        '9:invalid active_kcal',
      ]);
      expect(result.errors.first.toString(), 'line 4: invalid date');
    });

    test('a quoted line break keeps later line numbers right', () {
      final result = _parse(
        'date,steps,notes\n'
        '2026-03-01,100,"two\nlines"\n'
        '2026-03-02,-1,\n',
      );

      expect(result.days.single.steps, 100);
      expect(result.errors.single.line, 4);
    });
  });
}
