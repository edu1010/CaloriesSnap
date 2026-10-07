import 'dart:convert';
import 'dart:io';

import 'package:calorie_snap/data/repositories/nutrition_repository.dart';
import 'package:calorie_snap/services/food_detection/food_detection_service.dart';
import 'package:calorie_snap/services/food_detection/hybrid_food_detection_service.dart';
import 'package:calorie_snap/services/food_detection/local_ai_food_detection_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingDetector implements FoodDetectionService {
  _RecordingDetector(this.delegate);
  final FoodDetectionService delegate;
  List<DetectedFood> latest = [];
  @override
  Future<List<DetectedFood>> detectFoods(String imagePath) async {
    latest = await delegate.detectFoods(imagePath);
    return latest;
  }
}

// Opt-in integration benchmark using the independently audited held-out sample
// manifest. It evaluates the real Dart decoder, resizing and native runtime.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Dart/native hybrid benchmark on a stratified strict held-out subset',
    () async {
      final manifestPath =
          Platform.environment['CALORIESNAP_BENCHMARK_MANIFEST'] ??
          'training-artifacts/detection-comparison.json';
      final source =
          jsonDecode(await File(manifestPath).readAsString())
              as Map<String, dynamic>;
      final allSamples =
          (source['selected_samples'] as List).cast<Map<String, dynamic>>();
      final counts = <String, int>{};
      final perClass = int.parse(
        Platform.environment['CALORIESNAP_BENCHMARK_PER_CLASS'] ?? '3',
      );
      final samples =
          allSamples.where((sample) {
            final label = sample['label'] as String;
            final count = counts[label] ?? 0;
            if (count >= perClass) return false;
            counts[label] = count + 1;
            return true;
          }).toList();
      expect(counts, hasLength(116));
      expect(counts.values, everyElement(perClass));
      final repository = NutritionRepository();
      await repository.load();
      final specialist = LocalAiFoodDetectionService(
        nutritionRepository: repository,
      );
      final general = LocalAiFoodDetectionService(
        nutritionRepository: repository,
        modelAssetPath: 'assets/models/food101_classifier.tflite',
        labelsAssetPath: 'assets/models/food101_classifier_labels.csv',
      );
      addTearDown(specialist.dispose);
      addTearDown(general.dispose);
      final recording = _RecordingDetector(specialist);
      final hybrid = HybridFoodDetectionService(
        nutritionRepository: repository,
        specialist: recording,
        general: general,
      );
      final rows = <Map<String, dynamic>>[];
      var baselineCorrect = 0;
      var hybridCorrect = 0;
      String? canonical(List<DetectedFood> result) =>
          result.isEmpty
              ? null
              : repository.findByName(result.single.name)?.name;
      for (final sample in samples) {
        final stopwatch = Stopwatch()..start();
        final result = await hybrid.detectFoods(sample['image_path'] as String);
        stopwatch.stop();
        final baseline = canonical(recording.latest);
        final prediction = canonical(result);
        if (baseline == sample['label']) baselineCorrect++;
        if (prediction == sample['label']) hybridCorrect++;
        rows.add({
          ...sample,
          'specialist_prediction': baseline,
          'hybrid_prediction': prediction,
          'latency_ms': stopwatch.elapsedMilliseconds,
          'confidence': result.isEmpty ? null : result.single.confidence,
        });
        if (rows.length % 20 == 0) {
          debugPrint(
            'Native hybrid benchmark ${rows.length}/${samples.length}: '
            'baseline=$baselineCorrect hybrid=$hybridCorrect',
          );
        }
      }
      final output =
          Platform.environment['CALORIESNAP_BENCHMARK_OUTPUT'] ??
          'training-artifacts/dart-native-hybrid-benchmark.json';
      final report = {
        'scope': 'Classification only; no mass/calorie accuracy measured',
        'sample_source': manifestPath,
        'per_class': perClass,
        'count': samples.length,
        'specialist_top1': baselineCorrect / samples.length,
        'hybrid_top1': hybridCorrect / samples.length,
        'predictions': rows,
      };
      await File(
        output,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      debugPrint(
        'Native benchmark saved to $output: specialist '
        '${baselineCorrect / samples.length}, hybrid ${hybridCorrect / samples.length}',
      );
    },
    skip: Platform.environment['CALORIESNAP_NATIVE_BENCHMARK'] != '1',
    timeout: const Timeout(Duration(minutes: 45)),
  );
}
