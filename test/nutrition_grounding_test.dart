import 'package:calorie_snap/data/repositories/nutrition_repository.dart';
import 'package:calorie_snap/services/food_detection/vlm/meal_analysis.dart';
import 'package:calorie_snap/services/food_detection/vlm/nutrition_grounding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NutritionGrounding grounding;

  setUpAll(() async {
    final repository = NutritionRepository();
    await repository.load();
    grounding = NutritionGrounding(repository);
  });

  GroundedItem ground(
    String name, {
    String? en,
    double? grams = 100,
    double? kcal = 999999,
    String language = 'es',
    String? dish,
  }) => grounding.ground(
    AnalyzedItem(name: name, nameEn: en, grams: grams, kcalPer100g: kcal),
    languageCode: language,
    dishName: dish,
  );

  test('the table overrides the energy value proposed by the model', () {
    final item = ground('Pan de barra', en: 'baguette bread', kcal: 500);
    expect(item.match?.name, 'Baguette bread');
    expect(item.kcalPer100g, 270);
    expect(item.fromDatabase, isTrue);
  });

  test('matches despite accents, plurals, articles and neutral cooking words', () {
    expect(ground('lentejas guisadas').match?.name, 'Lentil stew');
    expect(ground('Arroz blanco cocido').match?.name, 'Rice cooked');
    expect(ground('la pechuga de pollo a la plancha').match?.name, 'Chicken breast');
    expect(ground('croqueta').match?.name, 'Croquetas');
    expect(ground('Jamón Serrano').match?.name, 'Jamon Serrano');
  });

  test('uses the English name when the localized one is unknown', () {
    final item = ground('cosa rara del chef', en: 'grilled salmon');
    expect(item.match?.name, 'Grilled Salmon');
  });

  test('an exact name is resolved in the language of the query first', () {
    // "Tortilla" is a flatbread in the English table and an omelette in Spain.
    expect(ground('tortilla', language: 'en').match?.name, 'Tortilla');
    expect(ground('tortilla de patatas').match?.name, 'Tortilla De Patatas');
  });

  test('frying is never dropped: fried food keeps a fried energy density', () {
    expect(ground('pollo frito').match?.name, 'Fried chicken');
    // No fried aubergine in the table: plain aubergine must not be used.
    final item = ground('berenjena frita', en: 'fried eggplant', kcal: 190);
    expect(item.match, isNull);
    expect(item.kcalPer100g, 190);
  });

  test('a name with mostly unknown words is not forced onto a table entry', () {
    final item = ground(
      'pastel azteca con mole poblano y queso',
      en: 'aztec mole casserole',
      kcal: 180,
    );
    expect(item.match, isNull);
    expect(item.kcalPer100g, 180);
  });

  test('a lone item can be identified by the dish name', () {
    final item = ground('plato', en: 'plate', dish: 'Fabada asturiana');
    expect(item.match?.name, 'Fabada Asturiana');
  });

  test('implausible model numbers are replaced or clamped', () {
    final unknown = ground('zzz', en: 'zzz', kcal: 5000, grams: 50000);
    expect(unknown.kcalPer100g, NutritionGrounding.unknownKcalPer100g);
    expect(unknown.grams, NutritionGrounding.maxGrams);

    final noGrams = ground('Paella', grams: 0);
    expect(noGrams.grams, noGrams.match!.defaultGramsMedium);

    expect(ground('zzz', en: 'zzz', kcal: null, grams: null).grams, 150);
    expect(ground('agua', kcal: 0).kcalPer100g, 0);
    expect(
      ground('zzz', en: 'zzz', kcal: 0).kcalPer100g,
      NutritionGrounding.unknownKcalPer100g,
    );
    expect(ground('x', en: 'blueberry', language: 'en').match?.name, 'Blueberries');
  });

  test('every common Spanish food resolves by both of its names', () async {
    final repository = NutritionRepository();
    await repository.load();
    final common = repository.foods.where(
      (food) => food.source == 'Generic composition estimate',
    );
    expect(common.length, greaterThan(150));
    for (final food in common) {
      expect(
        ground(food.nameEs!, language: 'es').match?.name,
        food.name,
        reason: food.nameEs,
      );
      expect(
        ground(food.name, language: 'en').match?.name,
        food.name,
        reason: food.name,
      );
    }
  });
}
