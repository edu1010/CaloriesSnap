import 'package:calorie_snap/core/l10n/app_localizations.dart';
import 'package:calorie_snap/data/repositories/meal_repository.dart';
import 'package:calorie_snap/data/repositories/nutrition_repository.dart';
import 'package:calorie_snap/features/register_meal/food_confirmation_screen.dart';
import 'package:calorie_snap/features/register_meal/meal_summary_screen.dart';
import 'package:calorie_snap/models/food_item.dart';
import 'package:calorie_snap/services/food_detection/food_detection_service.dart';
import 'package:calorie_snap/services/nutrition/calorie_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const candidates = <DetectedFood>[
    DetectedFood(
      name: 'Pizza',
      confidence: .35,
      suggestedGrams: 200,
      kcalPer100g: 250,
      requiresConfirmation: true,
    ),
    DetectedFood(
      name: 'Hamburger',
      confidence: .3,
      suggestedGrams: 150,
      kcalPer100g: 300,
    ),
  ];

  Future<void> showScreen(WidgetTester tester, {bool photo = true}) async {
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
          initialFoods:
              photo
                  ? []
                  : const [
                    FoodItem(
                      name: 'Pizza',
                      grams: 200,
                      kcalPer100g: 250,
                      calculatedKcal: 500,
                    ),
                  ],
          photoCandidates: photo ? candidates : null,
          mealRepository: MealRepository(),
          nutritionRepository: nutrition,
          calorieCalculator: CalorieCalculator(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'uncertain alternatives require selection and replace each other',
    (tester) async {
      await showScreen(tester);
      expect(find.text('Calorías aproximadas: 0 kcal'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Pizza'));
      await tester.pumpAndSettle();
      expect(find.text('Calorías aproximadas: 500 kcal'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Hamburger'));
      await tester.pumpAndSettle();
      expect(find.text('Calorías aproximadas: 450 kcal'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'decimal comma changes grams and calories, invalid input cannot continue',
    (tester) async {
      await showScreen(tester, photo: false);
      final grams = find.byType(TextField).at(1);
      await tester.enterText(grams, '125,5');
      await tester.pumpAndSettle();
      expect(find.text('Calorías aproximadas: 314 kcal'), findsOneWidget);
      await tester.enterText(grams, '-10');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(find.byType(MealSummaryScreen), findsNothing);
      expect(find.textContaining('gramos mayores que cero'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('known food correction updates calorie density', (tester) async {
    await showScreen(tester, photo: false);
    await tester.enterText(find.byType(TextField).first, 'Olive oil');
    await tester.pumpAndSettle();
    expect(find.text('884'), findsOneWidget);
    expect(find.text('Calorías aproximadas: 1768 kcal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
