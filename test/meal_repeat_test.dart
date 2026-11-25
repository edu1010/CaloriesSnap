import 'package:calorie_snap/core/l10n/app_localizations.dart';
import 'package:calorie_snap/data/repositories/meal_repository.dart';
import 'package:calorie_snap/data/repositories/nutrition_repository.dart';
import 'package:calorie_snap/features/meal_detail/meal_detail_screen.dart';
import 'package:calorie_snap/features/meal_detail/meal_repeat.dart';
import 'package:calorie_snap/features/register_meal/food_confirmation_screen.dart';
import 'package:calorie_snap/features/register_meal/meal_summary_screen.dart';
import 'package:calorie_snap/models/food_item.dart';
import 'package:calorie_snap/models/meal.dart';
import 'package:calorie_snap/services/nutrition/calorie_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in: no sqflite, records what the flow writes.
class _FakeMealRepository extends MealRepository {
  _FakeMealRepository(this.stored);

  final Meal stored;
  final List<Meal> inserted = <Meal>[];
  final List<Meal> updated = <Meal>[];

  @override
  Future<Meal?> getMealById(int mealId) async =>
      mealId == stored.id ? stored : null;

  @override
  Future<int> insertMeal(Meal meal) async {
    inserted.add(meal);
    return 99;
  }

  @override
  Future<void> updateMeal(Meal meal) async => updated.add(meal);
}

final _original = Meal(
  id: 7,
  dateTime: DateTime(2026, 3, 2, 21, 15),
  mealType: 'dinner',
  imagePath: '/data/meal_images/meal_1.jpg',
  foods: const <FoodItem>[
    FoodItem(
      id: 11,
      name: 'Pizza',
      grams: 200,
      kcalPer100g: 250,
      calculatedKcal: 500,
    ),
    FoodItem(
      id: 12,
      name: 'Salad',
      grams: 100,
      kcalPer100g: 20,
      calculatedKcal: 20,
    ),
  ],
  totalKcal: 520,
  lowerEstimateKcal: 442,
  upperEstimateKcal: 598,
  notes: 'Con amigos',
);

void main() {
  test('repeatable foods are id-free copies with the same quantities', () {
    final copies = repeatableFoods(_original);
    expect(copies, hasLength(2));
    expect(copies.every((food) => food.id == null), isTrue);
    expect(copies.map((f) => f.name), <String>['Pizza', 'Salad']);
    expect(copies.map((f) => f.grams), <double>[200, 100]);
    expect(copies.map((f) => f.kcalPer100g), <double>[250, 20]);
    expect(_original.foods.first.id, 11);
  });

  testWidgets(
    'repeat opens prefilled confirmation and saves a new meal for today',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final nutrition = NutritionRepository();
      await tester.runAsync(nutrition.load);
      final repository = _FakeMealRepository(_original);

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
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder:
                                  (_) => MealDetailScreen(
                                    meal: _original,
                                    mealRepository: repository,
                                    nutritionRepository: nutrition,
                                    calorieCalculator: CalorieCalculator(),
                                  ),
                            ),
                          ),
                      child: const Text('root'),
                    ),
                  ),
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('root'));
      await tester.pumpAndSettle();

      final repeat = find.byKey(const Key('repeat-meal'));
      await tester.ensureVisible(repeat);
      expect(find.text('Repetir comida'), findsOneWidget);
      await tester.tap(repeat);
      await tester.pumpAndSettle();

      // Prefilled, editable copies of the original foods.
      expect(find.byType(FoodConfirmationScreen), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Pizza'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Salad'), findsOneWidget);
      expect(find.text('Calorías aproximadas: 520 kcal'), findsOneWidget);

      // Edit a quantity on the copy.
      await tester.enterText(find.widgetWithText(TextField, '200'), '300');
      await tester.pumpAndSettle();
      expect(find.text('Calorías aproximadas: 770 kcal'), findsOneWidget);

      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(find.byType(MealSummaryScreen), findsOneWidget);

      final save = find.byIcon(Icons.save_outlined);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      // Inserted as a new meal, never an update of the original.
      expect(repository.updated, isEmpty);
      expect(repository.inserted, hasLength(1));
      final saved = repository.inserted.single;
      expect(saved.id, isNull);
      expect(saved.imagePath, isNull);
      expect(saved.mealType, 'Dinner');
      expect(saved.notes, 'Con amigos');
      final now = DateTime.now();
      expect(
        DateTime(saved.dateTime.year, saved.dateTime.month, saved.dateTime.day),
        DateTime(now.year, now.month, now.day),
      );
      expect(saved.foods.every((food) => food.id == null), isTrue);
      expect(saved.foods.map((f) => f.grams), <double>[300, 100]);
      expect(saved.totalKcal, 770);

      // Original untouched.
      expect(_original.foods.first.grams, 200);
      expect(_original.foods.first.id, 11);
      expect(_original.imagePath, isNotNull);

      // Single navigation back to the first route; no stray pops/exceptions.
      expect(find.text('root'), findsOneWidget);
      expect(find.byType(MealDetailScreen), findsNothing);
      expect(find.byType(FoodConfirmationScreen), findsNothing);
      expect(find.byType(MealSummaryScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('repeat label is English outside Spanish locales', (
    tester,
  ) async {
    late String label;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) {
            label = context.repeatMealLabel;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(label, 'Repeat meal');
  });
}
