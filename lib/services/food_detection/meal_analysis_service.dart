import 'food_detection_service.dart';

enum MealAnalysisEngine { classifier, vlm }

enum MealAnalysisStage { classifying, loadingModel, analyzing }

/// What a photo analysis proposes to log.
class MealDetection {
  const MealDetection({
    required this.foods,
    required this.engine,
    this.candidates = const <DetectedFood>[],
    this.dishName,
    this.vlmFailure,
  });

  /// Components to add to the meal. May be several for the vision model and
  /// is at most one for the classifier.
  final List<DetectedFood> foods;

  /// Alternative identities of one single dish, of which the user picks one.
  /// Only the classifier produces these.
  final List<DetectedFood> candidates;

  final String? dishName;
  final MealAnalysisEngine engine;

  /// Set when the vision model was available but its result could not be
  /// used, so the classifier answered instead.
  final Object? vlmFailure;
}

abstract class MealAnalysisService {
  Future<MealDetection> analyze(
    String imagePath, {
    required String languageCode,
    void Function(MealAnalysisStage stage)? onStage,
  });
}
