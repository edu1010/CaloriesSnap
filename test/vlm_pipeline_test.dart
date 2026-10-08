import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:calorie_snap/data/repositories/nutrition_repository.dart';
import 'package:calorie_snap/services/food_detection/cascade_meal_analysis_service.dart';
import 'package:calorie_snap/services/food_detection/food_detection_service.dart';
import 'package:calorie_snap/services/food_detection/meal_analysis_service.dart';
import 'package:calorie_snap/services/food_detection/vlm/vlm_engine.dart';
import 'package:calorie_snap/services/food_detection/vlm/vlm_meal_analyzer.dart';
import 'package:calorie_snap/services/food_detection/vlm/vlm_model_catalog.dart';
import 'package:calorie_snap/services/food_detection/vlm/vlm_model_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Serves two fake model files, honouring HTTP range requests.
class _ModelServer {
  _ModelServer(this._server, this.files) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final Map<String, Uint8List> files;
  final List<String?> rangeHeaders = <String?>[];

  static Future<_ModelServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _ModelServer(server, <String, Uint8List>{
      'model.gguf': Uint8List.fromList(
        List<int>.generate(300000, (i) => i % 251),
      ),
      'mmproj.gguf': Uint8List.fromList(
        List<int>.generate(90000, (i) => (i * 7) % 253),
      ),
    });
  }

  VlmModelSpec spec({String? projectorSha256}) {
    VlmRemoteFile remote(String name, {String? hash}) => VlmRemoteFile(
      fileName: name,
      url: 'http://127.0.0.1:${_server.port}/$name',
      bytes: files[name]!.length,
      sha256: hash ?? sha256.convert(files[name]!).toString(),
    );
    return VlmModelSpec(
      id: 'test-model',
      name: 'Test model',
      model: remote('model.gguf'),
      projector: remote('mmproj.gguf', hash: projectorSha256),
      minDeviceRamGb: 1,
      imageMaxEdge: 256,
    );
  }

  Future<void> _handle(HttpRequest request) async {
    final bytes = files[request.uri.pathSegments.last]!;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    rangeHeaders.add(range);
    var start = 0;
    if (range != null) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      request.response.statusCode = HttpStatus.partialContent;
    }
    request.response.add(Uint8List.sublistView(bytes, start));
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

class _Classifier implements FoodDetectionService {
  _Classifier(this.result, {this.error});
  final List<DetectedFood> result;
  final Object? error;

  @override
  Future<List<DetectedFood>> detectFoods(String imagePath) async {
    if (error != null) throw error!;
    return result;
  }
}

class _Engine implements VlmEngine {
  _Engine(this.answer);

  /// Either the text to return or an error to throw.
  Object answer;
  Completer<void>? block;
  int loads = 0;
  int unloads = 0;
  int cancels = 0;
  String? lastPrompt;
  img.Image? lastImage;

  @override
  Future<void> load(VlmModelFiles files) async {
    expect(File(files.modelPath).existsSync(), isTrue);
    expect(File(files.projectorPath).existsSync(), isTrue);
    loads++;
  }

  @override
  Future<String> describeImage({
    required String imagePath,
    required String system,
    required String prompt,
    required int maxTokens,
    Map<String, dynamic>? responseFormat,
  }) async {
    lastPrompt = prompt;
    lastImage = img.decodeImage(await File(imagePath).readAsBytes());
    await block?.future;
    final answer = this.answer;
    if (answer is String) return answer;
    throw answer;
  }

  @override
  void cancel() {
    cancels++;
    block?.complete();
  }

  @override
  Future<void> unload() async => unloads++;
}

const _pizza = DetectedFood(
  name: 'Pizza',
  confidence: 0.6,
  suggestedGrams: 200,
  kcalPer100g: 266,
  alternatives: <DetectedFood>[
    DetectedFood(
      name: 'Lasagna',
      confidence: 0.2,
      suggestedGrams: 250,
      kcalPer100g: 135,
    ),
  ],
);

const _sandwichAnswer =
    '{"food":true,"dish":"Bocadillo de lomo con queso","items":['
    '{"name":"pan de barra","en":"baguette bread","grams":120,"kcal100":400},'
    '{"name":"lomo a la plancha","en":"grilled pork loin","grams":90,"kcal100":150},'
    '{"name":"mole poblano","en":"mole poblano","grams":20,"kcal100":310}]}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding replaces HttpClient with one that always answers 400.
  HttpOverrides.global = null;

  late _ModelServer server;
  late Directory root;
  late String photo;
  late NutritionRepository repository;

  setUpAll(() async {
    repository = NutritionRepository();
    await repository.load();
  });

  setUp(() async {
    server = await _ModelServer.start();
    root = await Directory.systemTemp.createTemp('caloriesnap_vlm_test');
    photo = p.join(root.path, 'photo.png');
    await File(
      photo,
    ).writeAsBytes(img.encodePng(img.Image(width: 1200, height: 800)));
  });

  tearDown(() async {
    await server.close();
    await root.delete(recursive: true);
  });

  VlmModelStore newStore(VlmModelSpec spec) => VlmModelStore(
    catalog: <VlmModelSpec>[spec],
    rootDirectory: () async => Directory(p.join(root.path, 'models')),
  );

  group('VlmModelStore', () {
    test('downloads, verifies, selects and persists a model', () async {
      final spec = server.spec();
      final store = newStore(spec);
      await store.init();
      expect(store.activeModel, isNull);

      final phases = <VlmDownloadPhase>{};
      store.addListener(() {
        final progress = store.progress;
        if (progress != null) phases.add(progress.phase);
      });
      await store.download(spec);

      expect(phases, contains(VlmDownloadPhase.verifying));
      expect(store.progress, isNull);
      expect(store.isInstalled(spec), isTrue);
      expect(store.activeModel?.id, spec.id);
      final files = (await store.filesOf(spec))!;
      expect(await File(files.modelPath).readAsBytes(), server.files['model.gguf']);

      final reopened = newStore(spec);
      await reopened.init();
      expect(reopened.activeModel?.id, spec.id);

      await reopened.select(null);
      expect(reopened.activeModel, isNull);
      expect(reopened.isInstalled(spec), isTrue);

      await reopened.delete(spec);
      expect(reopened.isInstalled(spec), isFalse);
      expect(File(files.modelPath).existsSync(), isFalse);
    });

    test('resumes a partial file with a range request', () async {
      final spec = server.spec();
      final store = newStore(spec);
      await store.init();
      final dir = Directory(p.join(root.path, 'models', spec.id));
      await dir.create(recursive: true);
      await File(p.join(dir.path, 'model.gguf.part')).writeAsBytes(
        Uint8List.sublistView(server.files['model.gguf']!, 0, 100000),
      );

      await store.download(spec);

      expect(server.rangeHeaders.first, 'bytes=100000-');
      final files = (await store.filesOf(spec))!;
      expect(await File(files.modelPath).readAsBytes(), server.files['model.gguf']);
    });

    test('rejects and removes a file whose checksum does not match', () async {
      final spec = server.spec(projectorSha256: 'a' * 64);
      final store = newStore(spec);
      await store.init();

      await expectLater(store.download(spec), throwsStateError);

      expect(store.isInstalled(spec), isFalse);
      expect(store.activeModel, isNull);
      expect(store.progress, isNull);
      expect(
        File(p.join(root.path, 'models', spec.id, 'mmproj.gguf')).existsSync(),
        isFalse,
      );
    });
  });

  group('CascadeMealAnalysisService', () {
    late VlmModelStore store;
    late _Engine engine;
    late VlmMealAnalyzer analyzer;

    Future<CascadeMealAnalysisService> cascade({
      bool installed = true,
      FoodDetectionService? classifier,
      Duration timeout = const Duration(seconds: 30),
    }) async {
      final spec = server.spec();
      store = newStore(spec);
      await store.init();
      if (installed) await store.download(spec);
      analyzer = VlmMealAnalyzer(
        engine: engine,
        store: store,
        nutritionRepository: repository,
      );
      addTearDown(analyzer.dispose);
      return CascadeMealAnalysisService(
        classifier: classifier ?? _Classifier(<DetectedFood>[_pizza]),
        vlm: analyzer,
        vlmTimeout: timeout,
      );
    }

    setUp(() => engine = _Engine(_sandwichAnswer));

    test('without a downloaded model the classifier answers alone', () async {
      final service = await cascade(installed: false);
      final result = await service.analyze(photo, languageCode: 'es');

      expect(result.engine, MealAnalysisEngine.classifier);
      expect(result.foods.single.name, 'Pizza');
      expect(result.candidates.map((food) => food.name), ['Pizza', 'Lasagna']);
      expect(result.vlmFailure, isNull);
      expect(engine.loads, 0);
    });

    test('the vision model lists components with table-backed energy', () async {
      final service = await cascade();
      final stages = <MealAnalysisStage>[];
      final result = await service.analyze(
        photo,
        languageCode: 'es',
        onStage: stages.add,
      );

      expect(stages, MealAnalysisStage.values);
      expect(result.engine, MealAnalysisEngine.vlm);
      expect(result.dishName, 'Bocadillo de lomo con queso');
      expect(result.candidates, isEmpty);
      expect(result.foods.map((food) => food.name), [
        'Pan de barra',
        'Lomo a la plancha',
        'Mole poblano',
      ]);
      // Table values replace the model's 400 and 150.
      expect(result.foods[0].kcalPer100g, 270);
      expect(result.foods[1].kcalPer100g, 200);
      expect(result.foods[0].suggestedGrams, 120);
      expect(result.foods[0].estimatedNutrition, isFalse);
      // Unknown to the table: the model's value, flagged as an estimate.
      expect(result.foods[2].kcalPer100g, 310);
      expect(result.foods[2].estimatedNutrition, isTrue);

      expect(engine.lastPrompt, contains('Pizza, Lasagna'));
      expect(engine.lastPrompt, contains('Spanish'));
      expect(engine.lastImage!.width, 256);
      expect(engine.lastImage!.height, lessThan(256));

      // The model stays loaded between photos.
      await service.analyze(photo, languageCode: 'es');
      expect(engine.loads, 1);
    });

    test('falls back to the classifier when the model fails', () async {
      final service = await cascade();
      for (final answer in <Object>[
        StateError('out of memory'),
        'Sorry, I cannot help with that.',
      ]) {
        engine.answer = answer;
        final result = await service.analyze(photo, languageCode: 'es');
        expect(result.engine, MealAnalysisEngine.classifier);
        expect(result.foods.single.name, 'Pizza');
        expect(result.vlmFailure, isNotNull);
      }
    });

    test('falls back and cancels generation on timeout', () async {
      engine.block = Completer<void>();
      final service = await cascade(timeout: const Duration(milliseconds: 300));
      final result = await service.analyze(photo, languageCode: 'es');

      expect(result.engine, MealAnalysisEngine.classifier);
      expect(result.vlmFailure, isA<TimeoutException>());
      expect(engine.cancels, 1);
    });

    test('"no food" adds nothing but keeps the classifier guesses', () async {
      engine.answer = '{"food":false,"dish":"","items":[]}';
      final service = await cascade();
      final result = await service.analyze(photo, languageCode: 'es');

      expect(result.engine, MealAnalysisEngine.vlm);
      expect(result.foods, isEmpty);
      expect(result.candidates.map((food) => food.name), ['Pizza', 'Lasagna']);
    });

    test('a broken classifier does not block the vision model', () async {
      final service = await cascade(
        classifier: _Classifier(const [], error: StateError('no tflite')),
      );
      final result = await service.analyze(photo, languageCode: 'en');
      expect(result.engine, MealAnalysisEngine.vlm);
      expect(result.foods, hasLength(3));
      expect(engine.lastPrompt, isNot(contains('classifier guessed')));

      final alone = await cascade(
        installed: false,
        classifier: _Classifier(const [], error: StateError('no tflite')),
      );
      // Same model directory as above, so turn the model off explicitly.
      await store.select(null);
      await expectLater(
        alone.analyze(photo, languageCode: 'en'),
        throwsStateError,
      );
    });

    test('deleting the active model releases it from memory', () async {
      final service = await cascade();
      await service.analyze(photo, languageCode: 'es');
      expect(engine.unloads, 0);

      await store.delete(store.catalog.single);
      await analyzer.dispose();
      expect(engine.unloads, 1);
      expect(analyzer.isAvailable, isFalse);
    });
  });
}
