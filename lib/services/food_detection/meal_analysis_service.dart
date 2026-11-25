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
  /// [description] is the user's optional text about the dish ("arroz frito
  /// con pollo"); the vision model takes it as strong evidence.
  Future<MealDetection> analyze(
    String imagePath, {
    required String languageCode,
    String? description,
    void Function(MealAnalysisStage stage)? onStage,
  });
}

/// Optional support for publishing the fast result before advanced analysis.
abstract class ProgressiveMealAnalysisService implements MealAnalysisService {
  Future<MealDetection> analyzeProgressively(
    String imagePath, {
    required String languageCode,
    String? description,
    void Function(MealAnalysisStage stage)? onStage,
    required void Function(MealDetection result) onClassifierResult,
    required MealAnalysisCancellation cancellation,
  });
}

/// Cancels one request, including one that is still waiting for the model.
class MealAnalysisCancellation {
  bool _isCanceled = false;
  void Function()? _stopGeneration;

  bool get isCanceled => _isCanceled;

  void cancel() {
    if (_isCanceled) return;
    _isCanceled = true;
    _stopGeneration?.call();
    _stopGeneration = null;
  }

  /// Set only while this request owns the native generation context.
  void setStopGeneration(void Function()? stopGeneration) {
    _stopGeneration = stopGeneration;
  }
}
