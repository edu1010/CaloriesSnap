import 'package:calorie_snap/data/repositories/nutrition_repository.dart';
import 'package:calorie_snap/services/food_detection/food_detection_service.dart';
import 'package:calorie_snap/services/food_detection/hybrid_food_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Detector implements FoodDetectionService {
  _Detector(this.result, {this.error});
  final List<DetectedFood> result;
  final Object? error;
  int calls = 0;
  @override
  Future<List<DetectedFood>> detectFoods(String imagePath) async {
    calls++;
    if (error != null) throw error!;
    return result;
  }
}

DetectedFood _dish(String name, double confidence) => DetectedFood(
  name: name,
  confidence: confidence,
  suggestedGrams: 100,
  kcalPer100g: 100,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NutritionRepository repository;
  setUp(() async {
    repository = NutritionRepository();
    await repository.load();
  });

  HybridFoodDetectionService hybrid(_Detector specialist, _Detector general) =>
      HybridFoodDetectionService(
        nutritionRepository: repository,
        specialist: specialist,
        general: general,
      );

  test(
    'Spanish specialist winner routes regardless of competing model confidence',
    () async {
      final specialist = _Detector([_dish('Albondigas', 0.04)]);
      final general = _Detector([_dish('Pizza', 0.99)]);
      expect(
        (await hybrid(specialist, general).detectFoods('meal')).single.name,
        'Albondigas',
      );
      expect(general.calls, 0);
    },
  );
  test('localized Spanish winner uses canonical nutrition identity', () async {
    final food = repository.findByName('Tortilla De Patatas')!;
    final specialist = _Detector([_dish(food.localizedName('es'), 0.8)]);
    final general = _Detector([_dish('Pizza', 0.9)]);
    expect(
      (await hybrid(specialist, general).detectFoods('meal')).single.name,
      food.localizedName('es'),
    );
    expect(general.calls, 0);
  });
  test(
    'non-Spanish winner uses general model without adding either dish',
    () async {
      final specialist = _Detector([_dish('Pizza', 0.99)]);
      final general = _Detector([_dish('Lasagna', 0.4)]);
      final result = await hybrid(specialist, general).detectFoods('meal');
      expect(result, hasLength(1));
      expect(result.single.name, 'Lasagna');
    },
  );
  test(
    'specialist abstention routes to general; general abstention stays empty',
    () async {
      final specialist = _Detector([]);
      final general = _Detector([]);
      expect(await hybrid(specialist, general).detectFoods('meal'), isEmpty);
      expect(general.calls, 1);
    },
  );
  test(
    'inference failures propagate instead of silently replacing the model',
    () async {
      final specialist = _Detector([], error: StateError('broken specialist'));
      final general = _Detector([_dish('Pizza', 0.9)]);
      await expectLater(
        hybrid(specialist, general).detectFoods('meal'),
        throwsStateError,
      );
      expect(general.calls, 0);
      await expectLater(
        hybrid(
          _Detector([]),
          _Detector([], error: StateError('broken general')),
        ).detectFoods('meal'),
        throwsStateError,
      );
    },
  );
}
