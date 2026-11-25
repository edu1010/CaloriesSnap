import 'dart:convert';
import 'dart:io';

import 'package:calorie_snap/data/repositories/nutrition_repository.dart';
import 'package:calorie_snap/services/food_detection/food_detection_service.dart';
import 'package:calorie_snap/services/food_detection/hybrid_food_detection_service.dart';
import 'package:calorie_snap/services/food_detection/local_ai_food_detection_service.dart';
import 'package:calorie_snap/services/food_detection/meal_analysis_service.dart';
import 'package:calorie_snap/services/food_detection/vlm/vlm_engine.dart';
import 'package:calorie_snap/services/food_detection/vlm/vlm_meal_analyzer.dart';
import 'package:calorie_snap/services/food_detection/vlm/vlm_model_store.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../test/support/vlm_benchmark_models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier<String>('Starting benchmark…');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ValueListenableBuilder<String>(
                valueListenable: status,
                builder: (context, message, _) => Text(message),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => _run(status));
}

Future<void> _run(ValueNotifier<String> status) async {
  final rows = <Map<String, Object?>>[];
  final report = <String, Object?>{
    'status': 'running',
    'phase': 'reading_request',
    'backend': 'cpu',
    'cases': rows,
  };
  Directory? root;
  VlmModelStore? store;
  VlmMealAnalyzer? analyzer;

  Future<void> checkpoint() async {
    report['process_peak_rss_bytes'] = ProcessInfo.maxRss;
    final directory = root!;
    final temporary = File(path.join(directory.path, 'result.json.tmp'));
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    await temporary.rename(path.join(directory.path, 'result.json'));
  }

  try {
    final support = await getApplicationSupportDirectory();
    final directory =
        root = Directory(path.join(support.path, 'vlm_benchmark'));
    await directory.create(recursive: true);
    await checkpoint();
    final request =
        jsonDecode(
              await File(
                path.join(directory.path, 'request.json'),
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final model = request['model'] as String;
    final spec = benchmarkModels[model];
    if (spec == null) throw FormatException('Unknown benchmark model $model.');
    final cases = (request['cases'] as List).cast<Map<String, dynamic>>();
    if (cases.isEmpty) {
      throw const FormatException('At least one case is required.');
    }
    final useHints = request['hints'] != false;
    final thinking = request['thinking'] == true;
    report.addAll({
      'model': model,
      'model_id': spec.id,
      'model_name': spec.name,
      'hints': useHints,
      'thinking': thinking,
      'phase': 'loading_model',
    });
    status.value = 'Loading ${spec.name} on CPU…';
    await checkpoint();

    final nutrition = NutritionRepository();
    await nutrition.load();
    final modelStore =
        store = VlmModelStore(
          catalog: benchmarkModels.values.toList(),
          rootDirectory:
              () async => Directory(path.join(directory.path, 'models')),
        );
    await modelStore.init();
    final files = await modelStore.filesOf(spec);
    if (files == null) {
      throw StateError(
        '${spec.name} is missing its installed marker or expected model files.',
      );
    }
    await modelStore.select(spec);
    final engine = LlamadartVlmEngine(useGpu: false, enableThinking: thinking);
    final mealAnalyzer =
        analyzer = VlmMealAnalyzer(
          engine: engine,
          store: modelStore,
          nutritionRepository: nutrition,
          idleUnload: const Duration(hours: 1),
        );
    report['rss_before_analysis_bytes'] = ProcessInfo.currentRss;
    final load = Stopwatch()..start();
    try {
      await engine.load(files);
    } finally {
      report['model_load_ms'] = load.elapsedMilliseconds;
    }
    report['rss_after_model_load_bytes'] = ProcessInfo.currentRss;
    report['phase'] = 'analyzing_cases';

    FoodDetectionService? classifier = HybridFoodDetectionService(
      nutritionRepository: nutrition,
      specialist: LocalAiFoodDetectionService(nutritionRepository: nutrition),
      general: LocalAiFoodDetectionService(
        nutritionRepository: nutrition,
        modelAssetPath: 'assets/models/food101_general.tflite',
        labelsAssetPath: 'assets/models/food101_general_labels.csv',
      ),
    );
    for (final scenario in cases) {
      final id = scenario['id'];
      status.value = '${spec.name} · ${rows.length + 1}/${cases.length}';
      report['current_case'] = id;
      await checkpoint();
      final row = <String, Object?>{'id': id};
      final total = Stopwatch()..start();
      try {
        final relativePath = scenario['path'] as String;
        final imagePath = path.normalize(
          path.join(directory.path, relativePath),
        );
        if (path.isAbsolute(relativePath) ||
            !path.isWithin(directory.path, imagePath)) {
          throw FormatException(
            'Case $id must use an image inside vlm_benchmark.',
          );
        }
        final trueKcal = (scenario['kcal'] as num).toDouble();
        final trueGrams = (scenario['grams'] as num).toDouble();
        final description = scenario['description'] as String?;
        row.addAll({
          'true_kcal': trueKcal,
          'true_grams': trueGrams,
          'has_description': description?.isNotEmpty == true,
        });

        final classifierTime = Stopwatch()..start();
        List<DetectedFood> classified = const [];
        if (classifier != null) {
          try {
            classified = await classifier.detectFoods(imagePath);
          } catch (error) {
            report['classifier_error'] = error.toString();
            classifier = null;
          }
        }
        row['classifier_ms'] = classifierTime.elapsedMilliseconds;
        final hints =
            !useHints || classified.isEmpty
                ? const <String>[]
                : [
                  classified.first.name,
                  ...classified.first.alternatives.map((food) => food.name),
                ];
        row['hints'] = hints;
        final inference = Stopwatch()..start();
        final cancellation = MealAnalysisCancellation();
        MealDetection? detection;
        try {
          detection = await mealAnalyzer
              .analyze(
                imagePath,
                languageCode: 'es',
                hints: hints,
                description: description,
                cancellation: cancellation,
              )
              .timeout(const Duration(minutes: 3));
        } catch (_) {
          cancellation.cancel();
          rethrow;
        } finally {
          row['vlm_ms'] = inference.elapsedMilliseconds;
        }
        if (detection == null) {
          throw const FormatException('No usable model response.');
        }
        final foods = detection.foods;
        final kcal = foods.fold<double>(
          0,
          (sum, food) => sum + food.suggestedGrams * food.kcalPer100g / 100,
        );
        final grams = foods.fold<double>(
          0,
          (sum, food) => sum + food.suggestedGrams,
        );
        row.addAll({
          'status': foods.isEmpty ? 'no_food' : 'ok',
          'dish': detection.dishName,
          'vlm_kcal': kcal,
          'vlm_grams': grams,
          'kcal_abs_error': (kcal - trueKcal).abs(),
          'grams_abs_error': (grams - trueGrams).abs(),
          'foods': [
            for (final food in foods)
              {
                'name': food.name,
                'grams': food.suggestedGrams,
                'kcal100': food.kcalPer100g,
              },
          ],
        });
      } catch (error) {
        row['status'] = 'error';
        row['error'] = error.toString();
      }
      row['total_ms'] = total.elapsedMilliseconds;
      row['process_rss_bytes'] = ProcessInfo.currentRss;
      rows.add(row);
      await checkpoint();
    }
    report.remove('current_case');
    report.addAll({
      'status': 'completed',
      'phase': 'finished',
      'vlm_ms_median': _median(rows, 'vlm_ms'),
      'kcal_abs_error_median': _median(rows, 'kcal_abs_error'),
      'grams_abs_error_median': _median(rows, 'grams_abs_error'),
    });
  } catch (error, stack) {
    report['status'] = 'error';
    report['error'] = error.toString();
    debugPrintStack(label: error.toString(), stackTrace: stack);
  } finally {
    if (root != null) {
      try {
        await checkpoint();
      } catch (error) {
        report['status'] = 'error';
        report['error'] = 'Could not write result.json: $error';
      }
    }
    status.value =
        report['status'] == 'completed'
            ? 'Benchmark completed · ${rows.length} cases'
            : 'Benchmark failed\n${report['error']}';
    await analyzer?.dispose();
    store?.dispose();
  }
}

double? _median(List<Map<String, Object?>> rows, String key) {
  final values = rows.map((row) => row[key]).whereType<num>().toList()..sort();
  if (values.isEmpty) return null;
  final middle = values.length ~/ 2;
  return values.length.isOdd
      ? values[middle].toDouble()
      : (values[middle - 1] + values[middle]) / 2;
}
