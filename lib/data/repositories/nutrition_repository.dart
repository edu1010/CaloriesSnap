import 'dart:convert';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;

import '../../models/ingredient.dart';
import '../../models/nutrition_food.dart';
import '../../services/nutrition/food_search.dart';

class NutritionRepository {
  static const String _genericFoodsAsset =
      'lib/data/local/nutrition_database.json';
  static const String _dishFoodsAsset = 'lib/data/local/food101_nutrition.json';
  static const String _commonFoodsAsset =
      'lib/data/local/common_foods_es.json';
  static const String _packagedFoodsAsset =
      'lib/data/local/nutrition_products_es.json';
  static const String _ingredientsAsset =
      'lib/data/local/ingredients_es.json';

  final List<NutritionFood> _foods = <NutritionFood>[];
  final List<NutritionFood> _barcodeFoods = <NutritionFood>[];
  final Map<String, NutritionFood> _foodsByName = <String, NutritionFood>{};
  final Map<String, NutritionFood> _foodsByBarcode = <String, NutritionFood>{};

  final List<Ingredient> _ingredients = <Ingredient>[];
  FoodSearch _search = FoodSearch(ingredients: const <Ingredient>[]);

  List<NutritionFood> get foods => List<NutritionFood>.unmodifiable(_foods);

  /// Base foods with their preparations (raw, boiled, fried...).
  List<Ingredient> get ingredients =>
      List<Ingredient>.unmodifiable(_ingredients);

  /// Search over [ingredients] and the prepared dishes of [foods].
  FoodSearch get search => _search;
  int get barcodeFoodsCount => _barcodeFoods.length;

  Future<void> load() async {
    if (_foods.isNotEmpty) {
      return;
    }

    final genericFoods = await _loadFoodsFromAsset(_genericFoodsAsset);
    final dishFoods = await _loadFoodsFromAsset(
      _dishFoodsAsset,
      allowMissing: true,
    );
    final commonFoods = await _loadFoodsFromAsset(
      _commonFoodsAsset,
      allowMissing: true,
    );
    final barcodeFoods = await _loadFoodsFromAsset(
      _packagedFoodsAsset,
      allowMissing: true,
    );
    final ingredients = await _loadIngredients();

    // Generic ingredients are loaded first so they win on name collisions
    // (e.g. "French Fries") while the Food-101 dish table fills in every
    // label the on-device classifier can produce.
    _foods
      ..clear()
      ..addAll(genericFoods)
      ..addAll(dishFoods)
      ..addAll(commonFoods);
    final dishes = List<NutritionFood>.of(_foods);
    _ingredients
      ..clear()
      ..addAll(ingredients);
    // Every preparation is also a plain table row, added last so the
    // existing tables keep winning on name collisions. That way a name
    // picked in the search ("Arroz hervido") resolves again later.
    for (final ingredient in ingredients) {
      for (final variant in ingredient.variants) {
        _foods.add(ingredient.toNutritionFood(variant));
      }
    }
    _search = FoodSearch(ingredients: ingredients, dishes: dishes);

    _barcodeFoods
      ..clear()
      ..addAll(
        barcodeFoods.where((food) => _normalizeBarcode(food.barcode) != null),
      );

    _foodsByName.clear();
    for (final food in _foods) {
      _indexByNames(food);
    }
    for (final food in _barcodeFoods) {
      _indexByNames(food);
    }

    _foodsByBarcode.clear();
    for (final food in _barcodeFoods) {
      final normalizedBarcode = _normalizeBarcode(food.barcode);
      if (normalizedBarcode != null) {
        _foodsByBarcode.putIfAbsent(normalizedBarcode, () => food);
      }
    }
    for (final food in _foods) {
      final normalizedBarcode = _normalizeBarcode(food.barcode);
      if (normalizedBarcode != null) {
        _foodsByBarcode.putIfAbsent(normalizedBarcode, () => food);
      }
    }
  }

  NutritionFood? findByName(String name) {
    return _foodsByName[_normalizeName(name)];
  }

  /// Indexes a food by its canonical name and any localized variant so that
  /// [findByName] resolves regardless of which display name was persisted.
  void _indexByNames(NutritionFood food) {
    _foodsByName.putIfAbsent(_normalizeName(food.name), () => food);
    final localized = food.nameEs;
    if (localized != null && localized.trim().isNotEmpty) {
      _foodsByName.putIfAbsent(_normalizeName(localized), () => food);
    }
  }

  NutritionFood? findByBarcode(String barcode) {
    final normalized = _normalizeBarcode(barcode);
    if (normalized == null) {
      return null;
    }
    return _foodsByBarcode[normalized];
  }

  Future<List<Ingredient>> _loadIngredients() async {
    try {
      final raw = await rootBundle.loadString(_ingredientsAsset);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final source = decoded['source'] as String?;
      return (decoded['ingredients'] as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map((json) => Ingredient.fromJson(json, source: source))
          .toList(growable: false);
    } on FlutterError {
      // Asset not bundled (older builds, some tests).
      return const <Ingredient>[];
    }
  }

  Future<List<NutritionFood>> _loadFoodsFromAsset(
    String assetPath, {
    bool allowMissing = false,
  }) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return const <NutritionFood>[];
      }

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(NutritionFood.fromJson)
          .toList(growable: false);
    } catch (_) {
      if (allowMissing) {
        return const <NutritionFood>[];
      }
      rethrow;
    }
  }

  // Classifier labels often use underscores, while users enter accented
  // Spanish names. Keep matching exact after normalizing typography: dropping
  // preparation words (raw/cooked/fried) can silently select a wrong density.
  String _normalizeName(String value) {
    var normalized = value.trim().toLowerCase();
    const accents = <String, String>{
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ñ': 'n',
    };
    for (final entry in accents.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }
    return normalized
        .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
        .replaceAll(RegExp(r'[_\-\s]+'), ' ')
        .trim();
  }

  String? _normalizeBarcode(String? value) {
    if (value == null) {
      return null;
    }
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 8 || digits.length > 14) {
      return null;
    }
    return digits;
  }
}
