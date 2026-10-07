class DetectedFood {
  const DetectedFood({
    required this.name,
    required this.confidence,
    required this.suggestedGrams,
    required this.kcalPer100g,
    this.alternatives = const <DetectedFood>[],
    this.requiresConfirmation = false,
  });

  final String name;
  final double confidence;
  final double suggestedGrams;
  final double kcalPer100g;

  /// Other possible identities of this dish, never additional meal components.
  final List<DetectedFood> alternatives;
  final bool requiresConfirmation;
}

abstract class FoodDetectionService {
  Future<List<DetectedFood>> detectFoods(String imagePath);
}
