import 'dart:io';

import 'package:calorie_snap/services/food_detection/vlm/meal_analysis_prompt.dart';
import 'package:calorie_snap/services/food_detection/vlm/vlm_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probe', () async {
    final model = Platform.environment['PROBE_MODEL'] ?? 'qwen3.5-0.8b-q4';
    final dir = Directory('training-artifacts/vlm-models/$model').absolute.path;
    final gguf = Directory(dir)
        .listSync()
        .map((e) => e.path)
        .firstWhere((p) => p.endsWith('.gguf') && !p.contains('mmproj'));
    final engine = LlamadartVlmEngine();
    await engine.load(
      VlmModelFiles(modelPath: gguf, projectorPath: '$dir\\mmproj-F16.gguf'),
    );
    for (final image in Platform.environment['PROBE_IMAGES']!.split(';')) {
      for (final schema in [true, false]) {
        final sw = Stopwatch()..start();
        final out = await engine.describeImage(
          imagePath: image,
          system: MealAnalysisPrompt.system,
          prompt: MealAnalysisPrompt.user(languageCode: 'es'),
          maxTokens: 320,
          responseFormat: schema ? MealAnalysisPrompt.responseFormat : null,
        );
        print('PROBE schema=$schema ${sw.elapsedMilliseconds}ms ${image.split('\\').last}: $out');
      }
    }
    await engine.unload();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
