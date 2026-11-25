import 'dart:async';

import 'package:calorie_snap/core/l10n/app_localizations.dart';
import 'package:calorie_snap/data/repositories/meal_repository.dart';
import 'package:calorie_snap/data/repositories/nutrition_repository.dart';
import 'package:calorie_snap/features/register_meal/food_confirmation_screen.dart';
import 'package:calorie_snap/features/register_meal/meal_summary_screen.dart';
import 'package:calorie_snap/models/food_item.dart';
import 'package:calorie_snap/services/food_detection/food_detection_service.dart';
import 'package:calorie_snap/services/food_detection/meal_analysis_service.dart';
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

  Future<void> showScreen(
    WidgetTester tester, {
    bool photo = true,
    String? description,
    _PendingAnalysis? analysis,
    bool seedFromDescription = false,
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
          imagePath: analysis != null ? 'analyzed-photo.jpg' : null,
          photoAnalysisService: analysis,
          description: description,
          seedFromDescription: seedFromDescription,
          initialFoods:
              photo || seedFromDescription
                  ? []
                  : const [
                    FoodItem(
                      name: 'Pizza',
                      grams: 200,
                      kcalPer100g: 250,
                      calculatedKcal: 500,
                    ),
                  ],
          photoCandidates: photo && analysis == null ? candidates : null,
          mealRepository: MealRepository(),
          nutritionRepository: nutrition,
          calorieCalculator: CalorieCalculator(),
        ),
      ),
    );
    if (analysis == null) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
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

  testWidgets('photo suggestions arrive without replacing entered grams', (
    tester,
  ) async {
    final analysis = _PendingAnalysis();
    await showScreen(
      tester,
      analysis: analysis,
      description: '150 g de arroz cocido',
      seedFromDescription: true,
    );

    expect(find.text('150'), findsOneWidget);
    expect(find.text('Gramos indicados'), findsOneWidget);
    expect(find.text('¿Lo pesaste en crudo o cocido?'), findsNothing);
    expect(find.text('Guardar sin esperar'), findsOneWidget);

    analysis.publish(
      const MealDetection(
        foods: <DetectedFood>[],
        candidates: candidates,
        engine: MealAnalysisEngine.classifier,
      ),
    );
    await tester.pump();
    expect(find.widgetWithText(ChoiceChip, 'Pizza'), findsOneWidget);

    analysis.complete(
      const MealDetection(
        foods: <DetectedFood>[
          DetectedFood(
            name: 'Arroz hervido',
            confidence: 0,
            suggestedGrams: 300,
            kcalPer100g: 116,
          ),
          DetectedFood(
            name: 'Aceite de oliva',
            confidence: 0,
            suggestedGrams: 10,
            kcalPer100g: 884,
          ),
        ],
        engine: MealAnalysisEngine.vlm,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('ajustar a 300 g'), findsNothing);
    final oil = find.widgetWithText(
      ActionChip,
      'Aceite de oliva · aprox. 10 g',
    );
    expect(oil, findsOneWidget);
    expect(find.widgetWithText(TextField, 'Aceite de oliva'), findsNothing);
    await tester.ensureVisible(oil);
    await tester.tap(oil);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    final summary = tester.widget<MealSummaryScreen>(
      find.byType(MealSummaryScreen),
    );
    expect(summary.foods.map((food) => food.grams), <double>[150, 10]);
  });

  testWidgets('can review the draft without waiting for photo analysis', (
    tester,
  ) async {
    final analysis = _PendingAnalysis();
    await showScreen(tester, analysis: analysis);
    analysis.publish(
      const MealDetection(
        foods: <DetectedFood>[
          DetectedFood(
            name: 'Pizza',
            confidence: .95,
            suggestedGrams: 200,
            kcalPer100g: 250,
          ),
        ],
        candidates: candidates,
        engine: MealAnalysisEngine.classifier,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Guardar sin esperar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final summary = tester.widget<MealSummaryScreen>(
      find.byType(MealSummaryScreen),
    );
    expect(summary.foods.single.name, 'Pizza');
    expect(summary.foods.single.grams, 200);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(analysis.cancellation.isCanceled, isTrue);
    analysis.complete(
      const MealDetection(
        foods: <DetectedFood>[],
        engine: MealAnalysisEngine.vlm,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('can explicitly accept a new estimate for the same food', (
    tester,
  ) async {
    final analysis = _PendingAnalysis();
    await showScreen(tester, analysis: analysis);
    analysis.publish(
      const MealDetection(
        foods: <DetectedFood>[
          DetectedFood(
            name: 'Pizza',
            confidence: .95,
            suggestedGrams: 200,
            kcalPer100g: 250,
          ),
        ],
        candidates: candidates,
        engine: MealAnalysisEngine.classifier,
      ),
    );
    await tester.pump();
    analysis.complete(
      const MealDetection(
        foods: <DetectedFood>[
          DetectedFood(
            name: 'Pizza',
            confidence: 0,
            suggestedGrams: 120,
            kcalPer100g: 250,
          ),
        ],
        engine: MealAnalysisEngine.vlm,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Calorías aproximadas: 500 kcal'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(ActionChip, 'Pizza · ajustar a 120 g'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Calorías aproximadas: 300 kcal'), findsOneWidget);
  });

  testWidgets(
    'text-only draft asks how an unspecified rice weight was measured',
    (tester) async {
      await showScreen(
        tester,
        photo: false,
        description: '150 g de arroz',
        seedFromDescription: true,
      );
      expect(find.text('¿Lo pesaste en crudo o cocido?'), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, 'En crudo'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Arroz crudo'), findsOneWidget);
      expect(find.text('150'), findsOneWidget);
      expect(find.text('¿Lo pesaste en crudo o cocido?'), findsNothing);
    },
  );

  testWidgets('text-only draft preserves an explicit raw weight', (
    tester,
  ) async {
    await showScreen(
      tester,
      photo: false,
      description: '80 g de arroz en crudo',
      seedFromDescription: true,
    );

    expect(find.widgetWithText(TextField, 'Arroz crudo'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
    expect(find.text('Gramos indicados'), findsOneWidget);
    expect(find.text('¿Lo pesaste en crudo o cocido?'), findsNothing);
  });

  testWidgets('unknown household conversion requires a weight before review', (
    tester,
  ) async {
    await showScreen(
      tester,
      photo: false,
      description: '2 tazas de arroz',
      seedFromDescription: true,
    );

    expect(find.text('Indica el peso de «2 tazas»'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.byType(MealSummaryScreen), findsNothing);
  });
}

class _PendingAnalysis implements ProgressiveMealAnalysisService {
  final Completer<MealDetection> _finalResult = Completer<MealDetection>();
  late void Function(MealDetection) publish;
  late MealAnalysisCancellation cancellation;

  void complete(MealDetection result) => _finalResult.complete(result);

  @override
  Future<MealDetection> analyze(
    String imagePath, {
    required String languageCode,
    String? description,
    void Function(MealAnalysisStage stage)? onStage,
  }) => throw UnimplementedError();

  @override
  Future<MealDetection> analyzeProgressively(
    String imagePath, {
    required String languageCode,
    String? description,
    void Function(MealAnalysisStage stage)? onStage,
    required void Function(MealDetection result) onClassifierResult,
    required MealAnalysisCancellation cancellation,
  }) {
    publish = onClassifierResult;
    this.cancellation = cancellation;
    return _finalResult.future;
  }
}
