import '../../core/utils/app_date_utils.dart';
import '../../models/daily_activity.dart';

/// A row (or the header) of an imported CSV that could not be used.
class ActivityCsvRowError {
  const ActivityCsvRowError({required this.line, required this.reason});

  /// 1-based line number in the file.
  final int line;

  /// Short English reason, e.g. `invalid date` or `negative steps`.
  final String reason;

  @override
  String toString() => 'line $line: $reason';
}

class ActivityCsvParseResult {
  const ActivityCsvParseResult({
    required this.days,
    required this.errors,
    required this.headerValid,
    this.ignoredColumns = const <String>[],
  });

  /// Valid rows, one per date, in file order.
  final List<DailyActivity> days;
  final List<ActivityCsvRowError> errors;

  /// False when the header cannot be used; [days] is then empty and [errors]
  /// holds a single entry explaining why.
  final bool headerValid;

  /// Header names that are not part of the schema and were skipped.
  final List<String> ignoredColumns;
}

/// Parses the CalorieSnap daily activity CSV.
///
/// This is one documented, app-neutral schema. Proprietary exports (Mi
/// Fitness, Huawei Health, Strava, ...) are not parsed directly: they have to
/// be converted to this layout first, one row per day.
///
/// ```
/// date,active_kcal,total_kcal,steps,distance_km,active_minutes
/// 2026-03-02,420,2310,8500,6.2,45
/// 2026-03-03,,,10250,,
/// ```
///
/// File:
/// - UTF-8 text, with or without BOM. Line endings LF, CRLF or CR.
/// - The first non-blank line is the header. Blank lines (including lines
///   holding only delimiters) are skipped everywhere.
/// - The delimiter is `,` or `;`, detected from the header (whichever occurs
///   more often outside quotes; `,` on a tie).
/// - Fields may be wrapped in double quotes; a quote inside a quoted field is
///   written twice (`""`). Surrounding whitespace is trimmed.
///
/// Header:
/// - Column names are case-insensitive and may come in any order.
/// - `date` is mandatory, and at least one metric column must be present.
/// - Unknown columns are ignored (reported in
///   [ActivityCsvParseResult.ignoredColumns]) so files carrying extra data
///   still import.
/// - A schema column listed twice, a missing `date` column or no metric
///   column at all makes the header invalid: nothing is imported.
///
/// Columns:
/// - `date`: local calendar day as ISO `yyyy-MM-dd` (zero padded). It must be
///   a real date and not later than today.
/// - `active_kcal`: kilocalories burned through activity, excluding resting
///   metabolism. Decimal, 0 to 30000.
/// - `total_kcal`: total kilocalories burned that day (active + resting).
///   Decimal, 0 to 30000, and not lower than `active_kcal`.
/// - `steps`: whole number, 0 to 300000.
/// - `distance_km`: kilometres, decimal, 0 to 1000.
/// - `active_minutes`: whole number of exercise minutes, 0 to 1440.
///
/// Values:
/// - An empty cell means "not recorded" and is different from `0`. A short
///   row is read as if the missing trailing cells were empty.
/// - Numbers are plain digits with an optional decimal point (`1234.5`). No
///   thousands separators, units, signs or exponents. A decimal comma
///   (`1234,5`) is accepted only when the delimiter is `;`.
/// - Whole-number columns accept `8500` and `8500.0` but not `8500.5`.
///
/// Rows:
/// - Each row is validated on its own: a bad row is reported with its line
///   number and skipped, the other rows still import.
/// - A row is rejected when the date is invalid or in the future, a number is
///   malformed, negative or out of range, `active_kcal` exceeds `total_kcal`,
///   it has more cells than the header, or every metric cell is empty.
/// - When a date appears on several valid rows the first one is kept and the
///   later ones are reported as `duplicate date`.
///
/// Importing replaces nothing by itself: the caller decides how to store
/// [ActivityCsvParseResult.days], which all carry [ActivitySource.csvImport].
class ActivityCsvImporter {
  const ActivityCsvImporter._();

  static const requiredColumn = 'date';
  static const columns = <String>[
    'date',
    'active_kcal',
    'total_kcal',
    'steps',
    'distance_km',
    'active_minutes',
  ];

  static final RegExp _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static final RegExp _numberPattern = RegExp(r'^-?(\d+\.?\d*|\.\d+)$');

  /// [origin] is stored as the provenance of every record (usually the file
  /// name). [now] is only used to stamp records and to reject future dates.
  static ActivityCsvParseResult parse(
    String content, {
    String? origin,
    DateTime Function()? now,
  }) {
    final importedAt = (now ?? DateTime.now)();
    final today = AppDateUtils.startOfDay(importedAt);
    final trimmedOrigin = origin?.trim();
    final recordOrigin =
        trimmedOrigin == null || trimmedOrigin.isEmpty ? null : trimmedOrigin;

    var text = content;
    if (text.startsWith('﻿')) {
      text = text.substring(1);
    }

    final delimiter = _detectDelimiter(text);
    final records = _split(text, delimiter);
    if (records.isEmpty) {
      return _invalidHeader(1, 'empty file');
    }

    final header = records.first;
    final columnIndex = <String, int>{};
    final ignored = <String>[];
    for (var i = 0; i < header.fields.length; i++) {
      final raw = header.fields[i].trim();
      final name = raw.toLowerCase();
      if (!columns.contains(name)) {
        if (raw.isNotEmpty) {
          ignored.add(raw);
        }
        continue;
      }
      if (columnIndex.containsKey(name)) {
        return _invalidHeader(header.line, 'duplicate column $name');
      }
      columnIndex[name] = i;
    }
    if (!columnIndex.containsKey(requiredColumn)) {
      return _invalidHeader(header.line, 'missing date column');
    }
    if (columnIndex.length < 2) {
      return _invalidHeader(header.line, 'no metric column');
    }

    final days = <DailyActivity>[];
    final errors = <ActivityCsvRowError>[];
    final seenDates = <String>{};

    for (final record in records.skip(1)) {
      void reject(String reason) {
        errors.add(ActivityCsvRowError(line: record.line, reason: reason));
      }

      if (record.fields.length > header.fields.length) {
        reject('too many columns');
        continue;
      }

      String cell(String column) {
        final index = columnIndex[column];
        if (index == null || index >= record.fields.length) {
          return '';
        }
        return record.fields[index].trim();
      }

      final date = _parseDate(cell(requiredColumn));
      if (date == null) {
        reject('invalid date');
        continue;
      }
      if (date.isAfter(today)) {
        reject('future date');
        continue;
      }

      final values = <String, double?>{};
      String? problem;
      for (final column in columns.skip(1)) {
        final raw = cell(column);
        if (raw.isEmpty) {
          values[column] = null;
          continue;
        }
        final value = _parseNumber(raw, decimalComma: delimiter == ';');
        final wholeOnly = column == 'steps' || column == 'active_minutes';
        if (value == null || (wholeOnly && value != value.roundToDouble())) {
          problem = 'invalid $column';
          break;
        }
        if (value.isNegative) {
          problem = 'negative $column';
          break;
        }
        values[column] = value;
      }
      if (problem != null) {
        reject(problem);
        continue;
      }

      final distanceKm = values['distance_km'];
      final activity = DailyActivity(
        date: date,
        source: ActivitySource.csvImport,
        updatedAt: importedAt,
        activeKcal: values['active_kcal'],
        totalKcal: values['total_kcal'],
        steps: values['steps']?.round(),
        distanceMeters: distanceKm == null ? null : distanceKm * 1000,
        activeMinutes: values['active_minutes']?.round(),
        origin: recordOrigin,
      );

      if (!activity.hasAnyMetric) {
        reject('no metrics');
        continue;
      }
      final invalidField = activity.invalidField;
      if (invalidField != null) {
        reject(_describeInvalid(activity, invalidField));
        continue;
      }
      if (!seenDates.add(AppDateUtils.toDateKey(date))) {
        reject('duplicate date');
        continue;
      }

      days.add(activity);
    }

    return ActivityCsvParseResult(
      days: days,
      errors: errors,
      headerValid: true,
      ignoredColumns: ignored,
    );
  }

  static ActivityCsvParseResult _invalidHeader(int line, String reason) {
    return ActivityCsvParseResult(
      days: const <DailyActivity>[],
      errors: <ActivityCsvRowError>[
        ActivityCsvRowError(line: line, reason: reason),
      ],
      headerValid: false,
    );
  }

  static String _detectDelimiter(String text) {
    var commas = 0;
    var semicolons = 0;
    var inQuotes = false;
    var started = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '"') {
        inQuotes = !inQuotes;
        started = true;
      } else if (!inQuotes && (char == '\n' || char == '\r')) {
        if (started) {
          break;
        }
      } else if (!inQuotes && char == ',') {
        commas++;
        started = true;
      } else if (!inQuotes && char == ';') {
        semicolons++;
        started = true;
      } else if (char.trim().isNotEmpty) {
        started = true;
      }
    }
    return semicolons > commas ? ';' : ',';
  }

  /// Splits [text] into non-blank records, each tagged with the line it
  /// starts on.
  static List<_CsvRecord> _split(String text, String delimiter) {
    final records = <_CsvRecord>[];
    var fields = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var line = 1;
    var recordLine = 1;

    void endRecord() {
      fields.add(field.toString());
      field.clear();
      final blank = fields.every((value) => value.trim().isEmpty);
      if (!blank) {
        records.add(_CsvRecord(recordLine, fields));
      }
      fields = <String>[];
    }

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          if (char == '\n') {
            line++;
          }
          field.write(char);
        }
        continue;
      }

      if (char == '"') {
        inQuotes = true;
      } else if (char == delimiter) {
        fields.add(field.toString());
        field.clear();
      } else if (char == '\n' || char == '\r') {
        if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
          i++;
        }
        endRecord();
        line++;
        recordLine = line;
      } else {
        field.write(char);
      }
    }
    endRecord();

    return records;
  }

  static DateTime? _parseDate(String raw) {
    final match = _datePattern.firstMatch(raw);
    if (match == null) {
      return null;
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  static double? _parseNumber(String raw, {required bool decimalComma}) {
    var text = raw;
    if (decimalComma && text.contains(',')) {
      if (text.contains('.') || text.indexOf(',') != text.lastIndexOf(',')) {
        return null;
      }
      text = text.replaceFirst(',', '.');
    }
    if (!_numberPattern.hasMatch(text)) {
      return null;
    }
    final value = double.tryParse(text);
    if (value == null || !value.isFinite) {
      return null;
    }
    return value;
  }

  static const _fieldColumns = <String, String>{
    'activeKcal': 'active_kcal',
    'totalKcal': 'total_kcal',
    'steps': 'steps',
    'distanceMeters': 'distance_km',
    'activeMinutes': 'active_minutes',
  };

  static String _describeInvalid(DailyActivity activity, String field) {
    final column = _fieldColumns[field] ?? field;
    if (field == 'activeKcal') {
      final alone = DailyActivity(
        date: activity.date,
        source: activity.source,
        updatedAt: activity.updatedAt,
        activeKcal: activity.activeKcal,
      );
      if (alone.invalidField == null) {
        return 'active_kcal greater than total_kcal';
      }
    }
    return 'out of range $column';
  }
}

class _CsvRecord {
  const _CsvRecord(this.line, this.fields);

  final int line;
  final List<String> fields;
}
