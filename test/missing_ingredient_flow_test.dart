import 'package:calorie_snap/core/l10n/app_localizations.dart';
import 'package:calorie_snap/data/repositories/meal_repository.dart';
import 'package:calorie_snap/data/repositories/nutrition_repository.dart';
import 'package:calorie_snap/features/register_meal/food_confirmation_screen.dart';
import 'package:calorie_snap/models/food_item.dart';
import 'package:calorie_snap/services/food_detection/food_detection_service.dart';
import 'package:calorie_snap/services/food_detection/meal_analysis_service.dart';
import 'package:calorie_snap/services/nutrition/calorie_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> showScreen(
    WidgetTester tester, {
    String? description,
    List<FoodItem> foods = const <FoodItem>[],
  }) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final nutrition = NutritionRepository();
    await tester.runAsync(nutrition.load);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: FoodConfirmationScreen(
          initialFoods: foods,
          photoCandidates: const <DetectedFood>[],
          detection: const MealDetection(
            foods: <DetectedFood>[],
            engine: MealAnalysisEngine.classifier,
          ),
          description: description,
          mealRepository: MealRepository(),
          nutritionRepository: nutrition,
          calorieCalculator: CalorieCalculator(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('search "arroz", choose fried and add it to the meal', (
    tester,
  ) async {
    await showScreen(tester);
    expect(find.text('¿Falta algún ingrediente?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-missing-ingredient')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('food-search-field')), 'arroz');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('food-hit-rice')));
    await tester.pumpAndSettle();

    // Preparations of rice, boiled by default.
    for (final label in <String>['Crudo', 'Hervido', 'Frito']) {
      expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(ChoiceChip, 'Frito'));
    await tester.pumpAndSettle();
    expect(find.text('Arroz frito'), findsOneWidget);
    expect(find.text('Proteínas'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('food-grams-field')), '200');
    await tester.pumpAndSettle();
    expect(find.text('Tu ración: 200 g · 366 kcal'), findsOneWidget);
    await tester.tap(find.byKey(const Key('food-add-button')));
    await tester.pumpAndSettle();

    expect(find.text('Calorías aproximadas: 366 kcal'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Arroz frito'), findsOneWidget);
  });

  testWidgets('foods named in the description are offered until added', (
    tester,
  ) async {
    await showScreen(
      tester,
      description: 'arroz frito con 150 g de pechuga de pollo a la plancha',
      foods: const <FoodItem>[
        FoodItem(
          name: 'Arroz frito',
          grams: 200,
          kcalPer100g: 163,
          calculatedKcal: 326,
        ),
      ],
    );

    // Rice is already listed; only the chicken is missing.
    expect(find.widgetWithText(ActionChip, 'Arroz frito'), findsNothing);
    final chicken = find.widgetWithText(
      ActionChip,
      'Pechuga de pollo a la plancha',
    );
    expect(chicken, findsOneWidget);

    await tester.tap(chicken);
    await tester.pumpAndSettle();
    expect(find.text('Tu ración: 150 g · 212 kcal'), findsOneWidget);
    await tester.tap(find.byKey(const Key('food-add-button')));
    await tester.pumpAndSettle();

    expect(chicken, findsNothing);
    expect(find.text('Calorías aproximadas: 538 kcal'), findsOneWidget);
  });
}
