import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/utils/app_date_utils.dart';
import '../../models/daily_summary.dart';
import '../../models/food_item.dart';
import '../../models/meal.dart';

class MealRepository {
  Database? _database;

  Future<void> init() async {
    if (_database != null) {
      return;
    }

    final documentsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(documentsDir.path, 'calorie_snap.db');

    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE meals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date_time TEXT NOT NULL,
            meal_type TEXT NOT NULL,
            image_path TEXT,
            total_kcal REAL NOT NULL,
            lower_estimate_kcal REAL NOT NULL,
            upper_estimate_kcal REAL NOT NULL,
            notes TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE food_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            meal_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            grams REAL NOT NULL,
            kcal_per_100g REAL NOT NULL,
            calculated_kcal REAL NOT NULL,
            FOREIGN KEY (meal_id) REFERENCES meals(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('CREATE INDEX idx_meals_date ON meals(date_time)');
        await db.execute('CREATE INDEX idx_food_items_meal ON food_items(meal_id)');
      },
    );
  }

  Future<Database> get _db async {
    if (_database == null) {
      await init();
    }
    return _database!;
  }

  Future<int> insertMeal(Meal meal) async {
    final db = await _db;
    return db.transaction((txn) async {
      final mealData = meal.toDatabaseMap()..remove('id');
      final mealId = await txn.insert('meals', mealData);

      for (final food in meal.foods) {
        final foodMap = food.toDatabaseMap(mealId: mealId)..remove('id');
        await txn.insert('food_items', foodMap);
      }

      return mealId;
    });
  }

  Future<void> updateMeal(Meal meal) async {
    if (meal.id == null) {
      throw ArgumentError('Meal id cannot be null when updating');
    }

    final db = await _db;
    await db.transaction((txn) async {
      final mealData = meal.toDatabaseMap()..remove('id');
      await txn.update(
        'meals',
        mealData,
        where: 'id = ?',
        whereArgs: <Object?>[meal.id],
      );

      await txn.delete(
        'food_items',
        where: 'meal_id = ?',
        whereArgs: <Object?>[meal.id],
      );

      for (final food in meal.foods) {
        final foodMap = food.toDatabaseMap(mealId: meal.id!)..remove('id');
        await txn.insert('food_items', foodMap);
      }
    });
  }

  Future<void> deleteMeal(int mealId) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        'food_items',
        where: 'meal_id = ?',
        whereArgs: <Object?>[mealId],
      );
      await txn.delete(
        'meals',
        where: 'id = ?',
        whereArgs: <Object?>[mealId],
      );
    });
  }

  Future<Meal?> getMealById(int mealId) async {
    final db = await _db;
    final mealRows = await db.query(
      'meals',
      where: 'id = ?',
      whereArgs: <Object?>[mealId],
      limit: 1,
    );
    if (mealRows.isEmpty) {
      return null;
    }

    final foods = await _getFoodsForMeal(mealId);
    return Meal.fromMap(mealRows.first, foods: foods);
  }

  Future<List<Meal>> getMealsForDay(DateTime day) async {
    final db = await _db;
    final start = AppDateUtils.startOfDay(day);
    final end = AppDateUtils.startOfNextDay(day);

    final mealRows = await db.query(
      'meals',
      where: 'date_time >= ? AND date_time < ?',
      whereArgs: <Object?>[start.toIso8601String(), end.toIso8601String()],
      orderBy: 'date_time DESC',
    );

    if (mealRows.isEmpty) {
      return <Meal>[];
    }

    final mealIds = mealRows.map((row) => row['id'] as int).toList();
    final foodsByMeal = await _getFoodsForMeals(mealIds);

    return mealRows.map((row) {
      final mealId = row['id'] as int;
      return Meal.fromMap(row, foods: foodsByMeal[mealId] ?? <FoodItem>[]);
    }).toList();
  }

  Future<DailySummary> getDailySummary(DateTime day) async {
    final db = await _db;
    final start = AppDateUtils.startOfDay(day);
    final end = AppDateUtils.startOfNextDay(day);

    final rows = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS meals_count,
        COALESCE(SUM(total_kcal), 0) AS total_kcal
      FROM meals
      WHERE date_time >= ? AND date_time < ?
      ''',
      <Object?>[start.toIso8601String(), end.toIso8601String()],
    );

    final row = rows.first;
    return DailySummary(
      date: start,
      mealsCount: (row['meals_count'] as num?)?.toInt() ?? 0,
      totalKcal: (row['total_kcal'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<Map<DateTime, DailySummary>> getDailySummariesForMonth(
    DateTime month,
  ) async {
    final db = await _db;
    final start = AppDateUtils.startOfMonth(month);
    final end = AppDateUtils.startOfNextMonth(month);

    final rows = await db.rawQuery(
      '''
      SELECT
        substr(date_time, 1, 10) AS day_key,
        COUNT(*) AS meals_count,
        COALESCE(SUM(total_kcal), 0) AS total_kcal
      FROM meals
      WHERE date_time >= ? AND date_time < ?
      GROUP BY day_key
      ''',
      <Object?>[start.toIso8601String(), end.toIso8601String()],
    );

    final map = <DateTime, DailySummary>{};
    for (final row in rows) {
      final dayKey = row['day_key'] as String;
      final date = AppDateUtils.fromDateKey(dayKey);
      map[date] = DailySummary(
        date: date,
        mealsCount: (row['meals_count'] as num?)?.toInt() ?? 0,
        totalKcal: (row['total_kcal'] as num?)?.toDouble() ?? 0,
      );
    }

    return map;
  }

  Future<List<FoodItem>> _getFoodsForMeal(int mealId) async {
    final db = await _db;
    final rows = await db.query(
      'food_items',
      where: 'meal_id = ?',
      whereArgs: <Object?>[mealId],
      orderBy: 'id ASC',
    );
    return rows.map(FoodItem.fromMap).toList();
  }

  Future<Map<int, List<FoodItem>>> _getFoodsForMeals(List<int> mealIds) async {
    if (mealIds.isEmpty) {
      return <int, List<FoodItem>>{};
    }

    final db = await _db;
    final placeholders = List<String>.filled(mealIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT * FROM food_items WHERE meal_id IN ($placeholders) ORDER BY id ASC',
      mealIds,
    );

    final result = <int, List<FoodItem>>{};
    for (final row in rows) {
      final mealId = row['meal_id'] as int;
      result.putIfAbsent(mealId, () => <FoodItem>[]).add(FoodItem.fromMap(row));
    }
    return result;
  }
}
