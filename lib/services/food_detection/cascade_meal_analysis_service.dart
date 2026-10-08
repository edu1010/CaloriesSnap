import 'dart:async';

import 'food_detection_service.dart';
import 'meal_analysis_service.dart';
import 'vlm/vlm_meal_analyzer.dart';

/// Runs the fast classifier first and, when a vision-language model is
/// installed, lets it describe the whole plate using the classifier's guesses
/// as hints. Any failure of the large model falls back to the classifier, so
/// the app never does worse than without it.
class CascadeMealAnalysisService implements MealAnalysisService {
  CascadeMealAnalysisService({
    required FoodDetectionService classifier,
    VlmMealAnalyzer? vlm,
    this.vlmTimeout = const Duration(minutes: 3),
  }) : _classifier = classifier,
       _vlm = vlm;

  final FoodDetectionService _classifier;
  final VlmMealAnalyzer? _vlm;
  final Duration vlmTimeout;

  @override
  Future<MealDetection> analyze(
    String imagePath, {
    required String languageCode,
    void Function(MealAnalysisStage stage)? onStage,
  }) async {
    final vlm = _vlm;
    final useVlm = vlm != null && vlm.isAvailable;

    onStage?.call(MealAnalysisStage.classifying);
    List<DetectedFood> classified;
    try {
      classified = await _classifier.detectFoods(imagePath);
    } catch (_) {
      // Without the large model a broken classifier must surface.
      if (!useVlm) rethrow;
      classified = const <DetectedFood>[];
    }
    final candidates =
        classified.isEmpty
            ? const <DetectedFood>[]
            : <DetectedFood>[classified.first, ...classified.first.alternatives];
    final classifierResult = MealDetection(
      foods:
          classified.where((food) => !food.requiresConfirmation).toList(),
      candidates: candidates,
      engine: MealAnalysisEngine.classifier,
    );
    if (!useVlm) return classifierResult;

    try {
      final detection = await vlm
          .analyze(
            imagePath,
            languageCode: languageCode,
            hints: candidates.map((food) => food.name).toList(),
            onStage: onStage,
          )
          .timeout(vlmTimeout);
      if (detection == null) {
        return _fallback(
          classifierResult,
          const FormatException('The vision model returned no usable answer.'),
        );
      }
      if (detection.foods.isEmpty) {
        // "No food here": keep the classifier's guesses selectable, but add
        // nothing on the user's behalf.
        return MealDetection(
          foods: const <DetectedFood>[],
          candidates: candidates,
          engine: MealAnalysisEngine.vlm,
        );
      }
      return detection;
    } on TimeoutException catch (error) {
      vlm.cancel();
      return _fallback(classifierResult, error);
    } catch (error) {
      return _fallback(classifierResult, error);
    }
  }

  static MealDetection _fallback(MealDetection classifier, Object failure) =>
      MealDetection(
        foods: classifier.foods,
        candidates: classifier.candidates,
        engine: MealAnalysisEngine.classifier,
        vlmFailure: failure,
      );
}
