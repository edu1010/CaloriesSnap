import '../../../data/repositories/nutrition_repository.dart';
import '../../../models/nutrition_food.dart';
import 'meal_analysis.dart';

/// A model-described item after its energy density was checked against the
/// local nutrition table.
class GroundedItem {
  const GroundedItem({
    required this.name,
    required this.grams,
    required this.kcalPer100g,
    this.match,
  });

  final String name;
  final double grams;
  final double kcalPer100g;

  /// Table entry that supplied [kcalPer100g]; null when the value is the
  /// model's own estimate.
  final NutritionFood? match;

  bool get fromDatabase => match != null;
}

/// Replaces the model's kcal/100 g by the local table's whenever the item can
/// be identified there. A 1-2 B model names food far better than it recalls
/// numbers, so the table is the source of truth and the model is the fallback.
class NutritionGrounding {
  NutritionGrounding(this._repository);

  static const double minGrams = 5;
  static const double maxGrams = 2000;
  static const double maxKcalPer100g = 900;

  /// Used only when neither the table nor the model provides a usable value.
  static const double unknownKcalPer100g = 150;
  static const double unknownGrams = 150;

  /// Share of the item's meaningful words a table entry must explain.
  static const double _minCoverage = 0.5;

  final NutritionRepository _repository;
  List<_Entry>? _entries;

  GroundedItem ground(
    AnalyzedItem item, {
    required String languageCode,
    String? dishName,
  }) {
    final match =
        _find(item.name, languageCode) ??
        (item.nameEn == null ? null : _find(item.nameEn!, 'en')) ??
        (dishName == null ? null : _find(dishName, languageCode));

    final modelKcal = item.kcalPer100g;
    final kcal =
        match?.kcalPer100g ??
        // Zero is what a model writes when it does not know; real zero-energy
        // items (water, tea) are in the table.
        (modelKcal != null && modelKcal > 0 && modelKcal <= maxKcalPer100g
            ? modelKcal
            : unknownKcalPer100g);

    final modelGrams = item.grams;
    final grams =
        modelGrams != null && modelGrams > 0
            ? modelGrams.clamp(minGrams, maxGrams).toDouble()
            : match?.defaultGramsMedium ?? unknownGrams;

    return GroundedItem(
      name: _displayName(item.name),
      grams: grams.roundToDouble(),
      kcalPer100g: kcal,
      match: match,
    );
  }

  NutritionFood? _find(String query, String languageCode) {
    final spanish = languageCode == 'es';
    final entries = _entries ??= _repository.foods.map(_Entry.new).toList();
    final key = _key(query);
    if (key.isEmpty) return null;

    // Exact name, in the query's language first: "tortilla" is an omelette in
    // Spanish and a flatbread in English.
    for (final inQueryLanguage in const <bool>[true, false]) {
      for (final entry in entries) {
        final useSpanish = spanish == inQueryLanguage;
        if ((useSpanish ? entry.keyEs : entry.keyEn) == key) return entry.food;
      }
    }

    final tokens = _tokens(query);
    if (tokens.isEmpty) return null;
    final density = tokens.intersection(_densityWords);
    NutritionFood? best;
    var bestScore = 0.0;
    for (final inQueryLanguage in const <bool>[true, false]) {
      for (final entry in entries) {
        final useSpanish = spanish == inQueryLanguage;
        final candidate = useSpanish ? entry.tokensEs : entry.tokensEn;
        if (candidate.isEmpty || !tokens.containsAll(candidate)) continue;
        // "fried chicken" must not take plain chicken's energy density.
        if (!candidate.containsAll(density)) continue;
        final score = candidate.length / tokens.length;
        if (score > bestScore) {
          bestScore = score;
          best = entry.food;
        }
      }
      if (best != null && bestScore >= _minCoverage) return best;
    }
    return null;
  }

  static String _displayName(String name) {
    var text = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.length > 60) text = text.substring(0, 60).trimRight();
    return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
  }

  static String _key(String value) => _words(value).join(' ');

  static Iterable<String> _words(String value) {
    var text = value.toLowerCase();
    _accents.forEach((accented, plain) {
      text = text.replaceAll(accented, plain);
    });
    return text.split(RegExp(r'[^a-z0-9]+')).where((word) => word.isNotEmpty);
  }

  /// Meaningful, lightly stemmed words: no articles or prepositions, and no
  /// words that describe a default preparation without changing the energy
  /// density much ("cooked", "a la plancha").
  static Set<String> _tokens(String value) {
    return _words(value)
        .where((word) => !_stopWords.contains(word))
        .map(_stem)
        .where((word) => !_neutralWords.contains(word))
        .toSet();
  }

  static String _stem(String word) {
    var stem = word;
    if (stem.length > 4 && stem.endsWith('ies')) {
      return '${stem.substring(0, stem.length - 3)}y';
    }
    if (stem.length > 3 && stem.endsWith('s')) {
      stem = stem.substring(0, stem.length - 1);
    }
    if (stem.length > 4 && stem.endsWith('e')) {
      stem = stem.substring(0, stem.length - 1);
    }
    return stem;
  }

  static const Map<String, String> _accents = <String, String>{
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
    'ñ': 'n', 'ç': 'c',
  };

  static const Set<String> _stopWords = <String>{
    'a', 'al', 'con', 'de', 'del', 'el', 'en', 'la', 'las', 'los', 'o', 'y',
    'un', 'una', 'and', 'in', 'of', 'on', 'or', 'the', 'with', 'style',
  };

  // Stored stemmed, as produced by [_stem].
  static final Set<String> _neutralWords =
      <String>{
        'cooked', 'boiled', 'steamed', 'plain', 'raw', 'grilled', 'roasted',
        'baked', 'sliced', 'slice', 'piece', 'white', 'homemade', 'generic',
        'cocido', 'cocida', 'hervido', 'hervida', 'vapor', 'natural', 'crudo',
        'cruda', 'plancha', 'asado', 'asada', 'horno', 'loncha', 'trozo',
        'blanco', 'blanca', 'casero', 'casera', 'generica', 'generico',
      }.map(_stem).toSet();

  // Preparations that change energy density enough that both sides must agree.
  static final Set<String> _densityWords =
      <String>{
        'fried', 'breaded', 'battered', 'dry', 'dried', 'chips', 'cured',
        'frito', 'frita', 'empanado', 'empanada', 'rebozado', 'rebozada',
        'seco', 'seca', 'curado', 'curada',
      }.map(_stem).toSet();
}

class _Entry {
  _Entry(this.food)
    : keyEn = NutritionGrounding._key(food.name),
      keyEs = NutritionGrounding._key(food.nameEs ?? ''),
      tokensEn = NutritionGrounding._tokens(food.name),
      tokensEs = NutritionGrounding._tokens(food.nameEs ?? '');

  final NutritionFood food;
  final String keyEn;
  final String keyEs;
  final Set<String> tokensEn;
  final Set<String> tokensEs;
}
