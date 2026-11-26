import 'package:calorie_snap/data/repositories/nutrition_repository.dart';
import 'package:calorie_snap/models/ingredient.dart';
import 'package:calorie_snap/services/food_detection/vlm/meal_analysis_prompt.dart';
import 'package:calorie_snap/services/nutrition/food_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NutritionRepository repository;

  setUpAll(() async {
    repository = NutritionRepository();
    await repository.load();
  });

  String names(List<FoodSuggestion> suggestions) => suggestions
      .map((s) => s.ingredient.variantName(s.variant, 'es'))
      .join(' | ');

  group('ingredient table', () {
    test('loads with preparations, macros and a stated source', () {
      expect(repository.ingredients.length, greaterThan(60));
      var official = 0;
      var total = 0;
      for (final ingredient in repository.ingredients) {
        expect(ingredient.variants, isNotEmpty, reason: ingredient.id);
        for (final variant in ingredient.variants) {
          total++;
          expect(variant.hasMacros, isTrue, reason: ingredient.id);
          expect(variant.source, isNotNull, reason: ingredient.id);
          if (variant.ciqualCode != null && variant.addedOilGrams == null) {
            official++;
          }
          // Fat alone can never exceed the declared energy.
          expect(
            variant.fatPer100g! * 9,
            lessThanOrEqualTo(variant.kcalPer100g + 1),
            reason: '${ingredient.id} ${variant.preparation.name}',
          );
        }
      }
      // Most values must come straight from the official table.
      expect(official / total, greaterThan(0.8));
    });

    test('values match the CIQUAL 2020 foods they cite', () {
      IngredientVariant variant(String id, Preparation prep) => repository
          .ingredients
          .firstWhere((i) => i.id == id)
          .variants
          .firstWhere((v) => v.preparation == prep);

      final boiledRice = variant('rice', Preparation.boiled);
      expect(boiledRice.ciqualCode, 9104);
      expect(boiledRice.kcalPer100g, 145);
      final friedRice = variant('rice', Preparation.fried);
      expect(friedRice.ciqualCode, 9104);
      expect(friedRice.addedOilGrams, 5);
      expect(friedRice.kcalPer100g, greaterThan(boiledRice.kcalPer100g));
      expect(variant('potato', Preparation.fried).ciqualCode, 4032);
    });

    test('Spanish names agree in gender and number', () {
      Ingredient byId(String id) =>
          repository.ingredients.firstWhere((i) => i.id == id);
      String name(String id, Preparation prep) {
        final ingredient = byId(id);
        final variant = ingredient.variants.firstWhere(
          (v) => v.preparation == prep,
        );
        return ingredient.variantName(variant, 'es');
      }

      expect(name('rice', Preparation.fried), 'Arroz frito');
      expect(name('rice', Preparation.boiled), 'Arroz hervido');
      expect(name('chickpeas', Preparation.cooked), 'Garbanzos cocidos');
      expect(name('lentils', Preparation.cooked), 'Lentejas cocidas');
      expect(
        name('chicken_breast', Preparation.grilled),
        'Pechuga de pollo a la plancha',
      );
      expect(name('potato', Preparation.fried), 'Patatas fritas');
      expect(name('rice', Preparation.fried).isNotEmpty, isTrue);
      expect(
        byId('rice').variantName(byId('rice').variants[1], 'en'),
        'Boiled rice',
      );
    });

    test('picked names resolve again in the nutrition table', () {
      expect(repository.findByName('Arroz hervido')?.kcalPer100g, 145);
      expect(repository.findByName('Pechuga de pollo a la plancha'), isNotNull);
      // Existing tables keep priority on collisions.
      expect(repository.findByName('Arroz frito')?.kcalPer100g, 163);
    });
  });

  group('search', () {
    test('"arroz" offers the ingredient with all its preparations first', () {
      final hits = repository.search.search('arroz');
      expect(hits.first.ingredient.id, 'rice');
      expect(hits.first.variantIndex, isNull);
      final labels =
          hits.first.ingredient.variants
              .map((v) => hits.first.ingredient.variantLabel(v, 'es'))
              .toList();
      expect(labels, containsAll(<String>['Crudo', 'Hervido', 'Frito']));
      // Prepared rice dishes are offered too.
      expect(
        hits.map((h) => h.ingredient.nameEs),
        contains('Arroz a la cubana'),
      );
    });

    test('prefixes, accents and plurals all match', () {
      expect(repository.search.search('arr').first.ingredient.id, 'rice');
      expect(
        repository.search.search('brocoli').first.ingredient.id,
        'broccoli',
      );
      expect(repository.search.search('PATATAS').first.ingredient.id, 'potato');
    });

    test('naming a preparation preselects that variant', () {
      final hit = repository.search.search('pollo a la plancha').first;
      expect(hit.ingredient.id, 'chicken_breast');
      expect(hit.variant.preparation, Preparation.grilled);
    });

    test('a dish named exactly like a variant is not listed twice', () {
      final hits = repository.search.search('arroz frito');
      expect(
        hits.where(
          (h) => h.ingredient.isDish && h.ingredient.nameEs == 'Arroz frito',
        ),
        isEmpty,
      );
      expect(hits.first.ingredient.id, 'rice');
      expect(hits.first.variant.preparation, Preparation.fried);
    });

    test('an empty query lists every ingredient', () {
      expect(
        repository.search.search('', limit: 1000).length,
        repository.ingredients.length,
      );
    });
  });

  group('suggestions from the description', () {
    test('finds foods with the preparation the user wrote', () {
      final suggestions = repository.search.suggestFromText(
        'Arroz frito con pechuga de pollo a la plancha y brócoli al vapor',
      );
      expect(
        names(suggestions),
        'Arroz frito | Pechuga de pollo a la plancha | Brócoli al vapor',
      );
    });

    test('a preparation after "con" belongs to the next food', () {
      final suggestions = repository.search.suggestFromText(
        'arroz con calamares rebozados',
      );
      expect(names(suggestions), 'Arroz hervido | Calamar rebozado');
    });

    test('reads grams written before the food', () {
      final suggestions = repository.search.suggestFromText(
        '200 g de patatas fritas y 10g de aceite de oliva',
      );
      expect(suggestions.map((s) => s.grams), <double?>[200, 10]);
      expect(names(suggestions), 'Patatas fritas | Aceite de oliva');
    });

    test('longer dish names win over the words inside them', () {
      final suggestions = repository.search.suggestFromText(
        'una paella y macarrones con tomate',
      );
      final found =
          suggestions
              .map((s) => s.ingredient.localizedName('es').toLowerCase())
              .toList();
      expect(found, <String>['paella', 'macarrones con tomate']);
    });

    test('text without foods suggests nothing', () {
      expect(repository.search.suggestFromText('lo de siempre'), isEmpty);
    });
  });

  group('amounts in the description', () {
    FoodSuggestion one(String text) {
      final suggestions = repository.search.suggestFromText(text);
      expect(suggestions, hasLength(1), reason: text);
      return suggestions.single;
    }

    test('keeps scoops of powder separate from ready-to-drink bottles', () {
      final shake = one('dos scoops de PlennyShake');
      expect(shake.grams, 96);
      expect(
        shake.variant.kcalPer100g * shake.grams! / 100,
        closeTo(400, 0.01),
      );
      expect(one('un cacito de Huel Black').grams, 45);
      expect(one('two scoops of Huel Powder').grams, 100);
      final bottle = one('media botella de Huel Black ready to drink');
      expect(bottle.ingredient.dish?.unitMillilitres, 500);
      expect(bottle.grams, 250);
      expect(bottle.variant.kcalPer100g * bottle.grams! / 100, 200);
      expect(one('165 ml de Plenny Drink').grams, 165);
      expect(
        one('250 ml de Huel Black en polvo').hasUnresolvedQuantity,
        isTrue,
      );
      expect(repository.search.suggestFromText('Huel'), isEmpty);
    });

    test('recognizes regional names, native spellings and chain variants', () {
      expect(one('dos pão de queijo').grams, 50);
      expect(one('dos ツナマヨおにぎり').grams, 220);
      expect(one('150 g de arroz jollof').variant.kcalPer100g, 149);
      expect(one('un Double-Double Protein Style').grams, 289);
      expect(one('una empanada de carne').variant.kcalPer100g, 249);
      final mexico = one('un Meatball Marinara de Subway México');
      final usa = one('un Meatball Marinara de Subway Estados Unidos');
      expect(mexico.grams, 258);
      expect(usa.grams, 211);
      expect(
        mexico.variant.kcalPer100g * mexico.grams! / 100,
        closeTo(540, 0.01),
      );
      expect(usa.variant.kcalPer100g * usa.grams! / 100, closeTo(460, 0.01));
    });

    test(
      'recognizes chain products and regional food with editable amounts',
      () {
        final whopper = one('un whoper del Burger King');
        expect(whopper.grams, 289);
        expect(
          whopper.variant.kcalPer100g * whopper.grams! / 100,
          closeTo(643, 0.01),
        );
        expect(one('un Big Mac de McDonald’s').grams, 236);
        expect(one('un Whopper doble').grams, 378);
        expect(one('un tequeño').grams, 40);
        expect(one('tres rodajas de espetec').grams, 15);

        final pizza = one('150 g de pizza barbacoa de Telepizza');
        expect(pizza.grams, 150);
        expect(pizza.gramsEstimated, isFalse);
        expect(pizza.variant.kcalPer100g, 213);
        expect(
          one('media pizza barbacoa de Telepizza').hasUnresolvedQuantity,
          isTrue,
        );
        expect(repository.search.suggestFromText('comí en Telepizza'), isEmpty);
        expect(
          repository.search
              .search('telepizza barbacoa')
              .first
              .variant
              .kcalPer100g,
          213,
        );
      },
    );

    test('grams typed by the user are exact', () {
      final suggestions = repository.search.suggestFromText(
        '200 g de patatas fritas y 10g de aceite de oliva',
      );
      for (final s in suggestions) {
        expect(s.gramsEstimated, isFalse);
        expect(s.quantity!.isExactWeight, isTrue);
      }
      expect(one('150 gramos de arroz').grams, 150);
      expect(one('1,5 kg de patatas').grams, 1500);
      expect(one('1.5kg de patatas').grams, 1500);
      expect(one('medio kilo de patatas').grams, 500);
      expect(one('2,5 g de azúcar').grams, 2.5);
    });

    test('counts of countable foods use their unit weight', () {
      for (final text in <String>[
        '2 huevos',
        'dos huevos',
        'un par de huevos',
        'huevos x2',
      ]) {
        final egg = one(text);
        expect(egg.ingredient.id, 'egg', reason: text);
        expect(egg.grams, 120, reason: text);
        expect(egg.gramsEstimated, isTrue, reason: text);
        expect(egg.quantity!.amount, 2, reason: text);
        expect(egg.quantity!.unit, FoodUnit.piece, reason: text);
      }
      expect(one('un plátano').grams, 120);
      expect(one('medio aguacate').grams, 70);
      expect(one('2 huevos grandes').grams, 156);
    });

    test('household measures', () {
      final spoon = one('una cucharadita de aceite');
      expect(spoon.ingredient.id, 'olive_oil');
      expect(spoon.quantity!.unit, FoodUnit.teaspoon);
      expect(spoon.grams, 4.6);
      expect(spoon.gramsEstimated, isTrue);

      final implied = one('cucharadita de aceite');
      expect(implied.grams, 4.6);
      expect(implied.quantity!.amountImplied, isTrue);

      expect(one('1 y media cucharadas de azúcar').grams, 18);
      expect(one('un vaso de leche').grams, 206);
      expect(one('medio litro de leche').grams, 515);
      expect(one('0,5 l de leche').grams, 515);
      expect(one('una lata de atún').grams, 60);
    });

    test('slices of bread', () {
      final sliced = one('2 rebanadas de pan de molde');
      expect(sliced.variant.nameEs, 'Pan de molde');
      expect(sliced.grams, 50);
      final plain = one('rebanadas de pan');
      expect(plain.grams, 60);
      expect(plain.quantity!.amountImplied, isTrue);
      expect(one('dos tostadas').grams, 60);
      expect(one('2 tostadas de pan de molde').grams, 50);
    });

    test('a unit alias does not become a second food', () {
      final hake = one('un filete de merluza a la plancha');
      expect(hake.ingredient.id, 'hake');
      expect(hake.grams, 150);
    });

    test('amounts written after the food', () {
      final suggestions = repository.search.suggestFromText(
        'arroz hervido 150 g y huevos fritos x2',
      );
      expect(names(suggestions), 'Arroz hervido | Huevo frito');
      expect(suggestions.map((s) => s.grams), <double?>[150, 120]);
      expect(suggestions.first.gramsEstimated, isFalse);
    });

    test('each food keeps its own amount', () {
      final suggestions = repository.search.suggestFromText(
        '2 huevos fritos, 100 g de arroz y una manzana',
      );
      expect(suggestions.map((s) => s.ingredient.id), <String>[
        'egg',
        'rice',
        'apple',
      ]);
      expect(suggestions.map((s) => s.grams), <double?>[120, 100, 180]);
    });

    test('explicit amounts without a known weight are not defaulted', () {
      final paellas = one('3 paellas');
      expect(paellas.grams, isNull);
      expect(paellas.hasUnresolvedQuantity, isTrue);
      expect(paellas.quantity!.amount, 3);

      final cups = one('2 tazas de arroz');
      expect(cups.grams, isNull);
      expect(cups.quantity!.unit, FoodUnit.cup);
      expect(cups.hasUnresolvedQuantity, isTrue);
      expect(one('200 ml de arroz').hasUnresolvedQuantity, isTrue);
    });

    test('an article before an uncountable food is not an amount', () {
      final paella = one('una paella');
      expect(paella.quantity, isNull);
      expect(paella.grams, isNull);
      expect(paella.hasUnresolvedQuantity, isFalse);
    });

    test('servings use the portion presets', () {
      final rice = one('un plato de arroz');
      final portions = rice.ingredient.portionsOf(rice.variant);
      expect(rice.grams, portions[1]);
      expect(one('2 raciones de arroz').grams, portions[1] * 2);
    });

    test('raw weights', () {
      final raw = one('80 g de arroz en crudo');
      expect(raw.variant.preparation, Preparation.raw);
      expect(raw.grams, 80);
      expect(raw.gramsEstimated, isFalse);
      expect(raw.quantity!.weighedRaw, isTrue);

      // A raw weight is logged against the raw values, whatever the dish.
      final cooked = one('arroz hervido 80 g en crudo');
      expect(cooked.variant.preparation, Preparation.raw);
      expect(cooked.grams, 80);
      expect(cooked.gramsEstimated, isFalse);
      expect(cooked.preparationSpecified, isTrue);
      expect(cooked.quantity!.weighedRaw, isTrue);

      expect(
        one('200 g de arroz cocido').variant.preparation,
        isNot(Preparation.raw),
      );
      expect(one('200 g de arroz cocido').preparationSpecified, isTrue);
      expect(one('200 g de arroz').preparationSpecified, isFalse);
    });

    test('leaves explicitly excluded ingredients out of the draft', () {
      final suggestions = repository.search.suggestFromText(
        'arroz y pollo sin aceite ni tomate y dos huevos',
      );
      expect(suggestions.map((food) => food.ingredient.id), [
        'rice',
        'roast_chicken',
        'egg',
      ]);
    });
  });

  group('prompt', () {
    test('the description is passed as strong evidence', () {
      final prompt = MealAnalysisPrompt.user(
        languageCode: 'es',
        hints: <String>['Paella'],
        description: 'Arroz "negro"\ncon sepia',
      );
      expect(
        prompt,
        contains(
          "The person who ate this meal says: \"Arroz 'negro' con sepia\".",
        ),
      );
      expect(
        prompt.indexOf('ate this meal'),
        lessThan(prompt.indexOf('weak classifier')),
      );
    });

    test('blank or missing descriptions add nothing', () {
      final plain = MealAnalysisPrompt.user(languageCode: 'es');
      expect(
        MealAnalysisPrompt.user(languageCode: 'es', description: '  '),
        plain,
      );
      expect(plain, isNot(contains('says:')));
    });

    test('long descriptions are capped', () {
      final cleaned = MealAnalysisPrompt.cleanDescription('a' * 1000)!;
      expect(cleaned.length, MealAnalysisPrompt.maxDescriptionLength);
    });
  });
}
