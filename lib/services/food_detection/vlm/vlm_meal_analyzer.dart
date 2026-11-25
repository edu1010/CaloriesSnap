import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../data/repositories/nutrition_repository.dart';
import '../food_detection_service.dart';
import '../meal_analysis_service.dart';
import 'meal_analysis.dart';
import 'meal_analysis_prompt.dart';
import 'nutrition_grounding.dart';
import 'vlm_engine.dart';
import 'vlm_model_store.dart';

/// Describes a meal photo with the on-device vision-language model and turns
/// the answer into foods with table-backed energy values.
class VlmMealAnalyzer {
  VlmMealAnalyzer({
    required VlmEngine engine,
    required VlmModelStore store,
    required NutritionRepository nutritionRepository,
    this.idleUnload = const Duration(minutes: 3),
  }) : _engine = engine,
       _store = store,
       _grounding = NutritionGrounding(nutritionRepository) {
    _store.addListener(_onStoreChanged);
  }

  final VlmEngine _engine;
  final VlmModelStore _store;
  final NutritionGrounding _grounding;

  /// The model holds 1-2 GB; it is released after this long without use.
  final Duration idleUnload;

  Future<void> _queue = Future<void>.value();
  Timer? _idleTimer;
  String? _loadedId;

  bool get isAvailable => _store.activeModel != null;

  /// Returns null when the model's answer is unusable. A result with no
  /// foods means the model saw no food in the photo.
  Future<MealDetection?> analyze(
    String imagePath, {
    required String languageCode,
    List<String> hints = const <String>[],
    String? description,
    void Function(MealAnalysisStage stage)? onStage,
    MealAnalysisCancellation? cancellation,
  }) {
    // The native context serves one request at a time.
    final result = _queue.then(
      (_) => _analyze(
        imagePath,
        languageCode,
        hints,
        description,
        onStage,
        cancellation,
      ),
    );
    _queue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<void> dispose() async {
    _store.removeListener(_onStoreChanged);
    _idleTimer?.cancel();
    await _queue;
    _idleTimer?.cancel();
    await _unload();
  }

  Future<MealDetection?> _analyze(
    String imagePath,
    String languageCode,
    List<String> hints,
    String? description,
    void Function(MealAnalysisStage stage)? onStage,
    MealAnalysisCancellation? cancellation,
  ) async {
    if (cancellation?.isCanceled == true) return null;
    final spec = _store.activeModel;
    final files = spec == null ? null : await _store.filesOf(spec);
    if (cancellation?.isCanceled == true) return null;
    if (spec == null || files == null) {
      throw StateError('No vision model is installed.');
    }

    _idleTimer?.cancel();
    File? resized;
    try {
      if (_loadedId != spec.id) {
        onStage?.call(MealAnalysisStage.loadingModel);
        await _engine.load(files);
        _loadedId = spec.id;
      }
      if (cancellation?.isCanceled == true) return null;
      onStage?.call(MealAnalysisStage.analyzing);
      resized = await _resizeInBackground(imagePath, spec.imageMaxEdge);
      if (cancellation?.isCanceled == true) return null;
      cancellation?.setStopGeneration(_engine.cancel);
      final answer = await _engine.describeImage(
        imagePath: resized.path,
        system: MealAnalysisPrompt.system,
        prompt: MealAnalysisPrompt.user(
          languageCode: languageCode,
          hints: hints,
          description: description,
        ),
        maxTokens: MealAnalysisPrompt.maxOutputTokens,
        responseFormat: MealAnalysisPrompt.responseFormat,
      );
      final analysis = MealAnalysis.tryParse(answer);
      return analysis == null ? null : _toDetection(analysis, languageCode);
    } finally {
      cancellation?.setStopGeneration(null);
      try {
        await resized?.delete();
      } on FileSystemException {
        // A leftover temp file is harmless.
      }
      _idleTimer = Timer(idleUnload, () {
        _queue = _queue.then((_) => _unload());
      });
    }
  }

  MealDetection _toDetection(MealAnalysis analysis, String languageCode) {
    final single = analysis.items.length == 1;
    final foods = <DetectedFood>[
      for (final item in analysis.items)
        _toFood(
          _grounding.ground(
            item,
            languageCode: languageCode,
            // A lone item is the dish itself, so its name may identify it.
            dishName: single ? analysis.dish : null,
          ),
        ),
    ];
    return MealDetection(
      foods: foods,
      dishName: analysis.dish,
      engine: MealAnalysisEngine.vlm,
    );
  }

  static DetectedFood _toFood(GroundedItem item) => DetectedFood(
    name: item.name,
    // The model reports no calibrated score.
    confidence: 0,
    suggestedGrams: item.grams,
    kcalPer100g: item.kcalPer100g,
    estimatedNutrition: !item.fromDatabase,
  );

  void _onStoreChanged() {
    // Switching or deleting the model must not keep the old one in memory.
    if (_loadedId != null && _store.activeModel?.id != _loadedId) {
      _queue = _queue.then((_) => _unload());
    }
  }

  Future<void> _unload() async {
    _idleTimer?.cancel();
    if (_loadedId == null) return;
    _loadedId = null;
    await _engine.unload();
  }
}

// A separate function so the isolate closure captures only sendable values.
Future<File> _resizeInBackground(String imagePath, int maxEdge) =>
    Isolate.run(() => _writeResizedCopy(imagePath, maxEdge));

/// Writes an upright JPEG copy whose longest edge is at most [maxEdge].
Future<File> _writeResizedCopy(String imagePath, int maxEdge) async {
  final decoded = img.decodeImage(await File(imagePath).readAsBytes());
  if (decoded == null) {
    throw ArgumentError('Could not decode image at path: $imagePath');
  }
  var image = img.bakeOrientation(decoded);
  if (image.width > maxEdge || image.height > maxEdge) {
    image =
        image.width >= image.height
            ? img.copyResize(
              image,
              width: maxEdge,
              interpolation: img.Interpolation.average,
            )
            : img.copyResize(
              image,
              height: maxEdge,
              interpolation: img.Interpolation.average,
            );
  }
  final target = File(
    p.join(
      Directory.systemTemp.path,
      'caloriesnap_vlm_${DateTime.now().microsecondsSinceEpoch}.jpg',
    ),
  );
  await target.writeAsBytes(img.encodeJpg(image, quality: 90));
  return target;
}
