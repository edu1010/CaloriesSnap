import 'nutrition_food.dart';

/// How a food was prepared. Each one changes the energy density: boiled rice
/// is 130 kcal/100 g, fried rice about 175.
enum Preparation {
  raw,
  boiled,
  cooked,
  steamed,
  grilled,
  baked,
  roasted,
  fried,
  sauteed,
  stewed,
  battered,
  breaded,
  scrambled,
  canned,
  dried,
  smoked,
  cured,
  toasted,
  mashed,

  /// A kind rather than a cooking method ("whole milk", "Greek yogurt");
  /// the variant carries its own labels.
  custom;

  static Preparation parse(String value) => Preparation.values.firstWhere(
    (prep) => prep.name == value,
    orElse: () => Preparation.custom,
  );

  String labelEn() => _english[this] ?? name;

  /// Spanish participles agree with the noun: "arroz frito", "patata frita",
  /// "garbanzos cocidos".
  String labelEs(Gender gender) {
    final forms = _spanish[this];
    if (forms == null) return name;
    if (forms.length == 1) return forms.first;
    return forms[gender.index];
  }

  static const Map<Preparation, String> _english = <Preparation, String>{
    raw: 'Raw',
    boiled: 'Boiled',
    cooked: 'Cooked',
    steamed: 'Steamed',
    grilled: 'Grilled',
    baked: 'Baked',
    roasted: 'Roasted',
    fried: 'Fried',
    sauteed: 'Sautéed',
    stewed: 'Stewed',
    battered: 'Battered',
    breaded: 'Breaded',
    scrambled: 'Scrambled',
    canned: 'Canned',
    dried: 'Dried',
    smoked: 'Smoked',
    cured: 'Cured',
    toasted: 'Toasted',
    mashed: 'Mashed',
  };

  // Forms in [Gender] order: m, f, mp, fp. One form = invariant phrase.
  static const Map<Preparation, List<String>> _spanish =
      <Preparation, List<String>>{
        raw: <String>['crudo', 'cruda', 'crudos', 'crudas'],
        boiled: <String>['hervido', 'hervida', 'hervidos', 'hervidas'],
        cooked: <String>['cocido', 'cocida', 'cocidos', 'cocidas'],
        steamed: <String>['al vapor'],
        grilled: <String>['a la plancha'],
        baked: <String>['al horno'],
        roasted: <String>['asado', 'asada', 'asados', 'asadas'],
        fried: <String>['frito', 'frita', 'fritos', 'fritas'],
        sauteed: <String>['salteado', 'salteada', 'salteados', 'salteadas'],
        stewed: <String>['guisado', 'guisada', 'guisados', 'guisadas'],
        battered: <String>['rebozado', 'rebozada', 'rebozados', 'rebozadas'],
        breaded: <String>['empanado', 'empanada', 'empanados', 'empanadas'],
        scrambled: <String>['revuelto', 'revuelta', 'revueltos', 'revueltas'],
        canned: <String>['en conserva'],
        dried: <String>['seco', 'seca', 'secos', 'secas'],
        smoked: <String>['ahumado', 'ahumada', 'ahumados', 'ahumadas'],
        cured: <String>['curado', 'curada', 'curados', 'curadas'],
        toasted: <String>['tostado', 'tostada', 'tostados', 'tostadas'],
        mashed: <String>['en puré'],
      };
}

/// Grammatical gender and number of a Spanish food name.
enum Gender {
  m,
  f,
  mp,
  fp;

  static Gender parse(String? value) => Gender.values.firstWhere(
    (gender) => gender.name == value,
    orElse: () => Gender.m,
  );
}

/// Nutrition of one preparation of an [Ingredient], per 100 g as eaten.
class IngredientVariant {
  const IngredientVariant({
    required this.preparation,
    required this.kcalPer100g,
    this.proteinPer100g,
    this.carbsPer100g,
    this.fatPer100g,
    this.portionGrams,
    this.labelEs,
    this.labelEn,
    this.nameEs,
    this.nameEn,
    this.source,
  });

  factory IngredientVariant.fromJson(Map<String, dynamic> json) {
    final grams = json['grams'] as List<dynamic>?;
    return IngredientVariant(
      preparation: Preparation.parse(json['prep'] as String),
      kcalPer100g: (json['kcal'] as num).toDouble(),
      proteinPer100g: (json['protein'] as num?)?.toDouble(),
      carbsPer100g: (json['carbs'] as num?)?.toDouble(),
      fatPer100g: (json['fat'] as num?)?.toDouble(),
      portionGrams: grams?.map((value) => (value as num).toDouble()).toList(),
      labelEs: json['labelEs'] as String?,
      labelEn: json['labelEn'] as String?,
      nameEs: json['nameEs'] as String?,
      nameEn: json['name'] as String?,
      source: json['src'] as String?,
    );
  }

  final Preparation preparation;
  final double kcalPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;

  /// Small / medium / large grams when they differ from the ingredient's
  /// (raw rice is weighed dry, so its portions are smaller).
  final List<double>? portionGrams;

  /// Chip label and full name overrides for kinds ("Entera" / "Leche
  /// entera") and for irregular names ("Patatas fritas").
  final String? labelEs;
  final String? labelEn;
  final String? nameEs;
  final String? nameEn;

  /// Where the numbers come from: `ciqual:<code>` (CIQUAL 2020 food),
  /// `ciqual:<code>+oil<g>` (that food plus g of olive oil per 100 g, an
  /// estimate for home frying) or `estimate`.
  final String? source;

  /// CIQUAL food code, when the values come from the table.
  int? get ciqualCode {
    final match = RegExp(r'^ciqual:(\d+)').firstMatch(source ?? '');
    return match == null ? null : int.parse(match.group(1)!);
  }

  /// Grams of added oil per 100 g in a derived value, else null.
  int? get addedOilGrams {
    final match = RegExp(r'\+oil(\d+)$').firstMatch(source ?? '');
    return match == null ? null : int.parse(match.group(1)!);
  }

  bool get hasMacros =>
      proteinPer100g != null && carbsPer100g != null && fatPer100g != null;
}

/// A food with all the ways it is usually prepared.
class Ingredient {
  const Ingredient({
    required this.id,
    required this.name,
    required this.nameEs,
    required this.gender,
    required this.portionGrams,
    required this.variants,
    this.defaultIndex = 0,
    this.category,
    this.aliases = const <String>[],
    this.source,
    this.dish,
  });

  factory Ingredient.fromJson(Map<String, dynamic> json, {String? source}) {
    final variants =
        (json['variants'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(IngredientVariant.fromJson)
            .toList();
    final defaultPrep = Preparation.parse(json['default'] as String? ?? '');
    final defaultIndex = variants.indexWhere(
      (variant) => variant.preparation == defaultPrep,
    );
    return Ingredient(
      id: json['id'] as String,
      name: json['name'] as String,
      nameEs: json['nameEs'] as String,
      gender: Gender.parse(json['gender'] as String?),
      category: json['category'] as String?,
      aliases:
          (json['aliases'] as List<dynamic>? ?? const <dynamic>[])
              .cast<String>(),
      portionGrams:
          (json['grams'] as List<dynamic>)
              .map((value) => (value as num).toDouble())
              .toList(),
      variants: variants,
      defaultIndex: defaultIndex < 0 ? 0 : defaultIndex,
      source: source,
    );
  }

  /// A prepared dish of the general table, shown in the same picker as a
  /// single "variant" without macros.
  factory Ingredient.fromDish(NutritionFood food) => Ingredient(
    id: 'dish:${food.name}',
    name: food.name,
    nameEs: food.nameEs ?? food.name,
    gender: Gender.m,
    category: food.category,
    aliases: food.aliases,
    portionGrams: <double>[
      food.defaultGramsSmall,
      food.defaultGramsMedium,
      food.defaultGramsLarge,
    ],
    variants: <IngredientVariant>[
      IngredientVariant(
        preparation: Preparation.custom,
        kcalPer100g: food.kcalPer100g,
        nameEs: food.nameEs ?? food.name,
        nameEn: food.name,
      ),
    ],
    source: food.source,
    dish: food,
  );

  final String id;
  final String name;
  final String nameEs;
  final Gender gender;
  final String? category;
  final List<String> aliases;
  final List<double> portionGrams;
  final List<IngredientVariant> variants;
  final int defaultIndex;
  final String? source;

  /// Set when this entry wraps a dish of the general nutrition table.
  final NutritionFood? dish;

  bool get isDish => dish != null;

  String localizedName(String languageCode) =>
      languageCode == 'es' ? nameEs : name;

  /// Short chip label of [variant]: "Frito", "A la plancha", "Entera".
  String variantLabel(IngredientVariant variant, String languageCode) {
    final spanish = languageCode == 'es';
    final custom = spanish ? variant.labelEs : variant.labelEn;
    if (custom != null) return custom;
    if (variant.preparation == Preparation.custom) {
      return variantName(variant, languageCode);
    }
    final label =
        spanish
            ? variant.preparation.labelEs(Gender.m)
            : variant.preparation.labelEn();
    return label[0].toUpperCase() + label.substring(1);
  }

  /// Full name of [variant] as logged: "Arroz frito", "Fried rice".
  String variantName(IngredientVariant variant, String languageCode) {
    final spanish = languageCode == 'es';
    final custom = spanish ? variant.nameEs : variant.nameEn;
    if (custom != null) return custom;
    if (variant.preparation == Preparation.custom) {
      return localizedName(languageCode);
    }
    if (spanish) return '$nameEs ${variant.preparation.labelEs(gender)}';
    final base = name[0].toLowerCase() + name.substring(1);
    return '${variant.preparation.labelEn()} $base';
  }

  List<double> portionsOf(IngredientVariant variant) {
    final own = variant.portionGrams;
    return own != null && own.length == 3 ? own : portionGrams;
  }

  /// [variant] as a row of the general nutrition table, so names logged from
  /// the picker resolve again later (portion presets, grounding).
  NutritionFood toNutritionFood(IngredientVariant variant) {
    final portions = portionsOf(variant);
    return NutritionFood(
      name: variantName(variant, 'en'),
      nameEs: variantName(variant, 'es'),
      kcalPer100g: variant.kcalPer100g,
      defaultGramsSmall: portions[0],
      defaultGramsMedium: portions[1],
      defaultGramsLarge: portions[2],
      category: category,
      source: source,
    );
  }
}
