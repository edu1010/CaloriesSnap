import '../../core/utils/food_text.dart';
import '../../models/ingredient.dart';
import '../../models/nutrition_food.dart';

part 'food_search_quantity.dart';

/// One search result: an ingredient (or a dish wrapped as one) and, when the
/// query named a preparation ("arroz frito"), that variant.
class FoodSearchHit {
  const FoodSearchHit(this.ingredient, {this.variantIndex, this.score = 0});

  final Ingredient ingredient;
  final int? variantIndex;
  final double score;

  int get selectedIndex => variantIndex ?? ingredient.defaultIndex;
  IngredientVariant get variant => ingredient.variants[selectedIndex];
}

/// A food mentioned in the user's description of the meal.
class FoodSuggestion {
  const FoodSuggestion(
    this.ingredient,
    this.variantIndex, {
    this.grams,
    this.quantity,
    this.gramsEstimated = false,
    this.preparationSpecified = false,
  });

  final Ingredient ingredient;
  final int variantIndex;

  /// Grams for what the user wrote next to it: exactly "200 g de arroz", or
  /// converted from "2 huevos", "una cucharadita de aceite" (see
  /// [gramsEstimated]). Null when nothing was written or the unit has no
  /// known weight for this food (see [hasUnresolvedQuantity]).
  final double? grams;

  /// The amount as written, when there was one.
  final FoodQuantity? quantity;

  /// True when [grams] was converted from a household unit, a volume or a
  /// raw weight rather than typed in g/kg.
  final bool gramsEstimated;

  /// Whether the description explicitly identifies the preparation.
  final bool preparationSpecified;

  /// The user wrote an amount ("3 paellas", "2 tazas de arroz") that could
  /// not be turned into grams. It must be asked for, not replaced by a
  /// default portion.
  bool get hasUnresolvedQuantity => quantity != null && grams == null;

  IngredientVariant get variant => ingredient.variants[variantIndex];
}

/// Searches the ingredient table (with its preparations) and the prepared
/// dishes of the general table.
class FoodSearch {
  FoodSearch({
    required List<Ingredient> ingredients,
    List<NutritionFood> dishes = const <NutritionFood>[],
  }) : ingredients = List<Ingredient>.unmodifiable(ingredients) {
    final variantNames = <String>{};
    for (final ingredient in ingredients) {
      _addPhrase(ingredient, ingredient.nameEs, primary: true);
      _addPhrase(ingredient, ingredient.name, primary: true);
      for (final alias in ingredient.aliases) {
        _addPhrase(ingredient, alias);
      }
      for (var i = 0; i < ingredient.variants.length; i++) {
        final variant = ingredient.variants[i];
        for (final language in const <String>['es', 'en']) {
          final name = ingredient.variantName(variant, language);
          variantNames.add(normalizeFoodText(name));
          _addPhrase(ingredient, name, variantIndex: i, primary: true);
        }
      }
    }
    // A dish named exactly like a variant ("Arroz frito") would only repeat
    // it without the other preparations.
    for (final dish in dishes) {
      final names = <String>[dish.name, if (dish.nameEs != null) dish.nameEs!];
      if (names.any((name) => variantNames.contains(normalizeFoodText(name)))) {
        continue;
      }
      final entry = Ingredient.fromDish(dish);
      for (final name in names) {
        if (!_addPreparationAlias(name)) _addPhrase(entry, name, primary: true);
      }
      for (final alias in dish.aliases) {
        _addPhrase(entry, alias);
      }
    }
  }

  final List<Ingredient> ingredients;
  final List<_Phrase> _phrases = <_Phrase>[];

  /// Names such as "arroz cocido" already have a matching ingredient and
  /// preparation ("arroz hervido"). Keep its portion choices in the draft.
  bool _addPreparationAlias(String name) {
    final words = foodWords(name).map(singularFoodWord).toList();
    if (words.length < 2) return false;
    final preparation = _preparationWords[words.last];
    if (preparation == null) return false;
    final baseName = words.sublist(0, words.length - 1);
    for (final phrase in _phrases) {
      if (phrase.ingredient.isDish || !_equals(phrase.words, baseName)) {
        continue;
      }
      final variantIndex = _variantFor(phrase.ingredient, preparation);
      if (variantIndex != null) {
        _addPhrase(
          phrase.ingredient,
          name,
          variantIndex: variantIndex,
          primary: true,
        );
        return true;
      }
    }
    return false;
  }

  void _addPhrase(
    Ingredient ingredient,
    String text, {
    int? variantIndex,
    bool primary = false,
  }) {
    final words = foodWords(text).map(singularFoodWord).toList();
    if (words.isEmpty) return;
    _phrases.add(
      _Phrase(
        ingredient: ingredient,
        words: words,
        variantIndex: variantIndex,
        primary: primary,
      ),
    );
  }

  /// Results for what the user is typing, best first. An empty query lists
  /// every ingredient alphabetically.
  List<FoodSearchHit> search(
    String query, {
    String languageCode = 'es',
    int limit = 40,
  }) {
    final queryWords = foodWords(query).map(singularFoodWord).toList();
    if (queryWords.isEmpty) {
      final sorted = List<Ingredient>.of(ingredients)..sort(
        (a, b) => normalizeFoodText(
          a.localizedName(languageCode),
        ).compareTo(normalizeFoodText(b.localizedName(languageCode))),
      );
      return sorted.take(limit).map(FoodSearchHit.new).toList();
    }

    final best = <String, FoodSearchHit>{};
    for (final phrase in _phrases) {
      var score = _score(queryWords, phrase.words);
      if (score <= 0) continue;
      if (!phrase.ingredient.isDish) score += 5;
      if (phrase.primary) score += 2;
      final id = phrase.ingredient.id;
      final previous = best[id];
      if (previous == null || score > previous.score) {
        best[id] = FoodSearchHit(
          phrase.ingredient,
          variantIndex: phrase.variantIndex,
          score: score,
        );
      }
    }
    final hits =
        best.values.toList()..sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          if (byScore != 0) return byScore;
          final aName = a.ingredient.localizedName(languageCode);
          final bName = b.ingredient.localizedName(languageCode);
          final byLength = aName.length.compareTo(bName.length);
          return byLength != 0 ? byLength : aName.compareTo(bName);
        });
    return hits.take(limit).toList();
  }

  static double _score(List<String> query, List<String> phrase) {
    if (_equals(query, phrase)) return 100;
    // Words typed in order from the start: "arr" -> "arroz", "arroz fr" ->
    // "arroz frito".
    if (query.length <= phrase.length) {
      var ordered = true;
      for (var i = 0; i < query.length; i++) {
        final last = i == query.length - 1;
        if (last ? !phrase[i].startsWith(query[i]) : phrase[i] != query[i]) {
          ordered = false;
          break;
        }
      }
      if (ordered) return 80.0 - (phrase.length - query.length);
    }
    if (query.every((q) => phrase.any((word) => word.startsWith(q)))) {
      return 60.0 - (phrase.length - query.length).clamp(0, 20);
    }
    final joined = phrase.join(' ');
    final typed = query.join(' ');
    if (typed.length >= 3 && joined.contains(typed)) return 40;
    return 0;
  }

  /// Foods named in a free-text description such as "arroz frito con pollo
  /// a la plancha y 200 g de ensalada". Longer names win over the words they
  /// contain ("pan con tomate" over "pan" and "tomate").
  ///
  /// Amounts are read before ("200 g de", "dos", "1,5 kg de", "una
  /// cucharadita de", "media docena de") or after the food ("arroz 150 g",
  /// "huevos x2"); see [FoodSuggestion.grams] and [FoodSuggestion.quantity].
  List<FoodSuggestion> suggestFromText(String text) {
    final tokens = _tokenizeDescription(text);
    final words = tokens.map((token) => singularFoodWord(token.word)).toList();
    if (words.isEmpty) return const <FoodSuggestion>[];

    final matches = <_Match>[];
    for (final phrase in _phrases) {
      final length = phrase.words.length;
      if (length == 1 && phrase.words.first.length < 3) continue;
      for (var start = 0; start + length <= words.length; start++) {
        if (length == 1 &&
            words[start] == 'burger' &&
            start + 1 < words.length &&
            words[start + 1] == 'king') {
          continue;
        }
        if (_equals(words.sublist(start, start + length), phrase.words)) {
          matches.add(_Match(phrase, start));
        }
      }
    }
    // An alias that is also a unit is the unit when another food follows:
    // "un filete de merluza", "dos tostadas de pan integral".
    final starts = matches.map((match) => match.start).toSet();
    matches.removeWhere((match) {
      final next = match.start + 2;
      final unit = _QuantityParser._unitWords[tokens[match.start].word];
      return match.phrase.words.length == 1 &&
          next < words.length &&
          _QuantityParser._ofWords.contains(words[next - 1]) &&
          starts.contains(next) &&
          unit != null &&
          (!match.phrase.primary ||
              (unit == FoodUnit.slice && words[next] == 'pan'));
    });
    matches.sort((a, b) {
      final byLength = b.phrase.words.length.compareTo(a.phrase.words.length);
      if (byLength != 0) return byLength;
      // Same length: ingredients carry preparations, dishes do not.
      final byKind = (a.phrase.ingredient.isDish ? 1 : 0).compareTo(
        b.phrase.ingredient.isDish ? 1 : 0,
      );
      if (byKind != 0) return byKind;
      // A name beats an alias: "pollo" is the chicken entry itself.
      final byPrimary = (a.phrase.primary ? 0 : 1).compareTo(
        b.phrase.primary ? 0 : 1,
      );
      if (byPrimary != 0) return byPrimary;
      return a.start.compareTo(b.start);
    });

    final taken = List<bool>.filled(words.length, false);
    final chosen = <_Match>[];
    for (final match in matches) {
      final end = match.start + match.phrase.words.length;
      if (taken.sublist(match.start, end).any((used) => used)) continue;
      for (var i = match.start; i < end; i++) {
        taken[i] = true;
      }
      chosen.add(match);
    }
    chosen.sort((a, b) => a.start.compareTo(b.start));

    // Amounts written before each food first, so "pollo 2 huevos" gives the
    // 2 to the eggs; then amounts after the foods that still have none.
    final parser = _QuantityParser(tokens);
    final quantities = List<_ParsedQuantity?>.filled(chosen.length, null);
    for (var i = 0; i < chosen.length; i++) {
      final lo = i == 0 ? 0 : _endOf(chosen[i - 1]);
      quantities[i] = parser.before(chosen[i].start, lo);
    }
    for (var i = 0; i < chosen.length; i++) {
      if (quantities[i] != null) continue;
      var hi = tokens.length;
      if (i + 1 < chosen.length) {
        hi = quantities[i + 1]?.first ?? chosen[i + 1].start;
      }
      quantities[i] = parser.after(_endOf(chosen[i]), hi);
    }

    final seen = <String>{};
    final suggestions = <FoodSuggestion>[];
    for (var i = 0; i < chosen.length; i++) {
      final match = chosen[i];
      final previousEnd = i == 0 ? 0 : _endOf(chosen[i - 1]);
      if (_isExcluded(words, previousEnd, match.start)) continue;
      final ingredient = match.phrase.ingredient;
      if (!seen.add(ingredient.id)) continue;
      final end = _endOf(match);
      final near =
          match.phrase.variantIndex == null
              ? _preparationNear(ingredient, words, match.start, end)
              : null;
      var variantIndex =
          match.phrase.variantIndex ?? near ?? ingredient.defaultIndex;
      var explicitPreparation =
          match.phrase.variantIndex != null || near != null;

      var parsed = quantities[i];
      if (parsed == null) {
        suggestions.add(
          FoodSuggestion(
            ingredient,
            variantIndex,
            preparationSpecified: explicitPreparation,
          ),
        );
        continue;
      }
      final hi =
          i + 1 < chosen.length
              ? (quantities[i + 1]?.first ?? chosen[i + 1].start)
              : tokens.length;
      if (parsed.size == null) {
        final size = parser.sizeAfter(end, hi);
        if (size != null) parsed = parsed.withSize(size);
      }
      final phraseWords = match.phrase.words;
      var grams = _gramsFor(ingredient, variantIndex, phraseWords, parsed);
      // "una paella": an article, not an amount, when the food is not
      // countable.
      if (parsed.articleOnly &&
          grams == null &&
          ingredient.dish?.brand == null) {
        suggestions.add(
          FoodSuggestion(
            ingredient,
            variantIndex,
            preparationSpecified: explicitPreparation,
          ),
        );
        continue;
      }
      final exact =
          parsed.unit == FoodUnit.gram || parsed.unit == FoodUnit.kilogram;
      final estimated = grams != null && !exact;

      // Match the nutrient density to the state in which the food was weighed.
      var scopeEnd = end;
      while (scopeEnd < hi &&
          scopeEnd < end + 6 &&
          !_connectors.contains(words[scopeEnd])) {
        scopeEnd++;
      }
      final scopeStart = parsed.first < match.start ? parsed.first : end;
      final weighedRaw = parser.rawQualifierIn(scopeStart, scopeEnd);
      if (weighedRaw && exact) {
        final rawIndex = ingredient.variants.indexWhere(
          (variant) =>
              variant.preparation == Preparation.raw ||
              variant.preparation == Preparation.dried,
        );
        if (rawIndex >= 0) {
          variantIndex = rawIndex;
          explicitPreparation = true;
        }
      }
      if (grams != null && estimated) grams = _roundEstimate(grams);

      suggestions.add(
        FoodSuggestion(
          ingredient,
          variantIndex,
          grams: grams,
          gramsEstimated: estimated,
          preparationSpecified: explicitPreparation,
          quantity: FoodQuantity(
            amount: parsed.amount,
            unit: parsed.unit,
            text: (List<int>.of(parsed.indexes)
              ..sort()).map((index) => tokens[index].word).join(' '),
            amountImplied: parsed.implied,
            weighedRaw: weighedRaw,
          ),
        ),
      );
    }
    return suggestions;
  }

  static int _endOf(_Match match) => match.start + match.phrase.words.length;

  static bool _isExcluded(List<String> words, int from, int start) {
    for (var i = start - 1; i >= from; i--) {
      final word = words[i];
      if (_exclusions.contains(word)) return true;
      if (word == 'lleva' && i > from && words[i - 1] == 'no') return true;
      if (_connectors.contains(word)) return false;
    }
    return false;
  }

  /// A preparation word right after the food ("pollo a la plancha") or right
  /// before it ("fried chicken").
  static int? _preparationNear(
    Ingredient ingredient,
    List<String> words,
    int start,
    int end,
  ) {
    final window = <String>[
      if (start > 0) words[start - 1],
      for (var i = end; i < words.length && i < end + 4; i++)
        if (!_connectors.contains(words[i])) words[i] else '|',
    ];
    // Stop at the first connector after the food: "arroz con pollo frito"
    // fries the chicken, not the rice.
    final cut = window.indexOf('|');
    final scoped = cut < 0 ? window : window.sublist(0, cut);
    for (final word in scoped) {
      final prep = _preparationWords[word];
      if (prep == null) continue;
      final index = _variantFor(ingredient, prep);
      if (index != null) return index;
    }
    return null;
  }

  static int? _variantFor(Ingredient ingredient, Preparation prep) {
    for (final candidate in <Preparation>[prep, ...?_equivalents[prep]]) {
      final index = ingredient.variants.indexWhere(
        (variant) => variant.preparation == candidate,
      );
      if (index >= 0) return index;
    }
    return null;
  }

  static bool _equals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static const Set<String> _connectors = <String>{
    'y',
    'con',
    'e',
    'o',
    'and',
    'with',
    'or',
    'mas',
    'plus',
    'pero',
    'but',
    ..._exclusions,
  };

  static const Set<String> _exclusions = <String>{
    'sin',
    'ni',
    'without',
    'nor',
  };

  static const Map<Preparation, List<Preparation>>
  _equivalents = <Preparation, List<Preparation>>{
    Preparation.boiled: <Preparation>[Preparation.cooked, Preparation.steamed],
    Preparation.cooked: <Preparation>[Preparation.boiled, Preparation.steamed],
    Preparation.steamed: <Preparation>[Preparation.boiled, Preparation.cooked],
    Preparation.baked: <Preparation>[Preparation.roasted],
    Preparation.roasted: <Preparation>[Preparation.baked],
    Preparation.grilled: <Preparation>[Preparation.roasted, Preparation.baked],
    Preparation.battered: <Preparation>[Preparation.breaded, Preparation.fried],
    Preparation.breaded: <Preparation>[Preparation.battered, Preparation.fried],
    Preparation.sauteed: <Preparation>[Preparation.fried],
  };

  // Keys are singularized like the text, so "fritas" arrives as "frita".
  static final Map<String, Preparation> _preparationWords =
      <String, Preparation>{
        for (final entry
            in <String, Preparation>{
              'crudo': Preparation.raw,
              'cruda': Preparation.raw,
              'raw': Preparation.raw,
              'hervido': Preparation.boiled,
              'hervida': Preparation.boiled,
              'boiled': Preparation.boiled,
              'cocido': Preparation.cooked,
              'cocida': Preparation.cooked,
              'cooked': Preparation.cooked,
              'cocinado': Preparation.cooked,
              'cocinada': Preparation.cooked,
              'vapor': Preparation.steamed,
              'steamed': Preparation.steamed,
              'plancha': Preparation.grilled,
              'parrilla': Preparation.grilled,
              'brasa': Preparation.grilled,
              'grilled': Preparation.grilled,
              'horno': Preparation.baked,
              'baked': Preparation.baked,
              'asado': Preparation.roasted,
              'asada': Preparation.roasted,
              'roasted': Preparation.roasted,
              'roast': Preparation.roasted,
              'frito': Preparation.fried,
              'frita': Preparation.fried,
              'fried': Preparation.fried,
              'salteado': Preparation.sauteed,
              'salteada': Preparation.sauteed,
              'sauteed': Preparation.sauteed,
              'guisado': Preparation.stewed,
              'guisada': Preparation.stewed,
              'estofado': Preparation.stewed,
              'estofada': Preparation.stewed,
              'stewed': Preparation.stewed,
              'rebozado': Preparation.battered,
              'rebozada': Preparation.battered,
              'romana': Preparation.battered,
              'battered': Preparation.battered,
              'empanado': Preparation.breaded,
              'empanada': Preparation.breaded,
              'breaded': Preparation.breaded,
              'revuelto': Preparation.scrambled,
              'revuelta': Preparation.scrambled,
              'scrambled': Preparation.scrambled,
              'conserva': Preparation.canned,
              'lata': Preparation.canned,
              'canned': Preparation.canned,
              'seco': Preparation.dried,
              'seca': Preparation.dried,
              'ahumado': Preparation.smoked,
              'ahumada': Preparation.smoked,
              'smoked': Preparation.smoked,
              'curado': Preparation.cured,
              'curada': Preparation.cured,
              'tostado': Preparation.toasted,
              'tostada': Preparation.toasted,
              'toasted': Preparation.toasted,
              'pure': Preparation.mashed,
              'mashed': Preparation.mashed,
            }.entries)
          singularFoodWord(entry.key): entry.value,
      };
}

class _Phrase {
  const _Phrase({
    required this.ingredient,
    required this.words,
    required this.variantIndex,
    required this.primary,
  });

  final Ingredient ingredient;
  final List<String> words;
  final int? variantIndex;
  final bool primary;
}

class _Match {
  const _Match(this.phrase, this.start);

  final _Phrase phrase;
  final int start;
}
