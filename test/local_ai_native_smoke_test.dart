import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:calorie_snap/data/repositories/nutrition_repository.dart';
import 'package:calorie_snap/services/food_detection/local_ai_food_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Opt in with CALORIESNAP_NATIVE_SMOKE=1 and CALORIESNAP_TEST_IMAGE set to an
// actual meal photograph. The platform TensorFlow Lite library must be staged
// alongside the test executable exactly as for the desktop application.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final enabled = Platform.environment['CALORIESNAP_NATIVE_SMOKE'] == '1';
  test(
    'native model decodes a photograph and returns one dish with alternatives',
    () async {
      final path = Platform.environment['CALORIESNAP_TEST_IMAGE'];
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);
      final repository = NutritionRepository();
      await repository.load();
      final detector = LocalAiFoodDetectionService(
        nutritionRepository: repository,
      );
      addTearDown(detector.dispose);
      final stopwatch = Stopwatch()..start();
      final result = await detector.detectFoods(path);
      stopwatch.stop();
      // Smoke-test correctness of the Dart/native integration, not accuracy:
      // this photograph is not a held-out benchmark with a verified label.
      expect(result, hasLength(1));
      final dish = result.single;
      expect(dish.confidence, inInclusiveRange(0.03, 1.0));
      expect(dish.kcalPer100g, greaterThan(0));
      expect(dish.suggestedGrams, greaterThan(0));
      expect(dish.alternatives.length, lessThanOrEqualTo(2));
      expect({
        dish.name,
        ...dish.alternatives.map((candidate) => candidate.name),
      }, hasLength(1 + dish.alternatives.length));
      expect(dish.requiresConfirmation, anyOf(isTrue, isFalse));
      // Visible in the test report for desktop latency comparisons.
      debugPrint(
        'Native meal smoke: ${dish.name}; confidence=${dish.confidence}; '
        'alternatives=${dish.alternatives.map((candidate) => candidate.name).join(', ')}; '
        'cold latency=${stopwatch.elapsedMilliseconds} ms',
      );
      final concurrent = await Future.wait([
        detector.detectFoods(path),
        detector.detectFoods(path),
      ]);
      expect(
        concurrent.map((foods) => foods.single.name),
        everyElement(dish.name),
      );
      final invalid = File(
        '${Directory.systemTemp.path}/caloriesnap-invalid-image',
      );
      await invalid.writeAsString('invalid image bytes');
      addTearDown(() async {
        if (await invalid.exists()) await invalid.delete();
      });
      await expectLater(
        detector.detectFoods(invalid.path),
        throwsArgumentError,
      );
      // A worker exception must propagate and leave the queue usable.
      expect((await detector.detectFoods(path)).single.name, dish.name);
    },
    skip: !enabled,
  );
}
