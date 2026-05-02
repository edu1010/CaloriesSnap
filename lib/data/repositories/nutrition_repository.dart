import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../models/nutrition_food.dart';

class NutritionRepository {
  static const String _genericFoodsAsset =
      'lib/data/local/nutrition_database.json';
  static const String _packagedFoodsAsset =
      'lib/data/local/nutrition_products_es.json';

  final List<NutritionFood> _foods = <NutritionFood>[];
  final List<NutritionFood> _barcodeFoods = <NutritionFood>[];
  final Map<String, NutritionFood> _foodsByName = <String, NutritionFood>{};
  final Map<String, NutritionFood> _foodsByBarcode = <String, NutritionFood>{};

  List<NutritionFood> get foods => List<NutritionFood>.unmodifiable(_foods);
  int get barcodeFoodsCount => _barcodeFoods.length;

  Future<void> load() async {
    if (_foods.isNotEmpty) {
      return;
    }

    final genericFoods = await _loadFoodsFromAsset(_genericFoodsAsset);
    final barcodeFoods = await _loadFoodsFromAsset(
      _packagedFoodsAsset,
      allowMissing: true,
    );

    _foods
      ..clear()
      ..addAll(genericFoods);

    _barcodeFoods
      ..clear()
      ..addAll(
        barcodeFoods.where((food) => _normalizeBarcode(food.barcode) != null),
      );

    _foodsByName.clear();
    for (final food in _foods) {
      _foodsByName.putIfAbsent(_normalizeName(food.name), () => food);
    }
    for (final food in _barcodeFoods) {
      _foodsByName.putIfAbsent(_normalizeName(food.name), () => food);
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

  NutritionFood? findByBarcode(String barcode) {
    final normalized = _normalizeBarcode(barcode);
    if (normalized == null) {
      return null;
    }
    return _foodsByBarcode[normalized];
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

  String _normalizeName(String value) => value.trim().toLowerCase();

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
