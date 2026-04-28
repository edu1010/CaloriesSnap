class DetectedFood {
  const DetectedFood({
    required this.name,
    required this.confidence,
    required this.suggestedGrams,
    required this.kcalPer100g,
  });

  final String name;
  final double confidence;
  final double suggestedGrams;
  final double kcalPer100g;
}

abstract class FoodDetectionService {
  Future<List<DetectedFood>> detectFoods(String imagePath);
}
