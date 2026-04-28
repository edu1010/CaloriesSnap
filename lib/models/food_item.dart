class FoodItem {
  const FoodItem({
    this.id,
    required this.name,
    required this.grams,
    required this.kcalPer100g,
    required this.calculatedKcal,
  });

  final int? id;
  final String name;
  final double grams;
  final double kcalPer100g;
  final double calculatedKcal;

  FoodItem copyWith({
    int? id,
    String? name,
    double? grams,
    double? kcalPer100g,
    double? calculatedKcal,
  }) {
    return FoodItem(
      id: id ?? this.id,
      name: name ?? this.name,
      grams: grams ?? this.grams,
      kcalPer100g: kcalPer100g ?? this.kcalPer100g,
      calculatedKcal: calculatedKcal ?? this.calculatedKcal,
    );
  }

  factory FoodItem.fromMap(Map<String, dynamic> map) {
    return FoodItem(
      id: map['id'] as int?,
      name: map['name'] as String,
      grams: (map['grams'] as num).toDouble(),
      kcalPer100g: (map['kcal_per_100g'] as num).toDouble(),
      calculatedKcal: (map['calculated_kcal'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toDatabaseMap({required int mealId}) {
    return <String, dynamic>{
      'id': id,
      'meal_id': mealId,
      'name': name,
      'grams': grams,
      'kcal_per_100g': kcalPer100g,
      'calculated_kcal': calculatedKcal,
    };
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'grams': grams,
      'kcalPer100g': kcalPer100g,
      'calculatedKcal': calculatedKcal,
    };
  }

  factory FoodItem.fromJson(Map<String, dynamic> map) {
    return FoodItem(
      id: map['id'] as int?,
      name: map['name'] as String,
      grams: (map['grams'] as num).toDouble(),
      kcalPer100g: (map['kcalPer100g'] as num).toDouble(),
      calculatedKcal: (map['calculatedKcal'] as num).toDouble(),
    );
  }
}
