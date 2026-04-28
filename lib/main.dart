import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'data/repositories/meal_repository.dart';
import 'data/repositories/nutrition_repository.dart';
import 'services/food_detection/food_detection_service.dart';
import 'services/food_detection/local_ai_food_detection_service.dart';
import 'services/image/image_storage_service.dart';
import 'services/nutrition/calorie_calculator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final mealRepository = MealRepository();
  await mealRepository.init();

  final nutritionRepository = NutritionRepository();
  await nutritionRepository.load();

  final FoodDetectionService foodDetectionService = LocalAiFoodDetectionService(
    nutritionRepository: nutritionRepository,
  );

  runApp(
    CalorieSnapApp(
      mealRepository: mealRepository,
      nutritionRepository: nutritionRepository,
      foodDetectionService: foodDetectionService,
      imageStorageService: ImageStorageService(),
      calorieCalculator: CalorieCalculator(),
    ),
  );
}
