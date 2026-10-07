import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../data/repositories/nutrition_repository.dart';
import '../../models/nutrition_food.dart';
import 'food_detection_service.dart';
import 'classifier_postprocessing.dart';
import 'classifier_image_preprocessing.dart';

class LocalAiFoodDetectionService implements FoodDetectionService {
  LocalAiFoodDetectionService({
    required NutritionRepository nutritionRepository,
    String modelAssetPath = 'assets/models/food_classifier.tflite',
    String labelsAssetPath = 'assets/models/food_classifier_labels.csv',
  }) : _nutritionRepository = nutritionRepository,
       _modelAssetPath = modelAssetPath,
       _labelsAssetPath = labelsAssetPath;

  static const int _maxDetectedFoods = 1;
  static const double _minConfidence = 0.03;
  final NutritionRepository _nutritionRepository;
  final String _modelAssetPath;
  final String _labelsAssetPath;

  Interpreter? _interpreter;
  List<String>? _labels;
  Future<void>? _initializationFuture;
  Future<void> _pendingDetection = Future<void>.value();

  @override
  Future<List<DetectedFood>> detectFoods(String imagePath) {
    // A native interpreter may only be invoked by one worker at a time.
    final result = _pendingDetection.then((_) => _detectFoods(imagePath));
    _pendingDetection = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<List<DetectedFood>> _detectFoods(String imagePath) async {
    await _ensureInitialized();

    final interpreter = _interpreter;
    final labels = _labels;
    if (interpreter == null || labels == null || labels.isEmpty) {
      throw StateError('Local food detection model is not initialized.');
    }

    final address = interpreter.address;
    final probabilities = await Isolate.run(
      () => _runNativeClassification(imagePath, address),
    );
    final mappedScores = _mapPredictionsToSupportedFoods(
      probabilities: probabilities,
      labels: labels,
    );

    if (mappedScores.isEmpty) {
      return const <DetectedFood>[];
    }

    final ranked =
        mappedScores.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    final languageCode = ui.PlatformDispatcher.instance.locale.languageCode;
    final candidateIndices = List<int>.generate(probabilities.length, (i) => i)
      ..sort((a, b) => probabilities[b].compareTo(probabilities[a]));
    final margin =
        candidateIndices.length < 2
            ? 1.0
            : probabilities[candidateIndices[0]] -
                probabilities[candidateIndices[1]];
    final alternatives = <DetectedFood>[];
    final seenNames = mappedScores.keys.toSet();
    for (final index in candidateIndices.take(5)) {
      final name = _mapLabelToSupportedFood(labels[index]);
      if (name == null || !seenNames.add(name)) continue;
      final nutrition = _nutritionRepository.findByName(name);
      if (nutrition == null) continue;
      alternatives.add(
        DetectedFood(
          name: nutrition.localizedName(languageCode),
          confidence: probabilities[index],
          suggestedGrams: nutrition.defaultGramsMedium,
          kcalPer100g: nutrition.kcalPer100g,
        ),
      );
      if (alternatives.length == 2) break;
    }
    final detectedFoods = <DetectedFood>[];
    for (final entry in ranked) {
      if (entry.value < _minConfidence) {
        continue;
      }

      final NutritionFood? nutrition = _nutritionRepository.findByName(
        entry.key,
      );
      if (nutrition == null) continue;
      detectedFoods.add(
        DetectedFood(
          name: nutrition.localizedName(languageCode),
          confidence: entry.value.clamp(0.0, 1.0).toDouble(),
          // These are review heuristics, not calibrated accuracy thresholds.
          requiresConfirmation: entry.value < 0.5 || margin < 0.15,
          alternatives: alternatives,
          suggestedGrams: nutrition.defaultGramsMedium,
          kcalPer100g: nutrition.kcalPer100g,
        ),
      );

      if (detectedFoods.length >= _maxDetectedFoods) {
        break;
      }
    }

    return detectedFoods;
  }

  static Future<List<double>> _runNativeClassification(
    String imagePath,
    int address,
  ) async {
    // Borrow the owner's native interpreter. Never close it in the worker.
    final interpreter = Interpreter.fromAddress(address, allocated: true);
    final bytes = await File(imagePath).readAsBytes();
    final decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) {
      throw ArgumentError('Could not decode image at path: $imagePath');
    }

    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    final inputQuantization = inputTensor.params;
    final outputQuantization = outputTensor.params;

    final input = _buildInputTensorData(
      image: decodedImage,
      inputShape: inputTensor.shape,
      inputType: inputTensor.type,
      inputQuantization: inputQuantization,
    );
    final output = _buildOutputTensorData(
      outputShape: outputTensor.shape,
      outputType: outputTensor.type,
    );

    interpreter.run(input, output);

    final rawScores = _flattenScores(output);
    if (rawScores.isEmpty) {
      return const <double>[];
    }

    final normalizedScores = _prepareRawScores(
      rawScores: rawScores,
      outputType: outputTensor.type,
      outputQuantization: outputQuantization,
    );
    final probabilities = _normalizeScores(normalizedScores);
    return probabilities;
  }

  Future<void> dispose() async {
    await _pendingDetection;
    _interpreter?.close();
    _interpreter = null;
    _labels = null;
    _initializationFuture = null;
  }

  Future<void> _ensureInitialized() {
    return _initializationFuture ??= _initializeModel().catchError((
      Object error,
      StackTrace stack,
    ) {
      _initializationFuture = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> _initializeModel() async {
    final options = InterpreterOptions()..threads = 2;
    final interpreter = await Interpreter.fromAsset(
      _modelAssetPath,
      options: options,
    );
    try {
      interpreter.allocateTensors();
      final labelsCsv = await rootBundle.loadString(_labelsAssetPath);
      final labels = _parseLabels(labelsCsv);
      final outputShape = interpreter.getOutputTensor(0).shape;
      final outputCount = outputShape.fold<int>(
        1,
        (count, size) => count * size,
      );
      if (labels.isEmpty ||
          outputCount != labels.length ||
          labels.any((label) => label.isEmpty)) {
        throw StateError(
          'Classifier labels must be contiguous and match output shape $outputShape.',
        );
      }
      _interpreter = interpreter;
      _labels = labels;
    } catch (_) {
      interpreter.close();
      rethrow;
    }
  }

  List<String> _parseLabels(String rawCsv) {
    final byId = <int, String>{};
    final lines = const LineSplitter()
        .convert(rawCsv)
        .where((line) => line.trim().isNotEmpty);

    for (final line in lines) {
      if (line.toLowerCase().startsWith('id,')) {
        continue;
      }
      final firstComma = line.indexOf(',');
      if (firstComma <= 0 || firstComma == line.length - 1) {
        continue;
      }

      final id = int.tryParse(line.substring(0, firstComma).trim());
      if (id == null || id < 0) {
        continue;
      }
      byId[id] = line.substring(firstComma + 1).trim();
    }

    if (byId.isEmpty) {
      return const <String>[];
    }

    final maxId = byId.keys.reduce(math.max);
    final labels = List<String>.filled(maxId + 1, '');
    byId.forEach((id, label) {
      labels[id] = label;
    });
    return labels;
  }

  static Object _buildInputTensorData({
    required img.Image image,
    required List<int> inputShape,
    required TensorType inputType,
    required QuantizationParams inputQuantization,
  }) {
    if (inputShape.length != 4 || inputShape.first != 1) {
      throw StateError(
        'Unexpected input tensor shape: $inputShape. Expected [1, H, W, 3] or [1, 3, H, W].',
      );
    }

    final bool isChannelFirst = inputShape[1] == 3;
    final int inputHeight = isChannelFirst ? inputShape[2] : inputShape[1];
    final int inputWidth = isChannelFirst ? inputShape[3] : inputShape[2];
    final preparedImage = _resizeForClassifier(
      image,
      targetWidth: inputWidth,
      targetHeight: inputHeight,
    );

    if (isChannelFirst) {
      return _buildChannelFirstInput(
        preparedImage,
        inputType,
        inputQuantization,
      );
    }
    return _buildChannelLastInput(preparedImage, inputType, inputQuantization);
  }

  static img.Image _resizeForClassifier(
    img.Image image, {
    required int targetWidth,
    required int targetHeight,
  }) {
    return prepareClassifierImage(image, targetWidth, targetHeight);
  }

  static Object _buildChannelLastInput(
    img.Image image,
    TensorType inputType,
    QuantizationParams inputQuantization,
  ) {
    if (inputType == TensorType.float32) {
      return <List<List<List<double>>>>[
        List<List<List<double>>>.generate(
          image.height,
          (y) => List<List<double>>.generate(image.width, (x) {
            final pixel = image.getPixel(x, y);
            return <double>[pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
          }),
        ),
      ];
    }

    if (inputType == TensorType.uint8 || inputType == TensorType.int8) {
      return <List<List<List<int>>>>[
        List<List<List<int>>>.generate(
          image.height,
          (y) => List<List<int>>.generate(image.width, (x) {
            final pixel = image.getPixel(x, y);
            return <int>[
              _toQuantizedChannel(
                value: pixel.r.toInt(),
                inputType: inputType,
                quantization: inputQuantization,
              ),
              _toQuantizedChannel(
                value: pixel.g.toInt(),
                inputType: inputType,
                quantization: inputQuantization,
              ),
              _toQuantizedChannel(
                value: pixel.b.toInt(),
                inputType: inputType,
                quantization: inputQuantization,
              ),
            ];
          }),
        ),
      ];
    }

    throw StateError('Unsupported input tensor type: $inputType');
  }

  static Object _buildChannelFirstInput(
    img.Image image,
    TensorType inputType,
    QuantizationParams inputQuantization,
  ) {
    if (inputType == TensorType.float32) {
      return <List<List<List<double>>>>[
        List<List<List<double>>>.generate(
          3,
          (c) => List<List<double>>.generate(
            image.height,
            (y) => List<double>.generate(image.width, (x) {
              final pixel = image.getPixel(x, y);
              return _normalizedPixelChannel(pixel: pixel, channelIndex: c);
            }),
          ),
        ),
      ];
    }

    if (inputType == TensorType.uint8 || inputType == TensorType.int8) {
      return <List<List<List<int>>>>[
        List<List<List<int>>>.generate(
          3,
          (c) => List<List<int>>.generate(
            image.height,
            (y) => List<int>.generate(image.width, (x) {
              final pixel = image.getPixel(x, y);
              final value = _pixelChannel(pixel: pixel, channelIndex: c);
              return _toQuantizedChannel(
                value: value,
                inputType: inputType,
                quantization: inputQuantization,
              );
            }),
          ),
        ),
      ];
    }

    throw StateError('Unsupported input tensor type: $inputType');
  }

  static double _normalizedPixelChannel({
    required img.Pixel pixel,
    required int channelIndex,
  }) {
    final value = _pixelChannel(pixel: pixel, channelIndex: channelIndex);
    return value / 255.0;
  }

  static int _pixelChannel({
    required img.Pixel pixel,
    required int channelIndex,
  }) {
    switch (channelIndex) {
      case 0:
        return pixel.r.toInt();
      case 1:
        return pixel.g.toInt();
      case 2:
        return pixel.b.toInt();
      default:
        throw ArgumentError('Invalid channel index: $channelIndex');
    }
  }

  static int _toQuantizedChannel({
    required int value,
    required TensorType inputType,
    required QuantizationParams quantization,
  }) {
    final scale = quantization.scale;
    final zeroPoint = quantization.zeroPoint;
    if (scale.isFinite && scale > 0.0) {
      final normalizedValue = _normalizeImageValueForQuantizedInput(
        pixelValue: value,
        scale: scale,
        inputType: inputType,
      );
      final quantized = (normalizedValue / scale + zeroPoint).round();
      if (inputType == TensorType.uint8) {
        return quantized.clamp(0, 255).toInt();
      }
      return quantized.clamp(-128, 127).toInt();
    }

    if (inputType == TensorType.uint8) {
      return value.clamp(0, 255).toInt();
    }

    final centered = value - 128;
    return centered.clamp(-128, 127).toInt();
  }

  static double _normalizeImageValueForQuantizedInput({
    required int pixelValue,
    required double scale,
    required TensorType inputType,
  }) {
    // Our exported classifier takes pixels in the [0, 1] range: the model has
    // an internal Rescaling([0,1] -> [-1,1]) layer, so its quantized input
    // tensor encodes [0, 1] (typically scale 1/255). Mirror the float32 path
    // (pixel / 255) for both int8 and uint8 so the same [0, 1] domain is used.
    // Only models whose input genuinely encodes raw [0, 255] intensities use a
    // larger scale; keep that fallback for robustness.
    if (scale <= 1.0 / 128.0) {
      return pixelValue / 255.0;
    }
    return pixelValue.toDouble();
  }

  static Object _buildOutputTensorData({
    required List<int> outputShape,
    required TensorType outputType,
  }) {
    if (outputType == TensorType.float32) {
      return _createTensorBuffer(outputShape, 0.0);
    }
    if (outputType == TensorType.uint8 || outputType == TensorType.int8) {
      return _createTensorBuffer(outputShape, 0);
    }

    throw StateError('Unsupported output tensor type: $outputType');
  }

  static Object _createTensorBuffer(List<int> shape, num fillValue) {
    if (shape.isEmpty) {
      return fillValue;
    }

    if (shape.length == 1) {
      if (fillValue is double) {
        return List<double>.filled(shape.first, fillValue);
      }
      return List<int>.filled(shape.first, fillValue.toInt());
    }

    return List<dynamic>.generate(
      shape.first,
      (_) => _createTensorBuffer(shape.sublist(1), fillValue),
    );
  }

  static List<double> _flattenScores(Object outputTensorData) {
    final result = <double>[];

    void walk(Object? node) {
      if (node is List) {
        for (final child in node) {
          walk(child);
        }
        return;
      }
      if (node is num) {
        result.add(node.toDouble());
      }
    }

    walk(outputTensorData);
    return result;
  }

  static List<double> _normalizeScores(List<double> rawScores) {
    return ClassifierPostprocessing.probabilities(rawScores);
  }

  static List<double> _prepareRawScores({
    required List<double> rawScores,
    required TensorType outputType,
    required QuantizationParams outputQuantization,
  }) {
    if (outputType == TensorType.uint8) {
      return _dequantizeScores(rawScores, outputQuantization);
    }

    if (outputType == TensorType.int8) {
      return _dequantizeScores(rawScores, outputQuantization);
    }

    return rawScores;
  }

  static List<double> _dequantizeScores(
    List<double> rawScores,
    QuantizationParams quantization,
  ) {
    final scale = quantization.scale;
    if (!scale.isFinite || scale <= 0.0) {
      return rawScores;
    }
    final zeroPoint = quantization.zeroPoint.toDouble();
    return rawScores.map((value) => (value - zeroPoint) * scale).toList();
  }

  Map<String, double> _mapPredictionsToSupportedFoods({
    required List<double> probabilities,
    required List<String> labels,
  }) {
    if (probabilities.length != labels.length) {
      throw StateError('Classifier output and label count do not match.');
    }
    final winner = ClassifierPostprocessing.winningClass(
      probabilities,
      minimum: _minConfidence,
    );
    if (winner == null) return const <String, double>{};
    final label = labels[winner];
    if (label.isEmpty || label == '__background__') {
      return const <String, double>{};
    }
    // Never substitute an unrelated lower-ranked class if the winner cannot
    // be mapped. A classifier's alternatives are not additional meal items.
    final mappedFood = _mapLabelToSupportedFood(label);
    return mappedFood == null
        ? const <String, double>{}
        : <String, double>{mappedFood: probabilities[winner]};
  }

  String? _mapLabelToSupportedFood(String label) {
    // Calories must describe the complete model class, not a guessed ingredient.
    // Unknown labels require a reviewed nutrition entry before they can be logged.
    return _nutritionRepository.findByName(label)?.name;
  }
}
