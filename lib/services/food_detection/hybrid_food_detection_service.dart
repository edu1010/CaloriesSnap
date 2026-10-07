import '../../data/repositories/nutrition_repository.dart';
import 'food_detection_service.dart';

/// Routes the specialist's 15 Spanish classes to their existing model and
/// uses the independently evaluated Food-101 model for the remaining dishes.
/// Scores from the two models are never compared or combined.
class HybridFoodDetectionService implements FoodDetectionService {
  HybridFoodDetectionService({
    required NutritionRepository nutritionRepository,
    required FoodDetectionService specialist,
    required FoodDetectionService general,
    Set<String> specialistClasses = spanishClasses,
  }) : _nutritionRepository = nutritionRepository,
       _specialist = specialist,
       _general = general,
       _specialistClasses = Set<String>.unmodifiable(specialistClasses);

  static const Set<String> spanishClasses = {
    'Tortilla De Patatas',
    'Croquetas',
    'Gazpacho',
    'Salmorejo',
    'Patatas Bravas',
    'Pulpo A La Gallega',
    'Jamon Serrano',
    'Fabada Asturiana',
    'Pimientos De Padron',
    'Gambas Al Ajillo',
    'Empanada Gallega',
    'Ensaladilla Rusa',
    'Tarta De Santiago',
    'Bocadillo De Calamares',
    'Albondigas',
  };

  final NutritionRepository _nutritionRepository;
  final FoodDetectionService _specialist;
  final FoodDetectionService _general;
  final Set<String> _specialistClasses;

  @override
  Future<List<DetectedFood>> detectFoods(String imagePath) async {
    final specialist = await _specialist.detectFoods(imagePath);
    if (specialist.isNotEmpty) {
      final canonical =
          _nutritionRepository.findByName(specialist.first.name)?.name;
      if (_specialistClasses.contains(canonical)) {
        return <DetectedFood>[specialist.first];
      }
    }
    // Empty results mean abstention. Inference errors propagate to the caller;
    // silently substituting the other model would conceal a broken install.
    final general = await _general.detectFoods(imagePath);
    return general.isEmpty
        ? const <DetectedFood>[]
        : <DetectedFood>[general.first];
  }
}
