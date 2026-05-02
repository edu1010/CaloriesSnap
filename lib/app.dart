import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/l10n/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/meal_repository.dart';
import 'data/repositories/nutrition_repository.dart';
import 'features/home/home_screen.dart';
import 'services/barcode/open_food_facts_service.dart';
import 'services/food_detection/food_detection_service.dart';
import 'services/image/image_storage_service.dart';
import 'services/nutrition/calorie_calculator.dart';

class CalorieSnapApp extends StatelessWidget {
  const CalorieSnapApp({
    super.key,
    required this.mealRepository,
    required this.nutritionRepository,
    required this.foodDetectionService,
    required this.openFoodFactsService,
    required this.imageStorageService,
    required this.calorieCalculator,
  });

  final MealRepository mealRepository;
  final NutritionRepository nutritionRepository;
  final FoodDetectionService foodDetectionService;
  final OpenFoodFactsService openFoodFactsService;
  final ImageStorageService imageStorageService;
  final CalorieCalculator calorieCalculator;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (locale, supportedLocales) {
        if (locale == null) {
          return const Locale('en');
        }
        if (locale.languageCode.toLowerCase().startsWith('es')) {
          return const Locale('es');
        }
        return const Locale('en');
      },
      home: HomeScreen(
        mealRepository: mealRepository,
        nutritionRepository: nutritionRepository,
        foodDetectionService: foodDetectionService,
        openFoodFactsService: openFoodFactsService,
        imageStorageService: imageStorageService,
        calorieCalculator: calorieCalculator,
      ),
    );
  }
}
