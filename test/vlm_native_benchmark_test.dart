import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:calorie_snap/data/repositories/nutrition_repository.dart';
import 'package:calorie_snap/services/food_detection/food_detection_service.dart';
import 'package:calorie_snap/services/food_detection/hybrid_food_detection_service.dart';
import 'package:calorie_snap/services/food_detection/local_ai_food_detection_service.dart';
import 'package:calorie_snap/services/food_detection/meal_analysis_service.dart';
import 'package:calorie_snap/services/food_detection/vlm/meal_analysis.dart';
import 'package:calorie_snap/services/food_detection/vlm/nutrition_grounding.dart';
import 'package:calorie_snap/services/food_detection/vlm/vlm_engine.dart';
import 'package:calorie_snap/services/food_detection/vlm/vlm_meal_analyzer.dart';
import 'package:calorie_snap/services/food_detection/vlm/vlm_model_catalog.dart';
import 'package:calorie_snap/services/food_detection/vlm/vlm_model_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// Opt-in benchmark of the real on-device pipeline: the production Dart code,
// llama.cpp runtime, prompt, parser and nutrition grounding.
//
//   CALORIESNAP_VLM_BENCHMARK=1        enable
//   CALORIESNAP_VLM_MODEL=light|precise
//   CALORIESNAP_VLM_MODELS_DIR         where models are downloaded/kept
//   CALORIESNAP_VLM_PER_CLASS=1        images per classifier class (0 = skip)
//   CALORIESNAP_VLM_DISHES=60          Nutrition5k dishes (0 = skip)
//   CALORIESNAP_VLM_HINTS=1            pass classifier guesses to the model
//
// Part 1 measures dish identification on the audited held-out sample. The
// model answers in free text, so a hit is a lenient name match; it is not
// comparable digit for digit with classifier top-1.
// Part 2 measures calories and grams against Nutrition5k's weighed dishes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final env = Platform.environment;

  test(
    'on-device vision model: dish identification and calorie error',
    () async {
      final spec =
          env['CALORIESNAP_VLM_MODEL'] == 'precise'
              ? VlmModelCatalog.precise
              : VlmModelCatalog.light;
      final perClass = int.parse(env['CALORIESNAP_VLM_PER_CLASS'] ?? '1');
      final dishCount = int.parse(env['CALORIESNAP_VLM_DISHES'] ?? '60');
      final useHints = env['CALORIESNAP_VLM_HINTS'] != '0';

      final repository = NutritionRepository();
      await repository.load();
      final grounding = NutritionGrounding(repository);

      final store = VlmModelStore(
        rootDirectory:
            () async => Directory(
              env['CALORIESNAP_VLM_MODELS_DIR'] ??
                  'training-artifacts/vlm-models',
            ),
      );
      await store.init();
      if (!store.isInstalled(spec)) {
        debugPrint('Downloading ${spec.name} (${spec.totalBytes} bytes)...');
        var lastPercent = -10;
        store.addListener(() {
          final percent = ((store.progress?.fraction ?? 0) * 100).floor();
          if (percent >= lastPercent + 10) {
            lastPercent = percent;
            debugPrint('  $percent %');
          }
        });
        await store.download(spec);
      }
      await store.select(spec);

      final analyzer = VlmMealAnalyzer(
        engine: LlamadartVlmEngine(),
        store: store,
        nutritionRepository: repository,
        idleUnload: const Duration(hours: 1),
      );
      addTearDown(analyzer.dispose);

      // The classifier needs the TensorFlow Lite library staged next to the
      // test executable; without it the model runs unaided.
      FoodDetectionService? classifier = HybridFoodDetectionService(
        nutritionRepository: repository,
        specialist: LocalAiFoodDetectionService(
          nutritionRepository: repository,
        ),
        general: LocalAiFoodDetectionService(
          nutritionRepository: repository,
          modelAssetPath: 'assets/models/food101_general.tflite',
          labelsAssetPath: 'assets/models/food101_general_labels.csv',
        ),
      );

      Future<List<DetectedFood>> classify(String path) async {
        if (classifier == null) return const <DetectedFood>[];
        try {
          return await classifier!.detectFoods(path);
        } catch (error) {
          debugPrint('Classifier unavailable, continuing without it: $error');
          classifier = null;
          return const <DetectedFood>[];
        }
      }

      Future<_Run> run(String path) async {
        final classified = await classify(path);
        final hints =
            !useHints || classified.isEmpty
                ? const <String>[]
                : <String>[
                  classified.first.name,
                  ...classified.first.alternatives.map((food) => food.name),
                ];
        final stopwatch = Stopwatch()..start();
        MealDetection? detection;
        Object? error;
        try {
          detection = await analyzer.analyze(
            path,
            languageCode: 'es',
            hints: hints,
          );
        } catch (caught) {
          error = caught;
        }
        stopwatch.stop();
        return _Run(classified, detection, stopwatch.elapsedMilliseconds, error);
      }

      String? canonical(String name, String language) =>
          grounding
              .ground(AnalyzedItem(name: name), languageCode: language)
              .match
              ?.name;

      final report = <String, dynamic>{
        'model': spec.id,
        'hints': useHints,
        'image_max_edge': spec.imageMaxEdge,
      };

      // ---- Part 1: dish identification -------------------------------
      if (perClass > 0) {
        final manifest =
            jsonDecode(
                  await File(
                    env['CALORIESNAP_BENCHMARK_MANIFEST'] ??
                        'training-artifacts/detection-comparison.json',
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        final counts = <String, int>{};
        final samples =
            (manifest['selected_samples'] as List)
                .cast<Map<String, dynamic>>()
                .where((sample) {
                  final label = sample['label'] as String;
                  final count = counts[label] ?? 0;
                  if (count >= perClass) return false;
                  counts[label] = count + 1;
                  return true;
                })
                .toList();

        var vlmHits = 0;
        var classifierHits = 0;
        var unusable = 0;
        final latencies = <int>[];
        final rows = <Map<String, dynamic>>[];
        for (final sample in samples) {
          final label = sample['label'] as String;
          final truth = repository.findByName(label)!;
          final result = await run(sample['image_path'] as String);
          final detection = result.detection;
          final names = <String>[
            if (detection?.dishName != null) detection!.dishName!,
            ...?detection?.foods.map((food) => food.name),
          ];
          final hit = names.any(
            (name) =>
                canonical(name, 'es') == truth.name ||
                canonical(name, 'en') == truth.name,
          );
          final classifierName =
              result.classified.isEmpty
                  ? null
                  : repository.findByName(result.classified.first.name)?.name;
          if (hit) vlmHits++;
          if (classifierName == truth.name) classifierHits++;
          if (detection == null || detection.foods.isEmpty) unusable++;
          latencies.add(result.latencyMs);
          rows.add(<String, dynamic>{
            'label': label,
            'image_path': sample['image_path'],
            'classifier': classifierName,
            'vlm_dish': detection?.dishName,
            'vlm_items': names,
            'vlm_hit': hit,
            'latency_ms': result.latencyMs,
            if (result.error != null) 'error': result.error.toString(),
          });
          if (rows.length % 10 == 0) {
            debugPrint(
              'identification ${rows.length}/${samples.length}: '
              'vlm=$vlmHits classifier=$classifierHits unusable=$unusable',
            );
          }
        }
        report['identification'] = <String, dynamic>{
          'scope':
              'Lenient free-text name match for the vision model; exact '
              'top-1 for the classifier. Not directly comparable.',
          'count': samples.length,
          'vlm_lenient_hit_rate': vlmHits / samples.length,
          'classifier_top1': classifierHits / samples.length,
          'vlm_unusable_answers': unusable,
          'latency_ms_median': _median(latencies),
          'rows': rows,
        };
      }

      // ---- Part 2: calories against weighed dishes -------------------
      if (dishCount > 0) {
        final dishes = await _nutrition5kDishes(
          env['CALORIESNAP_NUTRITION5K'] ?? 'datasets/nutrition5k_dataset',
        );
        dishes.shuffle(Random(20261007));
        final selected = dishes.take(dishCount).toList();

        final vlmKcalErrors = <double>[];
        final vlmKcalRelative = <double>[];
        final vlmGramErrors = <double>[];
        final classifierKcalErrors = <double>[];
        final classifierKcalRelative = <double>[];
        final latencies = <int>[];
        var unusable = 0;
        final rows = <Map<String, dynamic>>[];
        for (final dish in selected) {
          final result = await run(dish.imagePath);
          latencies.add(result.latencyMs);

          double? classifierKcal;
          if (result.classified.isNotEmpty) {
            final top = result.classified.first;
            classifierKcal = top.suggestedGrams * top.kcalPer100g / 100;
            classifierKcalErrors.add((classifierKcal - dish.kcal).abs());
            classifierKcalRelative.add(
              (classifierKcal - dish.kcal).abs() / dish.kcal,
            );
          }

          final foods = result.detection?.foods ?? const <DetectedFood>[];
          double? vlmKcal;
          double? vlmGrams;
          if (foods.isEmpty) {
            unusable++;
          } else {
            vlmKcal = foods.fold<double>(
              0,
              (sum, food) => sum + food.suggestedGrams * food.kcalPer100g / 100,
            );
            vlmGrams = foods.fold<double>(
              0,
              (sum, food) => sum + food.suggestedGrams,
            );
            vlmKcalErrors.add((vlmKcal - dish.kcal).abs());
            vlmKcalRelative.add((vlmKcal - dish.kcal).abs() / dish.kcal);
            vlmGramErrors.add((vlmGrams - dish.grams).abs());
          }
          rows.add(<String, dynamic>{
            'dish_id': dish.id,
            'true_kcal': dish.kcal,
            'true_grams': dish.grams,
            'true_ingredients': dish.ingredients,
            'vlm_kcal': vlmKcal,
            'vlm_grams': vlmGrams,
            'vlm_dish': result.detection?.dishName,
            'vlm_items': <Map<String, dynamic>>[
              for (final food in foods)
                <String, dynamic>{
                  'name': food.name,
                  'grams': food.suggestedGrams,
                  'kcal100': food.kcalPer100g,
                  'from_table': !food.estimatedNutrition,
                },
            ],
            'classifier_kcal': classifierKcal,
            'latency_ms': result.latencyMs,
            if (result.error != null) 'error': result.error.toString(),
          });
          if (rows.length % 10 == 0) {
            debugPrint(
              'calories ${rows.length}/${selected.length}: '
              'vlm median abs error ${_median(vlmKcalErrors)} kcal',
            );
          }
        }
        report['calories'] = <String, dynamic>{
          'scope':
              'Nutrition5k overhead photos of weighed cafeteria dishes. '
              'Classifier baseline = top-1 dish at its default medium portion.',
          'count': selected.length,
          'true_kcal_median': _median(selected.map((dish) => dish.kcal)),
          'vlm_unusable_answers': unusable,
          'vlm_kcal_abs_error_median': _median(vlmKcalErrors),
          'vlm_kcal_abs_error_mean': _mean(vlmKcalErrors),
          'vlm_kcal_relative_error_median': _median(vlmKcalRelative),
          'vlm_grams_abs_error_median': _median(vlmGramErrors),
          'classifier_kcal_abs_error_median': _median(classifierKcalErrors),
          'classifier_kcal_abs_error_mean': _mean(classifierKcalErrors),
          'classifier_kcal_relative_error_median': _median(
            classifierKcalRelative,
          ),
          'latency_ms_median': _median(latencies),
          'rows': rows,
        };
      }

      final output =
          env['CALORIESNAP_VLM_OUTPUT'] ??
          'training-artifacts/vlm-benchmark-${spec.id}.json';
      await File(
        output,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      final summary = <String, dynamic>{
        for (final entry in report.entries)
          entry.key:
              entry.value is Map
                  ? (Map<String, dynamic>.of(entry.value as Map<String, dynamic>)
                    ..remove('rows'))
                  : entry.value,
      };
      debugPrint('Saved $output');
      debugPrint(const JsonEncoder.withIndent('  ').convert(summary));
    },
    skip: env['CALORIESNAP_VLM_BENCHMARK'] != '1',
    timeout: const Timeout(Duration(hours: 4)),
  );
}

class _Run {
  const _Run(this.classified, this.detection, this.latencyMs, this.error);
  final List<DetectedFood> classified;
  final MealDetection? detection;
  final int latencyMs;
  final Object? error;
}

class _Dish {
  const _Dish(this.id, this.imagePath, this.kcal, this.grams, this.ingredients);
  final String id;
  final String imagePath;
  final double kcal;
  final double grams;
  final List<String> ingredients;
}

/// Dishes with an overhead photo and plausible weighed totals.
Future<List<_Dish>> _nutrition5kDishes(String root) async {
  final dishes = <_Dish>[];
  for (final cafe in const <String>['cafe1', 'cafe2']) {
    final file = File('$root/metadata/dish_metadata_$cafe.csv');
    if (!await file.exists()) continue;
    for (final line in await file.readAsLines()) {
      // dish_id, kcal, grams, fat, carb, protein, then 7 fields per ingredient
      // of which the second is its name.
      final fields = line.split(',');
      if (fields.length < 6) continue;
      final kcal = double.tryParse(fields[1]);
      final grams = double.tryParse(fields[2]);
      if (kcal == null || grams == null || kcal < 50 || grams < 50) continue;
      final image = File(
        '$root/imagery/realsense_overhead/${fields[0]}/rgb.png',
      );
      if (!await image.exists()) continue;
      dishes.add(
        _Dish(fields[0], image.path, kcal, grams, <String>[
          for (var i = 7; i < fields.length; i += 7) fields[i],
        ]),
      );
    }
  }
  dishes.sort((a, b) => a.id.compareTo(b.id));
  return dishes;
}

double? _median(Iterable<num> values) {
  final sorted = values.map((value) => value.toDouble()).toList()..sort();
  if (sorted.isEmpty) return null;
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

double? _mean(Iterable<num> values) =>
    values.isEmpty
        ? null
        : values.fold<double>(0, (sum, value) => sum + value) / values.length;
