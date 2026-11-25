part of 'food_search.dart';

/// Unit the user wrote next to a food in the description.
enum FoodUnit {
  gram,
  kilogram,
  milliliter,
  centiliter,
  liter,

  /// A countable item: "2 huevos", "un plátano", "un filete de merluza".
  piece,

  /// "rebanada", "loncha", "rodaja", "tostada".
  slice,

  /// "onza" of chocolate.
  square,
  tablespoon,
  teaspoon,
  cup,
  glass,
  bowl,

  /// "plato", "ración", "porción", "trozo": the food's own portion presets.
  serving,
  can,
  sachet,
  handful,
}

/// The amount the user wrote for one food: "2", "1,5 kg", "una cucharadita".
class FoodQuantity {
  const FoodQuantity({
    required this.amount,
    required this.unit,
    required this.text,
    this.amountImplied = false,
    this.weighedRaw = false,
  });

  /// How many [unit]s: 2 for "2 huevos", 1.5 for "1,5 kg", 0.5 for "medio".
  final double amount;
  final FoodUnit unit;

  /// The words that expressed it, normalized ("1,5 kg", "dos", "media docena").
  final String text;

  /// True when no number was written and [amount] was inferred from the
  /// unit itself: "cucharadita de aceite" (1), "rebanadas de pan" (2).
  final bool amountImplied;

  /// The weight was stated raw/dry ("80 g de arroz en crudo").
  final bool weighedRaw;

  /// Grams or kilograms: the weight is what the user typed, not a guess.
  bool get isExactWeight => unit == FoodUnit.gram || unit == FoodUnit.kilogram;

  @override
  String toString() => 'FoodQuantity($amount ${unit.name}, "$text")';
}

class _Token {
  const _Token(this.word, [this.number]);

  /// Lower-case, accent-free word; digits as typed for numbers ("1,5").
  final String word;
  final double? number;
}

/// Like [foodWords] but keeps decimals ("1,5", "0.5") and fractions ("1/2")
/// as single number tokens.
List<_Token> _tokenizeDescription(String text) {
  final value = text
      .toLowerCase()
      .replaceAll('½', ' 1/2 ')
      .replaceAll('¼', ' 1/4 ')
      .replaceAll('¾', ' 3/4 ');
  final tokens = <_Token>[];
  final pattern = RegExp(r'(\d+(?:[.,]\d+)?)(?:\s*/\s*(\d+))?');
  var last = 0;
  void words(String segment) {
    for (final word in foodWords(segment)) {
      tokens.add(_Token(word));
    }
  }

  for (final match in pattern.allMatches(value)) {
    words(value.substring(last, match.start));
    var number = _parseNumber(match.group(1)!);
    final denominator = match.group(2);
    if (denominator != null) {
      final d = double.parse(denominator);
      number = d == 0 ? 0 : number / d;
    }
    tokens.add(_Token(match.group(0)!.replaceAll(RegExp(r'\s+'), ''), number));
    last = match.end;
  }
  words(value.substring(last));
  return tokens;
}

double _parseNumber(String text) {
  // "1.500" is a thousands separator in Spanish; "1,5" and "1.5" decimals.
  if (RegExp(r'^\d{1,3}\.\d{3}$').hasMatch(text)) {
    return double.parse(text.replaceAll('.', ''));
  }
  return double.parse(text.replaceAll(',', '.'));
}

enum _Size { small, medium, large, heaped }

enum _AmountKind { number, article, collective, indefinite }

class _Amount {
  const _Amount(this.value, this.start, this.kind);
  final double value;
  final int start;
  final _AmountKind kind;
}

class _ParsedQuantity {
  const _ParsedQuantity({
    required this.amount,
    required this.unit,
    required this.indexes,
    this.size,
    this.implied = false,
    this.articleOnly = false,
  });

  final double amount;
  final FoodUnit unit;

  /// Token positions that expressed the quantity (without "de").
  final List<int> indexes;
  final _Size? size;
  final bool implied;

  /// Only "un"/"una" before the food: a quantity if the food is countable
  /// ("un huevo"), otherwise just an article ("una paella").
  final bool articleOnly;

  int get first => indexes.reduce((a, b) => a < b ? a : b);

  _ParsedQuantity withSize(_Size value) => _ParsedQuantity(
    amount: amount,
    unit: unit,
    indexes: indexes,
    size: value,
    implied: implied,
    articleOnly: articleOnly,
  );
}

class _QuantityParser {
  const _QuantityParser(this.tokens);

  final List<_Token> tokens;

  String _word(int i) => tokens[i].word;

  /// "200 g de", "dos", "una cucharadita de", "rebanadas de", "medio kilo
  /// de", "un par de" right before the food at [start], not reaching below
  /// [lo].
  _ParsedQuantity? before(int start, int lo) {
    var p = start - 1;
    bool ok(int i) => i >= lo && i < tokens.length;
    final used = <int>[];

    var hadOf = false;
    if (ok(p) && _ofWords.contains(_word(p))) {
      hadOf = true;
      p--;
    }
    _Size? size;
    if (ok(p) && _sizeWords.containsKey(_word(p))) {
      size = _sizeWords[_word(p)];
      used.add(p);
      p--;
    }
    FoodUnit? unit;
    String? unitWord;
    if (ok(p) && _unitWords.containsKey(_word(p))) {
      unit = _unitWords[_word(p)];
      unitWord = _word(p);
      used.add(p);
      p--;
      // "una gran cucharada"
      if (size == null && ok(p) && _sizeWords.containsKey(_word(p))) {
        size = _sizeWords[_word(p)];
        used.add(p);
        p--;
      }
    }

    final amount = _amountEndingAt(p, lo);
    if (amount == null) {
      // A household unit alone still says how much: "cucharadita de aceite"
      // is one, "rebanadas de pan" a couple. Bare "gramos de" says nothing.
      if (unit == null || _metricUnits.contains(unit)) return null;
      return _ParsedQuantity(
        amount: unitWord!.endsWith('s') ? 2 : 1,
        unit: unit,
        indexes: used,
        size: size,
        implied: true,
      );
    }
    if (unit == null && hadOf && amount.kind != _AmountKind.collective) {
      return null;
    }
    if (unit == null && amount.kind == _AmountKind.indefinite) return null;
    for (var i = amount.start; i <= p; i++) {
      used.add(i);
    }
    return _ParsedQuantity(
      amount: amount.value,
      unit: unit ?? FoodUnit.piece,
      indexes: used,
      size: size,
      implied: amount.kind == _AmountKind.indefinite,
      articleOnly: unit == null && amount.kind == _AmountKind.article,
    );
  }

  /// "arroz hervido 150 g", "huevos x2", "tostadas 2" right after the food
  /// ending at [end], not reaching [hi].
  _ParsedQuantity? after(int end, int hi) {
    var q = end;
    var skipped = 0;
    while (q < hi &&
        skipped < 4 &&
        (_articleWords.contains(_word(q)) ||
            FoodSearch._preparationWords.containsKey(
              singularFoodWord(_word(q)),
            ))) {
      q++;
      skipped++;
    }
    if (q >= hi) return null;
    if (_word(q) == 'x' && q + 1 < hi && tokens[q + 1].number != null) {
      return _ParsedQuantity(
        amount: tokens[q + 1].number!,
        unit: FoodUnit.piece,
        indexes: <int>[q, q + 1],
      );
    }
    final number = tokens[q].number;
    if (number == null || number <= 0) return null;
    var r = q + 1;
    FoodUnit? unit;
    if (r < hi && _unitWords.containsKey(_word(r))) {
      unit = _unitWords[_word(r)];
      r++;
    }
    // "pan 60 g de queso": the weight belongs to what follows.
    if (r < tokens.length && _ofWords.contains(_word(r))) return null;
    if (unit == null &&
        r < tokens.length &&
        !FoodSearch._connectors.contains(_word(r)) &&
        !_sizeWords.containsKey(_word(r)) &&
        !_rawWords.contains(_word(r)) &&
        _word(r) != 'en') {
      return null;
    }
    return _ParsedQuantity(
      amount: number,
      unit: unit ?? FoodUnit.piece,
      indexes: <int>[for (var i = q; i < r; i++) i],
    );
  }

  _Amount? _amountEndingAt(int p, int lo) {
    if (p < lo) return null;
    final token = tokens[p];
    final word = token.word;
    double? value;
    var start = p;
    var kind = _AmountKind.number;

    double? numberAt(int i) {
      if (i < lo) return null;
      return tokens[i].number ?? _numberWords[_word(i)];
    }

    if (token.number != null) {
      value = token.number;
    } else if (_articleWords.contains(word) && word.startsWith('u')) {
      value = 1;
      kind = _AmountKind.article;
    } else if (_numberWords.containsKey(word)) {
      value = _numberWords[word];
    } else if (word == 'cuarto' || word == 'tercio') {
      value = word == 'cuarto' ? 0.25 : 1 / 3;
      if (p - 1 >= lo && _isOne(_word(p - 1))) start = p - 1;
    } else if (word == 'cuartos' || word == 'tercios') {
      final n = numberAt(p - 1);
      if (n == null) return null;
      value = n * (word == 'cuartos' ? 0.25 : 1 / 3);
      start = p - 1;
    } else if (word == 'par' || word == 'pares') {
      kind = _AmountKind.collective;
      final n = numberAt(p - 1);
      value = 2 * (n ?? 1);
      if (n != null) start = p - 1;
    } else if (word == 'docena' || word == 'docenas') {
      kind = _AmountKind.collective;
      final n = numberAt(p - 1);
      value = 12 * (n ?? 1);
      if (n != null) start = p - 1;
    } else if (_indefiniteWords.contains(word)) {
      value = 2;
      kind = _AmountKind.indefinite;
    }
    if (value == null || value <= 0) return null;

    // "1 y media cucharadas", "dos y medio kilos"
    if ((word == 'medio' || word == 'media') &&
        start - 2 >= lo &&
        _word(start - 1) == 'y') {
      final whole = numberAt(start - 2);
      if (whole != null && whole >= 1) {
        value += whole;
        start -= 2;
      }
    }
    return _Amount(value, start, kind);
  }

  static bool _isOne(String word) =>
      word == 'un' || word == 'una' || word == 'uno' || word == '1';

  /// Whether the weight was stated raw: "en crudo", "peso crudo", "en seco".
  bool rawQualifierIn(int from, int to) {
    for (var i = from; i < to && i < tokens.length; i++) {
      final word = _word(i);
      if (_rawWords.contains(word)) return true;
      if ((word == 'seco' || word == 'seca') &&
          i > 0 &&
          (_word(i - 1) == 'en' || _word(i - 1) == 'peso')) {
        return true;
      }
    }
    return false;
  }

  /// First size word after the food: "2 huevos grandes".
  _Size? sizeAfter(int end, int hi) {
    for (var i = end; i < hi && i < end + 3; i++) {
      final size = _sizeWords[_word(i)];
      if (size != null) return size;
      if (FoodSearch._connectors.contains(_word(i))) return null;
    }
    return null;
  }

  static const Set<String> _ofWords = <String>{'de', 'del', 'of'};
  static const Set<String> _articleWords = <String>{
    'un',
    'una',
    'uno',
    'el',
    'la',
    'al',
    'a',
  };
  static const Set<String> _indefiniteWords = <String>{
    'unos',
    'unas',
    'algunos',
    'algunas',
    'some',
  };
  static const Set<String> _rawWords = <String>{
    'crudo',
    'cruda',
    'crudos',
    'crudas',
    'raw',
    'uncooked',
  };

  static const Map<String, double> _numberWords = <String, double>{
    'medio': 0.5,
    'media': 0.5,
    'half': 0.5,
    'dos': 2,
    'tres': 3,
    'cuatro': 4,
    'cinco': 5,
    'seis': 6,
    'siete': 7,
    'ocho': 8,
    'nueve': 9,
    'diez': 10,
    'once': 11,
    'doce': 12,
    'quince': 15,
    'veinte': 20,
    'treinta': 30,
    'cuarenta': 40,
    'cincuenta': 50,
    'cien': 100,
    'doscientos': 200,
    'doscientas': 200,
    'trescientos': 300,
    'trescientas': 300,
    'cuatrocientos': 400,
    'cuatrocientas': 400,
    'quinientos': 500,
    'quinientas': 500,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
  };

  static const Map<String, _Size> _sizeWords = <String, _Size>{
    'pequeno': _Size.small,
    'pequena': _Size.small,
    'pequenos': _Size.small,
    'pequenas': _Size.small,
    'small': _Size.small,
    'mediano': _Size.medium,
    'mediana': _Size.medium,
    'medianos': _Size.medium,
    'medianas': _Size.medium,
    'medium': _Size.medium,
    'grande': _Size.large,
    'grandes': _Size.large,
    'gran': _Size.large,
    'big': _Size.large,
    'large': _Size.large,
    'colmada': _Size.heaped,
    'colmadas': _Size.heaped,
    'colmado': _Size.heaped,
    'colmados': _Size.heaped,
    'heaped': _Size.heaped,
  };

  static const Set<FoodUnit> _metricUnits = <FoodUnit>{
    FoodUnit.gram,
    FoodUnit.kilogram,
    FoodUnit.milliliter,
    FoodUnit.centiliter,
    FoodUnit.liter,
  };

  static const Map<String, FoodUnit> _unitWords = <String, FoodUnit>{
    'g': FoodUnit.gram,
    'gr': FoodUnit.gram,
    'grs': FoodUnit.gram,
    'gramo': FoodUnit.gram,
    'gramos': FoodUnit.gram,
    'gram': FoodUnit.gram,
    'grams': FoodUnit.gram,
    'kg': FoodUnit.kilogram,
    'kgs': FoodUnit.kilogram,
    'kilo': FoodUnit.kilogram,
    'kilos': FoodUnit.kilogram,
    'kilogramo': FoodUnit.kilogram,
    'kilogramos': FoodUnit.kilogram,
    'ml': FoodUnit.milliliter,
    'cc': FoodUnit.milliliter,
    'mililitro': FoodUnit.milliliter,
    'mililitros': FoodUnit.milliliter,
    'cl': FoodUnit.centiliter,
    'centilitro': FoodUnit.centiliter,
    'centilitros': FoodUnit.centiliter,
    'l': FoodUnit.liter,
    'litro': FoodUnit.liter,
    'litros': FoodUnit.liter,
    'unidad': FoodUnit.piece,
    'unidades': FoodUnit.piece,
    'pieza': FoodUnit.piece,
    'piezas': FoodUnit.piece,
    'filete': FoodUnit.piece,
    'filetes': FoodUnit.piece,
    'bola': FoodUnit.piece,
    'bolas': FoodUnit.piece,
    'rebanada': FoodUnit.slice,
    'rebanadas': FoodUnit.slice,
    'loncha': FoodUnit.slice,
    'lonchas': FoodUnit.slice,
    'lonchita': FoodUnit.slice,
    'lonchitas': FoodUnit.slice,
    'rodaja': FoodUnit.slice,
    'rodajas': FoodUnit.slice,
    'raja': FoodUnit.slice,
    'rajas': FoodUnit.slice,
    'tajada': FoodUnit.slice,
    'tajadas': FoodUnit.slice,
    'tostada': FoodUnit.slice,
    'tostadas': FoodUnit.slice,
    'slice': FoodUnit.slice,
    'slices': FoodUnit.slice,
    'onza': FoodUnit.square,
    'onzas': FoodUnit.square,
    'cucharada': FoodUnit.tablespoon,
    'cucharadas': FoodUnit.tablespoon,
    'cuchara': FoodUnit.tablespoon,
    'cucharas': FoodUnit.tablespoon,
    'cda': FoodUnit.tablespoon,
    'cdas': FoodUnit.tablespoon,
    'tbsp': FoodUnit.tablespoon,
    'cucharadita': FoodUnit.teaspoon,
    'cucharaditas': FoodUnit.teaspoon,
    'cucharilla': FoodUnit.teaspoon,
    'cucharillas': FoodUnit.teaspoon,
    'cdta': FoodUnit.teaspoon,
    'cdtas': FoodUnit.teaspoon,
    'cdita': FoodUnit.teaspoon,
    'tsp': FoodUnit.teaspoon,
    'taza': FoodUnit.cup,
    'tazas': FoodUnit.cup,
    'cup': FoodUnit.cup,
    'cups': FoodUnit.cup,
    'vaso': FoodUnit.glass,
    'vasos': FoodUnit.glass,
    'glass': FoodUnit.glass,
    'glasses': FoodUnit.glass,
    'bol': FoodUnit.bowl,
    'boles': FoodUnit.bowl,
    'bols': FoodUnit.bowl,
    'cuenco': FoodUnit.bowl,
    'cuencos': FoodUnit.bowl,
    'tazon': FoodUnit.bowl,
    'tazones': FoodUnit.bowl,
    'bowl': FoodUnit.bowl,
    'bowls': FoodUnit.bowl,
    'plato': FoodUnit.serving,
    'platos': FoodUnit.serving,
    'racion': FoodUnit.serving,
    'raciones': FoodUnit.serving,
    'porcion': FoodUnit.serving,
    'porciones': FoodUnit.serving,
    'trozo': FoodUnit.serving,
    'trozos': FoodUnit.serving,
    'serving': FoodUnit.serving,
    'servings': FoodUnit.serving,
    'portion': FoodUnit.serving,
    'portions': FoodUnit.serving,
    'lata': FoodUnit.can,
    'latas': FoodUnit.can,
    'latita': FoodUnit.can,
    'latitas': FoodUnit.can,
    'sobre': FoodUnit.sachet,
    'sobres': FoodUnit.sachet,
    'sobrecito': FoodUnit.sachet,
    'sobrecitos': FoodUnit.sachet,
    'punado': FoodUnit.handful,
    'punados': FoodUnit.handful,
    'handful': FoodUnit.handful,
    'handfuls': FoodUnit.handful,
  };
}

/// Grams for [quantity] of [ingredient]'s variant [variantIndex], or null when
/// the unit has no sensible weight for that food ("2 tazas de arroz").
double? _gramsFor(
  Ingredient ingredient,
  int variantIndex,
  List<String> phraseWords,
  _ParsedQuantity quantity,
) {
  final amount = quantity.amount;
  final density = _densities[ingredient.id];
  double sized(double grams) => grams * _multiplier(quantity.size);

  double? specific(FoodUnit unit) {
    final variant = ingredient.variants[variantIndex];
    for (final key in <String>[
      '${ingredient.id}:${phraseWords.join(' ')}',
      '${ingredient.id}@${normalizeFoodText(ingredient.variantName(variant, 'es'))}',
      ingredient.id,
    ]) {
      final grams = _unitGrams[key]?[unit];
      if (grams != null) return grams;
    }
    return null;
  }

  double serving() {
    final portions = ingredient.portionsOf(ingredient.variants[variantIndex]);
    final index = switch (quantity.size) {
      _Size.small => 0,
      _Size.large || _Size.heaped => 2,
      _ => 1,
    };
    return portions[index] * amount;
  }

  switch (quantity.unit) {
    case FoodUnit.gram:
      return amount;
    case FoodUnit.kilogram:
      return amount * 1000;
    case FoodUnit.milliliter:
      return density == null ? null : amount * density;
    case FoodUnit.centiliter:
      return density == null ? null : amount * 10 * density;
    case FoodUnit.liter:
      return density == null ? null : amount * 1000 * density;
    case FoodUnit.serving:
      return serving();
    case FoodUnit.bowl:
      return density == null ? null : sized(amount * 300 * density);
    case FoodUnit.tablespoon:
    case FoodUnit.teaspoon:
    case FoodUnit.cup:
    case FoodUnit.glass:
      final own = specific(quantity.unit);
      if (own != null) return sized(amount * own);
      if (density == null) return null;
      return sized(amount * _millilitres[quantity.unit]! * density);
    case FoodUnit.piece:
    case FoodUnit.slice:
    case FoodUnit.square:
    case FoodUnit.can:
    case FoodUnit.sachet:
    case FoodUnit.handful:
      final own = specific(quantity.unit);
      return own == null ? null : sized(amount * own);
  }
}

double _multiplier(_Size? size) => switch (size) {
  _Size.small => 0.75,
  _Size.large => 1.3,
  _Size.heaped => 1.5,
  _ => 1.0,
};

double _roundEstimate(double grams) =>
    grams >= 10 ? grams.roundToDouble() : (grams * 10).round() / 10;

const Map<FoodUnit, double> _millilitres = <FoodUnit, double>{
  FoodUnit.tablespoon: 15,
  FoodUnit.teaspoon: 5,
  FoodUnit.cup: 250,
  FoodUnit.glass: 200,
};

/// g/ml of the foods measured by volume.
const Map<String, double> _densities = <String, double>{
  'milk': 1.03,
  'olive_oil': 0.92,
  'sunflower_oil': 0.92,
  'cream': 1.0,
  'honey': 1.42,
  'mayonnaise': 0.95,
  'ketchup': 1.15,
};

/// Curated edible grams of one unit of a food. Keys: `id`, `id@variant name`
/// (Spanish, normalized) or `id:matched words` (singular), most specific
/// first.
const Map<String, Map<FoodUnit, double>>
_unitGrams = <String, Map<FoodUnit, double>>{
  'egg': {FoodUnit.piece: 60},
  'apple': {FoodUnit.piece: 180},
  'banana': {FoodUnit.piece: 120},
  'orange': {FoodUnit.piece: 150},
  'pear': {FoodUnit.piece: 170},
  'peach': {FoodUnit.piece: 150},
  'kiwi': {FoodUnit.piece: 75},
  'mango': {FoodUnit.piece: 250},
  'strawberries': {FoodUnit.piece: 12},
  'grapes': {FoodUnit.piece: 5},
  'melon': {FoodUnit.slice: 200},
  'watermelon': {FoodUnit.slice: 250},
  'pineapple': {FoodUnit.slice: 80},
  'tomato': {FoodUnit.piece: 120, FoodUnit.slice: 15, FoodUnit.tablespoon: 15},
  'onion': {FoodUnit.piece: 110},
  'pepper': {FoodUnit.piece: 150},
  'zucchini': {FoodUnit.piece: 250},
  'eggplant': {FoodUnit.piece: 300},
  'carrot': {FoodUnit.piece: 70},
  'cucumber': {FoodUnit.piece: 200},
  'avocado': {FoodUnit.piece: 140},
  'potato': {FoodUnit.piece: 150},
  'sweet_potato': {FoodUnit.piece: 200},
  'mushrooms': {FoodUnit.piece: 15},
  'asparagus': {FoodUnit.piece: 15},
  'olives': {FoodUnit.piece: 4, FoodUnit.handful: 20},
  'almonds': {FoodUnit.piece: 1.2, FoodUnit.handful: 25},
  'walnuts': {FoodUnit.piece: 5, FoodUnit.handful: 25},
  'peanuts': {FoodUnit.piece: 1, FoodUnit.handful: 30},
  'bread': {FoodUnit.slice: 30},
  'bread:tostada': {FoodUnit.piece: 30, FoodUnit.slice: 30},
  'bread:barra': {FoodUnit.piece: 250},
  'bread:baguette': {FoodUnit.piece: 250},
  'bread@pan de molde': {FoodUnit.piece: 25, FoodUnit.slice: 25},
  'bread@pan tostado': {FoodUnit.piece: 25, FoodUnit.slice: 25},
  'oats': {FoodUnit.tablespoon: 8, FoodUnit.cup: 80},
  'chicken_breast': {FoodUnit.piece: 150},
  'chicken_thigh': {FoodUnit.piece: 100},
  'turkey_breast': {FoodUnit.slice: 10},
  'beef_steak': {FoodUnit.piece: 150},
  'burger_patty': {FoodUnit.piece: 120},
  'pork_loin': {FoodUnit.piece: 100},
  'lamb_chops': {FoodUnit.piece: 50},
  'sausage': {FoodUnit.piece: 50},
  'chorizo': {FoodUnit.slice: 5},
  'bacon': {FoodUnit.slice: 12},
  'serrano_ham': {FoodUnit.slice: 15},
  'cooked_ham': {FoodUnit.slice: 20},
  'salmon': {FoodUnit.piece: 150},
  'hake': {FoodUnit.piece: 150},
  'cod': {FoodUnit.piece: 150},
  'sea_bream': {FoodUnit.piece: 250},
  'sardines': {FoodUnit.piece: 50, FoodUnit.can: 60},
  'tuna': {FoodUnit.can: 60},
  'corn': {FoodUnit.can: 140},
  'prawns': {FoodUnit.piece: 12},
  'mussels': {FoodUnit.piece: 8},
  'yogurt': {FoodUnit.piece: 125},
  'cheese': {FoodUnit.slice: 20, FoodUnit.tablespoon: 6},
  'cheese@mozzarella': {FoodUnit.piece: 125},
  'butter': {FoodUnit.tablespoon: 14, FoodUnit.teaspoon: 5},
  'sugar': {FoodUnit.tablespoon: 12, FoodUnit.teaspoon: 4, FoodUnit.sachet: 8},
  'chocolate': {FoodUnit.square: 6},
};
