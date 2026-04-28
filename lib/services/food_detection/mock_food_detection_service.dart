import '../../data/repositories/nutrition_repository.dart';
import '../../models/nutrition_food.dart';
import 'food_detection_service.dart';

class MockFoodDetectionService implements FoodDetectionService {
  MockFoodDetectionService({
    required NutritionRepository nutritionRepository,
  }) : _nutritionRepository = nutritionRepository;

  final NutritionRepository _nutritionRepository;

  @override
  Future<List<DetectedFood>> detectFoods(String imagePath) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final defaults = <String, double>{
      'Rice cooked': 0.93,
      'Chicken breast': 0.89,
      'Salad': 0.86,
    };

    return defaults.entries.map((entry) {
      final NutritionFood? nutrition =
          _nutritionRepository.findByName(entry.key);
      return DetectedFood(
        name: entry.key,
        confidence: entry.value,
        suggestedGrams: nutrition?.defaultGramsMedium ?? 120,
        kcalPer100g: nutrition?.kcalPer100g ?? 100,
      );
    }).toList();
  }
}
