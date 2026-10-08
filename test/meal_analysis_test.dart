import 'package:calorie_snap/services/food_detection/vlm/meal_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the contracted JSON', () {
    final analysis =
        MealAnalysis.tryParse(
          '{"food":true,"dish":"Bocadillo de lomo con queso","items":['
          '{"name":"pan de barra","en":"baguette bread","grams":120,"kcal100":270},'
          '{"name":"lomo","en":"pork loin","grams":90,"kcal100":200}]}',
        )!;
    expect(analysis.isFood, isTrue);
    expect(analysis.dish, 'Bocadillo de lomo con queso');
    expect(analysis.items.map((item) => item.name), ['pan de barra', 'lomo']);
    expect(analysis.items.first.nameEn, 'baguette bread');
    expect(analysis.items.first.grams, 120);
    expect(analysis.items.last.kcalPer100g, 200);
  });

  test('accepts prose, code fences, reasoning and trailing commas', () {
    final analysis =
        MealAnalysis.tryParse(
          '<think>it looks like {soup}</think>Sure:\n```json\n'
          '{"food": true, "dish": "Sopa", "items": [{"name": "sopa de fideos", '
          '"en": "noodle soup", "grams": "300 g", "kcal100": "45",},],}\n```\n'
          'Hope it helps {x}',
        )!;
    expect(analysis.items.single.grams, 300);
    expect(analysis.items.single.kcalPer100g, 45);
  });

  test('keeps complete items when the output was cut by the token limit', () {
    final analysis =
        MealAnalysis.tryParse(
          '{"food":true,"dish":"Plato combinado","items":['
          '{"name":"huevo frito","en":"fried egg","grams":60,"kcal100":200},'
          '{"name":"patatas fr',
        )!;
    expect(analysis.items.single.name, 'huevo frito');
  });

  test('a photo without food yields no items', () {
    final analysis =
        MealAnalysis.tryParse('{"food":false,"dish":"","items":[]}')!;
    expect(analysis.isFood, isFalse);
    expect(analysis.items, isEmpty);

    // "food": true without anything to log is not a usable detection either.
    expect(
      MealAnalysis.tryParse('{"food":true,"dish":"?","items":[]}')!.isFood,
      isFalse,
    );
  });

  test('unusable answers return null instead of throwing', () {
    expect(MealAnalysis.tryParse(''), isNull);
    expect(MealAnalysis.tryParse('I cannot see the image.'), isNull);
    expect(MealAnalysis.tryParse('{"food":true,"dish":"x","items":[{"na'), isNull);
    expect(MealAnalysis.tryParse('<think>still thinking {"food":true'), isNull);
    expect(MealAnalysis.tryParse('[1, 2, 3]'), isNull);
  });

  test('drops placeholder names and repeated items', () {
    final analysis =
        MealAnalysis.tryParse(
          '{"food":true,"dish":"...","items":['
          '{"name":"...","en":"...","grams":0,"kcal100":0},'
          '{"name":"Fresa","en":"strawberry","grams":140,"kcal100":32},'
          '{"name":"fresa","en":"strawberry","grams":140,"kcal100":32}]}',
        )!;
    expect(analysis.dish, isNull);
    expect(analysis.items.single.name, 'Fresa');
  });

  test('ignores malformed items and caps their number', () {
    final items = List<String>.generate(
      20,
      (i) => '{"name":"item $i","en":"item $i","grams":10,"kcal100":10}',
    ).join(',');
    final analysis =
        MealAnalysis.tryParse(
          '{"food":true,"dish":"x","items":[42,{"grams":5},$items]}',
        )!;
    expect(analysis.items, hasLength(MealAnalysis.maxItems));
    expect(analysis.items.first.name, 'item 0');
  });
}
