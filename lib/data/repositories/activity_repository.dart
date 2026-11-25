import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/utils/app_date_utils.dart';
import '../../models/calorie_goals.dart';
import '../../models/daily_activity.dart';
import '../../services/activity/activity_store.dart';

/// SQLite-backed [ActivityStore].
///
/// Lives in its own database file so the meals database and its schema are
/// left untouched.
class SqliteActivityStore implements ActivityStore {
  SqliteActivityStore({Future<Database> Function()? openDatabaseOverride})
    : _openDatabaseOverride = openDatabaseOverride;

  static const databaseFileName = 'calorie_snap_activity.db';
  static const schemaVersion = 1;

  static const _dailyGoalKey = 'daily_kcal';
  static const _weeklyGoalKey = 'weekly_kcal';

  final Future<Database> Function()? _openDatabaseOverride;
  Database? _database;

  /// Creates every table of [schemaVersion]. Usable as an `onCreate` callback.
  static Future<void> createSchema(Database db, int version) {
    return _createTables(db);
  }

  static Future<void> _createTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE goals (
        key TEXT PRIMARY KEY,
        value REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_activity (
        date_key TEXT NOT NULL,
        source TEXT NOT NULL,
        active_kcal REAL,
        total_kcal REAL,
        steps INTEGER,
        distance_meters REAL,
        active_minutes INTEGER,
        origin TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (date_key, source)
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_state (
        source TEXT PRIMARY KEY,
        last_success_at TEXT,
        last_attempt_at TEXT,
        last_error TEXT,
        last_imported_days INTEGER
      )
    ''');
  }

  Future<void> init() async {
    if (_database != null) {
      return;
    }

    final override = _openDatabaseOverride;
    if (override != null) {
      final db = await override();
      // A database opened without version/onCreate still gets the schema.
      if (await db.getVersion() == 0) {
        await db.transaction((txn) async {
          final existing = await txn.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
            <Object?>['daily_activity'],
          );
          if (existing.isEmpty) {
            await _createTables(txn);
          }
        });
        await db.setVersion(schemaVersion);
      }
      _database = db;
      return;
    }

    final documentsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(documentsDir.path, databaseFileName);

    _database = await openDatabase(
      dbPath,
      version: schemaVersion,
      onCreate: createSchema,
    );
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }

  Future<Database> get _db async {
    if (_database == null) {
      await init();
    }
    return _database!;
  }

  @override
  Future<CalorieGoals> loadGoals() async {
    final db = await _db;
    final rows = await db.query('goals');

    double? daily;
    double? weekly;
    for (final row in rows) {
      final value = (row['value'] as num?)?.toDouble();
      if (row['key'] == _dailyGoalKey) {
        daily = value;
      } else if (row['key'] == _weeklyGoalKey) {
        weekly = value;
      }
    }
    return CalorieGoals(dailyKcal: daily, weeklyKcal: weekly);
  }

  @override
  Future<void> saveGoals(CalorieGoals goals) async {
    if (!CalorieGoals.isValidDaily(goals.dailyKcal)) {
      throw ArgumentError.value(goals.dailyKcal, 'dailyKcal');
    }
    if (!CalorieGoals.isValidWeekly(goals.weeklyKcal)) {
      throw ArgumentError.value(goals.weeklyKcal, 'weeklyKcal');
    }

    final db = await _db;
    await db.transaction((txn) async {
      await _writeGoal(txn, _dailyGoalKey, goals.dailyKcal);
      await _writeGoal(txn, _weeklyGoalKey, goals.weeklyKcal);
    });
  }

  Future<void> _writeGoal(Transaction txn, String key, double? value) async {
    if (value == null) {
      await txn.delete('goals', where: 'key = ?', whereArgs: <Object?>[key]);
      return;
    }
    await txn.insert('goals', <String, Object?>{
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> upsert(DailyActivity activity) async {
    _validate(activity);
    final db = await _db;
    await db.insert(
      'daily_activity',
      _toRow(activity),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> replaceRange(
    ActivitySource source,
    DateTime startInclusive,
    DateTime endExclusive,
    List<DailyActivity> days,
  ) async {
    final startKey = AppDateUtils.toDateKey(startInclusive);
    final endKey = AppDateUtils.toDateKey(endExclusive);

    for (final day in days) {
      _validate(day);
      if (day.source != source) {
        throw ArgumentError.value(day.source, 'days', 'Expected $source');
      }
      final key = AppDateUtils.toDateKey(day.date);
      if (key.compareTo(startKey) < 0 || key.compareTo(endKey) >= 0) {
        throw ArgumentError.value(day.date, 'days', 'Outside of the range');
      }
    }

    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        'daily_activity',
        where: 'source = ? AND date_key >= ? AND date_key < ?',
        whereArgs: <Object?>[source.storageKey, startKey, endKey],
      );
      for (final day in days) {
        await txn.insert(
          'daily_activity',
          _toRow(day),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<void> delete(DateTime day, ActivitySource source) async {
    final db = await _db;
    await db.delete(
      'daily_activity',
      where: 'date_key = ? AND source = ?',
      whereArgs: <Object?>[AppDateUtils.toDateKey(day), source.storageKey],
    );
  }

  @override
  Future<List<DailyActivity>> recordsForDay(DateTime day) async {
    final db = await _db;
    final rows = await db.query(
      'daily_activity',
      where: 'date_key = ?',
      whereArgs: <Object?>[AppDateUtils.toDateKey(day)],
    );

    final records = <DailyActivity>[];
    for (final row in rows) {
      final record = _fromRow(row);
      if (record != null) {
        records.add(record);
      }
    }
    records.sort((a, b) => a.source.index.compareTo(b.source.index));
    return records;
  }

  @override
  Future<Map<DateTime, DailyActivity>> effectiveForRange(
    DateTime startInclusive,
    DateTime endExclusive,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'daily_activity',
      where: 'date_key >= ? AND date_key < ?',
      whereArgs: <Object?>[
        AppDateUtils.toDateKey(startInclusive),
        AppDateUtils.toDateKey(endExclusive),
      ],
      orderBy: 'date_key ASC',
    );

    final map = <DateTime, DailyActivity>{};
    for (final row in rows) {
      final record = _fromRow(row);
      if (record == null) {
        continue;
      }
      final current = map[record.date];
      if (current == null || record.source.index < current.source.index) {
        map[record.date] = record;
      }
    }
    return map;
  }

  @override
  Future<ActivitySyncState?> loadSyncState(ActivitySource source) async {
    final db = await _db;
    final rows = await db.query(
      'sync_state',
      where: 'source = ?',
      whereArgs: <Object?>[source.storageKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    return ActivitySyncState(
      source: source,
      lastSuccessAt: _parseDateTime(row['last_success_at']),
      lastAttemptAt: _parseDateTime(row['last_attempt_at']),
      lastError: row['last_error'] as String?,
      lastImportedDays: (row['last_imported_days'] as num?)?.toInt(),
    );
  }

  @override
  Future<void> saveSyncState(ActivitySyncState state) async {
    final db = await _db;
    await db.insert('sync_state', <String, Object?>{
      'source': state.source.storageKey,
      'last_success_at': state.lastSuccessAt?.toIso8601String(),
      'last_attempt_at': state.lastAttemptAt?.toIso8601String(),
      'last_error': state.lastError,
      'last_imported_days': state.lastImportedDays,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  void _validate(DailyActivity activity) {
    final invalidField = activity.invalidField;
    if (invalidField != null) {
      throw ArgumentError.value(activity, 'activity', 'Invalid $invalidField');
    }
    if (!activity.hasAnyMetric) {
      throw ArgumentError.value(activity, 'activity', 'No metric');
    }
  }

  Map<String, Object?> _toRow(DailyActivity activity) {
    return <String, Object?>{
      'date_key': AppDateUtils.toDateKey(activity.date),
      'source': activity.source.storageKey,
      'active_kcal': activity.activeKcal,
      'total_kcal': activity.totalKcal,
      'steps': activity.steps,
      'distance_meters': activity.distanceMeters,
      'active_minutes': activity.activeMinutes,
      'origin': activity.origin,
      'updated_at': activity.updatedAt.toIso8601String(),
    };
  }

  DailyActivity? _fromRow(Map<String, Object?> row) {
    final source = ActivitySource.fromStorageKey(row['source'] as String?);
    if (source == null) {
      return null;
    }

    final date = AppDateUtils.fromDateKey(row['date_key'] as String);
    return DailyActivity(
      date: date,
      source: source,
      updatedAt: _parseDateTime(row['updated_at']) ?? date,
      activeKcal: (row['active_kcal'] as num?)?.toDouble(),
      totalKcal: (row['total_kcal'] as num?)?.toDouble(),
      steps: (row['steps'] as num?)?.toInt(),
      distanceMeters: (row['distance_meters'] as num?)?.toDouble(),
      activeMinutes: (row['active_minutes'] as num?)?.toInt(),
      origin: row['origin'] as String?,
    );
  }

  DateTime? _parseDateTime(Object? value) {
    if (value is! String) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}
