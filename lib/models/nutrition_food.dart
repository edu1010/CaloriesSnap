class NutritionFood {
  const NutritionFood({
    required this.name,
    required this.kcalPer100g,
    required this.defaultGramsSmall,
    required this.defaultGramsMedium,
    required this.defaultGramsLarge,
  });

  final String name;
  final double kcalPer100g;
  final double defaultGramsSmall;
  final double defaultGramsMedium;
  final double defaultGramsLarge;

  factory NutritionFood.fromJson(Map<String, dynamic> json) {
    return NutritionFood(
      name: json['name'] as String,
      kcalPer100g: (json['kcalPer100g'] as num).toDouble(),
      defaultGramsSmall: (json['defaultGramsSmall'] as num).toDouble(),
      defaultGramsMedium: (json['defaultGramsMedium'] as num).toDouble(),
      defaultGramsLarge: (json['defaultGramsLarge'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'kcalPer100g': kcalPer100g,
      'defaultGramsSmall': defaultGramsSmall,
      'defaultGramsMedium': defaultGramsMedium,
      'defaultGramsLarge': defaultGramsLarge,
    };
  }

  double gramsForPortion(String portionSize) {
    switch (portionSize.toLowerCase()) {
      case 'small':
        return defaultGramsSmall;
      case 'large':
        return defaultGramsLarge;
      case 'medium':
      default:
        return defaultGramsMedium;
    }
  }
}
