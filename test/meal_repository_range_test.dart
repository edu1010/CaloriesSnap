import 'dart:io';

import 'package:calorie_snap/data/repositories/meal_repository.dart';
import 'package:calorie_snap/models/food_item.dart';
import 'package:calorie_snap/models/meal.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Meal _meal(DateTime dateTime, double kcal) {
  return Meal(
    dateTime: dateTime,
    mealType: 'lunch',
    foods: const <FoodItem>[],
    totalKcal: kcal,
    lowerEstimateKcal: kcal,
    upperEstimateKcal: kcal,
    notes: '',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;
  late MealRepository repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('calorie_snap_meals_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => tempDir.path);

    // MealRepository has no injectable database: make sure the mocked
    // documents directory is really in effect before it opens anything.
    final documentsDir = await getApplicationDocumentsDirectory();
    if (documentsDir.path != tempDir.path) {
      fail(
        'path_provider is not mocked: refusing to touch ${documentsDir.path}',
      );
    }

    repository = MealRepository();
    await repository.init();

    await repository.insertMeal(_meal(DateTime(2026, 3, 8, 23, 59), 111));
    await repository.insertMeal(_meal(DateTime(2026, 3, 9, 0, 0), 300));
    await repository.insertMeal(_meal(DateTime(2026, 3, 9, 21, 30), 700));
    await repository.insertMeal(_meal(DateTime(2026, 3, 15, 23, 59), 500));
    await repository.insertMeal(_meal(DateTime(2026, 3, 16, 0, 0), 222));
    await repository.insertMeal(_meal(DateTime(2026, 4, 1, 12), 400));
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await databaseFactory.deleteDatabase('${tempDir.path}/calorie_snap.db');
    await tempDir.delete(recursive: true);
  });

  test(
    'getDailySummariesForRange groups by local day, end exclusive',
    () async {
      final summaries = await repository.getDailySummariesForRange(
        DateTime(2026, 3, 9),
        DateTime(2026, 3, 16),
      );

      expect(summaries.keys.toSet(), <DateTime>{
        DateTime(2026, 3, 9),
        DateTime(2026, 3, 15),
      });
      expect(summaries[DateTime(2026, 3, 9)]!.totalKcal, 1000);
      expect(summaries[DateTime(2026, 3, 9)]!.mealsCount, 2);
      expect(summaries[DateTime(2026, 3, 15)]!.totalKcal, 500);
      expect(summaries[DateTime(2026, 3, 15)]!.mealsCount, 1);
    },
  );

  test('a range may span two months', () async {
    final summaries = await repository.getDailySummariesForRange(
      DateTime(2026, 3, 30),
      DateTime(2026, 4, 6),
    );
    expect(summaries.keys.single, DateTime(2026, 4, 1));
  });

  test('an empty range has no entries', () async {
    final summaries = await repository.getDailySummariesForRange(
      DateTime(2026, 5, 4),
      DateTime(2026, 5, 11),
    );
    expect(summaries, isEmpty);
  });

  test('getDailySummariesForMonth still covers exactly the month', () async {
    final march = await repository.getDailySummariesForMonth(
      DateTime(2026, 3, 20),
    );
    expect(march.keys.toSet(), <DateTime>{
      DateTime(2026, 3, 8),
      DateTime(2026, 3, 9),
      DateTime(2026, 3, 15),
      DateTime(2026, 3, 16),
    });
    expect(march[DateTime(2026, 3, 16)]!.totalKcal, 222);
  });
}
