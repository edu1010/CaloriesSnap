class NutritionFood {
  const NutritionFood({
    required this.name,
    required this.kcalPer100g,
    required this.defaultGramsSmall,
    required this.defaultGramsMedium,
    required this.defaultGramsLarge,
    this.nameEs,
    this.barcode,
    this.brand,
    this.category,
    this.source,
    this.aliases = const <String>[],
    this.unitGrams,
    this.unitMillilitres,
    this.scoopGrams,
  });

  final String name;
  final String? nameEs;
  final double kcalPer100g;
  final double defaultGramsSmall;
  final double defaultGramsMedium;
  final double defaultGramsLarge;
  final String? barcode;
  final String? brand;
  final String? category;
  final String? source;
  final List<String> aliases;
  final double? unitGrams;

  /// Bottle volume for drinks whose label gives energy per 100 ml.
  /// The legacy gram fields carry nominal amounts at 1 g/ml for these rows.
  final double? unitMillilitres;
  final double? scoopGrams;

  double? get standardUnitAmount => unitGrams ?? unitMillilitres;

  factory NutritionFood.fromJson(Map<String, dynamic> json) {
    return NutritionFood(
      name: json['name'] as String,
      nameEs: _asNullableString(json['nameEs']),
      kcalPer100g: (json['kcalPer100g'] as num).toDouble(),
      defaultGramsSmall: (json['defaultGramsSmall'] as num).toDouble(),
      defaultGramsMedium: (json['defaultGramsMedium'] as num).toDouble(),
      defaultGramsLarge: (json['defaultGramsLarge'] as num).toDouble(),
      barcode: _asNullableString(json['barcode']),
      brand: _asNullableString(json['brand']),
      category: _asNullableString(json['category']),
      source: _asNullableString(json['source']),
      aliases: (json['aliases'] as List<dynamic>? ?? const []).cast<String>(),
      unitGrams: (json['unitGrams'] as num?)?.toDouble(),
      unitMillilitres: (json['unitMillilitres'] as num?)?.toDouble(),
      scoopGrams: (json['scoopGrams'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'nameEs': nameEs,
      'kcalPer100g': kcalPer100g,
      'defaultGramsSmall': defaultGramsSmall,
      'defaultGramsMedium': defaultGramsMedium,
      'defaultGramsLarge': defaultGramsLarge,
      'barcode': barcode,
      'brand': brand,
      'category': category,
      'source': source,
      if (aliases.isNotEmpty) 'aliases': aliases,
      if (unitGrams != null) 'unitGrams': unitGrams,
      if (unitMillilitres != null) 'unitMillilitres': unitMillilitres,
      if (scoopGrams != null) 'scoopGrams': scoopGrams,
    };
  }

  /// Display name for the given language code. Falls back to the canonical
  /// (English) [name] when no localized variant is available.
  String localizedName(String languageCode) {
    if (languageCode == 'es') {
      final localized = nameEs;
      if (localized != null && localized.isNotEmpty) {
        return localized;
      }
    }
    return name;
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

String? _asNullableString(Object? value) {
  if (value == null) {
    return null;
  }
  final asString = value.toString().trim();
  return asString.isEmpty ? null : asString;
}
