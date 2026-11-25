import 'package:calorie_snap/app.dart';
import 'package:calorie_snap/data/repositories/meal_repository.dart';
import 'package:calorie_snap/data/repositories/nutrition_repository.dart';
import 'package:calorie_snap/features/activity/activity_dashboard_screen.dart';
import 'package:calorie_snap/models/calorie_goals.dart';
import 'package:calorie_snap/models/daily_summary.dart';
import 'package:calorie_snap/services/activity/activity_sync_coordinator.dart';
import 'package:calorie_snap/services/activity/energy_dashboard_service.dart';
import 'package:calorie_snap/services/activity/health_connect_activity_source.dart';
import 'package:calorie_snap/services/barcode/open_food_facts_service.dart';
import 'package:calorie_snap/services/food_detection/meal_analysis_service.dart';
import 'package:calorie_snap/services/food_detection/vlm/vlm_model_catalog.dart';
import 'package:calorie_snap/services/food_detection/vlm/vlm_model_store.dart';
import 'package:calorie_snap/services/image/image_storage_service.dart';
import 'package:calorie_snap/services/nutrition/calorie_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_activity_store.dart';

class _Meals extends MealRepository {
  @override
  Future<DailySummary> getDailySummary(DateTime day) async =>
      DailySummary(date: day, mealsCount: 3, totalKcal: 1800);
}

class _UnusedAnalysis implements MealAnalysisService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Meal analysis is not part of this navigation test');
}

class _FirstRunModels extends VlmModelStore {
  bool _finishedOnboarding = false;
  VlmDownloadProgress? _pendingDownload;

  @override
  bool get needsOnboarding => !_finishedOnboarding;

  @override
  VlmDownloadProgress? get progress => _pendingDownload;

  @override
  Future<void> download(VlmModelSpec spec) async {
    _pendingDownload = VlmDownloadProgress(
      spec: spec,
      phase: VlmDownloadPhase.downloading,
      receivedBytes: 0,
    );
    notifyListeners();
  }

  @override
  Future<void> finishOnboarding() async {
    _finishedOnboarding = true;
    notifyListeners();
  }
}

CalorieSnapApp _app(VlmModelStore models, FakeActivityStore store) =>
    CalorieSnapApp(
      mealRepository: _Meals(),
      nutritionRepository: NutritionRepository(),
      mealAnalysisService: _UnusedAnalysis(),
      vlmModelStore: models,
      openFoodFactsService: OpenFoodFactsService(),
      imageStorageService: ImageStorageService(),
      calorieCalculator: CalorieCalculator(),
      energyDashboardService: EnergyDashboardService(
        store: store,
        loadIntake: (_, _) async => <DateTime, DailySummary>{},
      ),
      activitySyncCoordinator: ActivitySyncCoordinator(
        store: store,
        source: HealthConnectActivitySource(isAndroid: false),
      ),
    );

void main() {
  testWidgets('goals remain reachable on a small phone with a saved target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('es')];
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final store =
        FakeActivityStore()
          ..goals = const CalorieGoals(dailyKcal: 2200, weeklyKcal: 15000);
    final models = VlmModelStore();
    addTearDown(models.dispose);
    await tester.pumpWidget(_app(models, store));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final action = find.widgetWithText(OutlinedButton, 'Objetivos y actividad');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.byType(ActivityDashboardScreen), findsOneWidget);
    expect(find.text('Objetivo semanal'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first launch can start a model download and continue to home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('es')];
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final models = _FirstRunModels();
    addTearDown(models.dispose);

    await tester.pumpWidget(_app(models, FakeActivityStore()));
    await tester.pumpAndSettle();
    expect(find.text('Configura la IA de tus fotos'), findsOneWidget);
    expect(find.text('Empezar con el clasificador rápido'), findsOneWidget);
    final download = find.byKey(
      ValueKey('download-ai-${VlmModelCatalog.lfm3.id}'),
    );
    await tester.scrollUntilVisible(download, 100);
    await tester.pumpAndSettle();
    await tester.tap(download);
    await tester.pumpAndSettle();
    expect(models.progress?.spec, VlmModelCatalog.lfm3);

    await tester.tap(find.text('Continuar mientras se descarga'));
    await tester.pumpAndSettle();
    expect(find.text('Configura la IA de tus fotos'), findsNothing);
    await tester.tap(find.byTooltip('IA local'));
    await tester.pumpAndSettle();
    expect(find.text('IA local'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Cancelar descarga'), 160);
    await tester.pumpAndSettle();
    expect(find.text('Cancelar descarga').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
