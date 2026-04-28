import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../models/nutrition_food.dart';

class NutritionRepository {
  final List<NutritionFood> _foods = <NutritionFood>[];

  List<NutritionFood> get foods => List<NutritionFood>.unmodifiable(_foods);

  Future<void> load() async {
    if (_foods.isNotEmpty) {
      return;
    }

    final raw = await rootBundle.loadString('lib/data/local/nutrition_database.json');
    final decoded = jsonDecode(raw) as List<dynamic>;
    _foods
      ..clear()
      ..addAll(
        decoded
            .cast<Map<String, dynamic>>()
            .map(NutritionFood.fromJson),
      );
  }

  NutritionFood? findByName(String name) {
    final target = name.trim().toLowerCase();
    for (final item in _foods) {
      if (item.name.toLowerCase() == target) {
        return item;
      }
    }
    return null;
  }
}
