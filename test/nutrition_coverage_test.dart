import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:calorie_snap/data/repositories/nutrition_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Food-101 nutrition coverage', () {
    late NutritionRepository repository;

    setUp(() async {
      repository = NutritionRepository();
      await repository.load();
    });

    test('every classifier label resolves to nutrition data', () async {
      final csv = await rootBundle.loadString(
        'assets/models/food_classifier_labels.csv',
      );
      final lines =
          csv
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .skip(1) // header: id,name
              .toList();

      expect(lines.length, greaterThanOrEqualTo(101));

      final unresolved = <String>[];
      for (final line in lines) {
        final label = line.split(',').sublist(1).join(',').trim();
        final match = repository.findByName(label);
        if (match == null || match.kcalPer100g <= 0) {
          unresolved.add(label);
        }
      }

      expect(
        unresolved,
        isEmpty,
        reason: 'Labels without nutrition data: $unresolved',
      );
    });

    test('previously dropped dishes now carry calories', () {
      for (final dish in const <String>[
        'Tiramisu',
        'Ramen',
        'Falafel',
        'Pho',
      ]) {
        final food = repository.findByName(dish);
        expect(food, isNotNull, reason: '$dish should resolve');
        expect(food!.kcalPer100g, greaterThan(0));
        expect(food.defaultGramsMedium, greaterThan(0));
      }
    });

    test('Spanish dishes carry calories', () {
      const spanishDishes = <String>[
        'Tortilla De Patatas',
        'Croquetas',
        'Gazpacho',
        'Salmorejo',
        'Patatas Bravas',
        'Pulpo A La Gallega',
        'Jamon Serrano',
        'Fabada Asturiana',
        'Pimientos De Padron',
        'Gambas Al Ajillo',
        'Empanada Gallega',
        'Ensaladilla Rusa',
        'Tarta De Santiago',
        'Bocadillo De Calamares',
        'Albondigas',
      ];
      for (final dish in spanishDishes) {
        final food = repository.findByName(dish);
        expect(food, isNotNull, reason: '$dish should resolve');
        expect(food!.kcalPer100g, greaterThan(0));
        expect(food.defaultGramsMedium, greaterThan(0));
      }
    });

    test('dishes are resolvable by their Spanish display name', () {
      // Spanish name -> same canonical entry (identity preserved across locale).
      final tiramisu = repository.findByName('Tiramisú');
      expect(tiramisu, isNotNull);
      expect(tiramisu!.name, 'Tiramisu');
      expect(tiramisu.localizedName('es'), 'Tiramisú');
      expect(tiramisu.localizedName('en'), 'Tiramisu');
    });

    test('classifier typography and Spanish accents resolve exactly', () {
      expect(
        repository.findByName('  chicken_breast  ')?.name,
        'Chicken breast',
      );
      expect(repository.findByName('TIRAMISU')?.name, 'Tiramisu');
      expect(repository.findByName('Tiramisu\u0301')?.name, 'Tiramisu');
      expect(
        repository.findByName('arroz   integral cocido')?.name,
        'Brown rice cooked',
      );
      expect(repository.findByName('salmon')?.name, 'Salmon');
    });

    test('preparation differences do not become fuzzy nutrition matches', () {
      expect(repository.findByName('Arroz cocido')?.kcalPer100g, 130);
      expect(repository.findByName('Arroz frito')?.kcalPer100g, 163);
      expect(repository.findByName('Arroz crudo'), isNull);
      expect(repository.findByName('Tortilla francesa')?.name, 'Omelette');
      expect(
        repository.findByName('Tortilla de trigo o maiz')?.name,
        'Tortilla',
      );
    });
  });
}
