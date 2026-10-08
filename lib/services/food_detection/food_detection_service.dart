class DetectedFood {
  const DetectedFood({
    required this.name,
    required this.confidence,
    required this.suggestedGrams,
    required this.kcalPer100g,
    this.alternatives = const <DetectedFood>[],
    this.requiresConfirmation = false,
    this.estimatedNutrition = false,
  });

  final String name;
  final double confidence;
  final double suggestedGrams;
  final double kcalPer100g;

  /// Other possible identities of this dish, never additional meal components.
  final List<DetectedFood> alternatives;
  final bool requiresConfirmation;

  /// True when [kcalPer100g] is the vision model's own guess because the food
  /// was not found in the local nutrition table.
  final bool estimatedNutrition;
}

abstract class FoodDetectionService {
  Future<List<DetectedFood>> detectFoods(String imagePath);
}
