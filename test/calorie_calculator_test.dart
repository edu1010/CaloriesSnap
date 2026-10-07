import 'package:calorie_snap/models/food_item.dart';
import 'package:calorie_snap/services/nutrition/calorie_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final calculator = CalorieCalculator();
  const rice = FoodItem(
    name: 'Rice cooked',
    grams: 180,
    kcalPer100g: 130,
    calculatedKcal: 234,
  );

  test('editing portion or nutritional density updates derived calories', () {
    expect(rice.copyWith(grams: 100).calculatedKcal, 130);
    expect(rice.copyWith(kcalPer100g: 200).calculatedKcal, 360);
    expect(rice.copyWith(grams: 100, kcalPer100g: 200).calculatedKcal, 200);
  });

  test('meal totals use weight and density when stored kcal is stale', () {
    expect(
      calculator.calculateMealTotal([rice.copyWith(calculatedKcal: 999)]),
      234,
    );
    expect(calculator.calculateMealTotal([]), 0);
  });

  test('calories reject invalid measurements and accept zero quantities', () {
    for (final invalid in [-1.0, double.nan, double.infinity]) {
      expect(
        () => calculator.calculateFoodCalories(invalid, 130),
        throwsArgumentError,
      );
      expect(
        () => calculator.calculateFoodCalories(180, invalid),
        throwsArgumentError,
      );
    }
    expect(calculator.calculateFoodCalories(0, 130), 0);
    expect(
      () => calculator.calculateFoodCalories(1e308, 1e308),
      throwsArgumentError,
    );
  });
}
