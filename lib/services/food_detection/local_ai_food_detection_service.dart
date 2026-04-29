import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../data/repositories/nutrition_repository.dart';
import '../../models/nutrition_food.dart';
import 'food_detection_service.dart';

class LocalAiFoodDetectionService implements FoodDetectionService {
  LocalAiFoodDetectionService({
    required NutritionRepository nutritionRepository,
    String modelAssetPath = 'assets/models/food_classifier.tflite',
    String labelsAssetPath = 'assets/models/food_classifier_labels.csv',
  }) : _nutritionRepository = nutritionRepository,
       _modelAssetPath = modelAssetPath,
       _labelsAssetPath = labelsAssetPath;

  static const int _maxDetectedFoods = 3;
  static const double _minConfidence = 0.03;
  static const int _maxMappedPredictions = 80;
  static const double _minLexicalScore = 1.0;

  static final Map<String, _FoodLexicon> _foodLexicons = <String, _FoodLexicon>{
    'Rice cooked': const _FoodLexicon(
      keywords: <String>{
        'rice',
        'risotto',
        'pilaf',
        'biryani',
        'paella',
        'congee',
        'porridge',
        'chahan',
        'nasi',
        'jollof',
        'arroz',
      },
      phrases: <String>{
        'fried rice',
        'sticky rice',
        'rice bowl',
        'rice cake',
        'rice porridge',
      },
    ),
    'Chicken breast': const _FoodLexicon(
      keywords: <String>{
        'chicken',
        'poultry',
        'drumstick',
        'wing',
        'nugget',
        'karaage',
        'teriyaki',
        'katsu',
        'tikka',
      },
      phrases: <String>{
        'fried chicken',
        'grilled chicken',
        'chicken breast',
        'chicken salad',
        'chicken sandwich',
      },
    ),
    'Pasta cooked': const _FoodLexicon(
      keywords: <String>{
        'pasta',
        'spaghetti',
        'macaroni',
        'noodle',
        'ramen',
        'udon',
        'penne',
        'linguine',
        'fettuccine',
        'lasagna',
        'ravioli',
        'gnocchi',
      },
      phrases: <String>{'mac and cheese', 'noodle soup', 'pasta salad'},
    ),
    'Bread': const _FoodLexicon(
      keywords: <String>{
        'bread',
        'toast',
        'bagel',
        'bun',
        'roll',
        'naan',
        'pita',
        'sandwich',
        'burger',
        'baguette',
        'focaccia',
        'pizza',
        'quesadilla',
        'flatbread',
      },
      phrases: <String>{
        'garlic bread',
        'grilled cheese',
        'french toast',
        'hot dog bun',
      },
    ),
    'Egg': const _FoodLexicon(
      keywords: <String>{
        'egg',
        'omelet',
        'omelette',
        'frittata',
        'quiche',
        'benedict',
        'scramble',
        'tamago',
      },
      phrases: <String>{'fried egg', 'boiled egg', 'poached egg'},
    ),
    'Salad': const _FoodLexicon(
      keywords: <String>{
        'salad',
        'slaw',
        'coleslaw',
        'tabbouleh',
        'tabouli',
        'gazpacho',
        'ceviche',
        'aguachile',
      },
      phrases: <String>{
        'green salad',
        'fruit salad',
        'potato salad',
        'caesar salad',
      },
    ),
    'Olive oil': const _FoodLexicon(
      keywords: <String>{'olive', 'vinaigrette', 'dressing', 'aioli'},
      phrases: <String>{'olive oil', 'olive tapenade'},
    ),
  };

  final NutritionRepository _nutritionRepository;
  final String _modelAssetPath;
  final String _labelsAssetPath;

  Interpreter? _interpreter;
  List<String>? _labels;
  Future<void>? _initializationFuture;

  @override
  Future<List<DetectedFood>> detectFoods(String imagePath) async {
    await _ensureInitialized();

    final interpreter = _interpreter;
    final labels = _labels;
    if (interpreter == null || labels == null || labels.isEmpty) {
      throw StateError('Local food detection model is not initialized.');
    }

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
      return const <DetectedFood>[];
    }

    final normalizedScores = _prepareRawScores(
      rawScores: rawScores,
      outputType: outputTensor.type,
      outputQuantization: outputQuantization,
    );
    final probabilities = _normalizeScores(normalizedScores);
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

    final detectedFoods = <DetectedFood>[];
    for (final entry in ranked) {
      if (entry.value < _minConfidence && detectedFoods.isNotEmpty) {
        continue;
      }

      final NutritionFood? nutrition = _nutritionRepository.findByName(
        entry.key,
      );
      detectedFoods.add(
        DetectedFood(
          name: entry.key,
          confidence: entry.value.clamp(0.0, 1.0).toDouble(),
          suggestedGrams: nutrition?.defaultGramsMedium ?? 120,
          kcalPer100g: nutrition?.kcalPer100g ?? 100,
        ),
      );

      if (detectedFoods.length >= _maxDetectedFoods) {
        break;
      }
    }

    return detectedFoods;
  }

  Future<void> _ensureInitialized() {
    return _initializationFuture ??= _initializeModel();
  }

  Future<void> _initializeModel() async {
    final options = InterpreterOptions()..threads = 2;
    final interpreter = await Interpreter.fromAsset(
      _modelAssetPath,
      options: options,
    );
    interpreter.allocateTensors();

    final labelsCsv = await rootBundle.loadString(_labelsAssetPath);
    final labels = _parseLabels(labelsCsv);
    if (labels.isEmpty) {
      throw StateError('No labels loaded from $_labelsAssetPath.');
    }

    _interpreter = interpreter;
    _labels = labels;
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
      if (id == null) {
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

  Object _buildInputTensorData({
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
    final preparedImage = _centerCropAndResize(
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

  img.Image _centerCropAndResize(
    img.Image image, {
    required int targetWidth,
    required int targetHeight,
  }) {
    final cropSize = math.min(image.width, image.height);
    final offsetX = (image.width - cropSize) ~/ 2;
    final offsetY = (image.height - cropSize) ~/ 2;
    final cropped = img.copyCrop(
      image,
      x: offsetX,
      y: offsetY,
      width: cropSize,
      height: cropSize,
    );

    return img.copyResize(
      cropped,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.linear,
    );
  }

  Object _buildChannelLastInput(
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

  Object _buildChannelFirstInput(
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

  double _normalizedPixelChannel({
    required img.Pixel pixel,
    required int channelIndex,
  }) {
    final value = _pixelChannel(pixel: pixel, channelIndex: channelIndex);
    return value / 255.0;
  }

  int _pixelChannel({required img.Pixel pixel, required int channelIndex}) {
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

  int _toQuantizedChannel({
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

  double _normalizeImageValueForQuantizedInput({
    required int pixelValue,
    required double scale,
    required TensorType inputType,
  }) {
    // Most image models quantize either [0, 1] or [-1, 1] input ranges.
    // With larger scales the model usually expects [0, 255] intensity values.
    if (scale <= 1.0 / 128.0) {
      if (inputType == TensorType.int8) {
        return pixelValue / 127.5 - 1.0;
      }
      return pixelValue / 255.0;
    }
    return pixelValue.toDouble();
  }

  Object _buildOutputTensorData({
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

  Object _createTensorBuffer(List<int> shape, num fillValue) {
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

  List<double> _flattenScores(Object outputTensorData) {
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

  List<double> _normalizeScores(List<double> rawScores) {
    if (rawScores.isEmpty) {
      return const <double>[];
    }

    final finiteScores = rawScores.where((v) => v.isFinite).toList();
    if (finiteScores.isEmpty) {
      return List<double>.filled(rawScores.length, 0.0);
    }

    final total = finiteScores.fold<double>(0.0, (sum, value) => sum + value);
    final looksLikeProbabilities =
        rawScores.every((v) => v >= 0.0 && v <= 1.0) &&
        total > 0.8 &&
        total < 1.2;
    if (looksLikeProbabilities) {
      return rawScores
          .map((value) => value.clamp(0.0, 1.0).toDouble())
          .toList();
    }

    final maxLogit = finiteScores.reduce(math.max);
    final expScores = <double>[];
    var denominator = 0.0;
    for (final value in rawScores) {
      final safeValue = value.isFinite ? value : -1e9;
      final expValue = math.exp(safeValue - maxLogit);
      expScores.add(expValue);
      denominator += expValue;
    }

    if (denominator <= 0.0) {
      return List<double>.filled(rawScores.length, 0.0);
    }

    return expScores.map((value) => value / denominator).toList();
  }

  List<double> _prepareRawScores({
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

  List<double> _dequantizeScores(
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
    final available = math.min(probabilities.length, labels.length);
    if (available == 0) {
      return const <String, double>{};
    }

    final rankedIndices = List<int>.generate(available, (index) => index)
      ..sort((a, b) => probabilities[b].compareTo(probabilities[a]));

    final mappedScores = <String, double>{};
    final topCount = math.min(_maxMappedPredictions, rankedIndices.length);

    for (var i = 0; i < topCount; i++) {
      final index = rankedIndices[i];
      final label = labels[index];
      if (label.isEmpty || label == '__background__') {
        continue;
      }

      final mappedFood = _mapLabelToSupportedFood(label);
      if (mappedFood == null) {
        continue;
      }

      final score = probabilities[index];
      final previous = mappedScores[mappedFood] ?? 0.0;
      if (score > previous) {
        mappedScores[mappedFood] = score;
      }
    }

    return mappedScores;
  }

  String? _mapLabelToSupportedFood(String label) {
    final directMatch = _nutritionRepository.findByName(label);
    if (directMatch != null) {
      return directMatch.name;
    }

    final normalized = _normalizeLabelForMatching(label);
    final tokens = _tokenizeLabel(normalized);
    if (tokens.isEmpty) {
      return null;
    }

    String? bestFood;
    var bestScore = 0.0;
    for (final entry in _foodLexicons.entries) {
      final score = _scoreLexicalMatch(
        normalizedLabel: normalized,
        tokens: tokens,
        lexicon: entry.value,
      );
      if (score > bestScore) {
        bestScore = score;
        bestFood = entry.key;
      }
    }

    if (bestScore < _minLexicalScore) {
      return null;
    }
    return bestFood;
  }

  String _normalizeLabelForMatching(String label) {
    final normalized = label.toLowerCase();
    final buffer = StringBuffer();
    for (var i = 0; i < normalized.length; i++) {
      final code = normalized.codeUnitAt(i);
      final isAsciiLowercase = code >= 97 && code <= 122;
      final isDigit = code >= 48 && code <= 57;
      buffer.write(isAsciiLowercase || isDigit ? normalized[i] : ' ');
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Set<String> _tokenizeLabel(String normalizedLabel) {
    if (normalizedLabel.isEmpty) {
      return const <String>{};
    }
    return normalizedLabel
        .split(' ')
        .where((token) => token.isNotEmpty)
        .map(_stemToken)
        .toSet();
  }

  String _stemToken(String token) {
    if (token.length > 4 && token.endsWith('ies')) {
      return '${token.substring(0, token.length - 3)}y';
    }
    if (token.length > 4 && token.endsWith('es')) {
      return token.substring(0, token.length - 2);
    }
    if (token.length > 3 && token.endsWith('s')) {
      return token.substring(0, token.length - 1);
    }
    return token;
  }

  double _scoreLexicalMatch({
    required String normalizedLabel,
    required Set<String> tokens,
    required _FoodLexicon lexicon,
  }) {
    var score = 0.0;

    for (final phrase in lexicon.phrases) {
      if (normalizedLabel.contains(phrase)) {
        score += 2.0;
      }
    }
    for (final keyword in lexicon.keywords) {
      if (tokens.contains(_stemToken(keyword))) {
        score += 1.0;
      }
    }
    return score;
  }
}

class _FoodLexicon {
  const _FoodLexicon({required this.keywords, required this.phrases});

  final Set<String> keywords;
  final Set<String> phrases;
}
