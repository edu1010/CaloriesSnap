import '../../models/food_item.dart';

class CalorieCalculator {
  double calculateFoodCalories(double grams, double kcalPer100g) {
    _validateNonNegative(grams, 'grams');
    _validateNonNegative(kcalPer100g, 'kcalPer100g');
    final calories = (grams / 100.0) * kcalPer100g;
    if (!calories.isFinite) {
      throw ArgumentError('Calorie calculation exceeds the supported range');
    }
    return calories;
  }

  double calculateMealTotal(List<FoodItem> foods) {
    return foods.fold<double>(
      0,
      (total, item) =>
          total + calculateFoodCalories(item.grams, item.kcalPer100g),
    );
  }

  double calculateLowerEstimate(double total) {
    _validateNonNegative(total, 'total');
    return total * 0.8;
  }

  double calculateUpperEstimate(double total) {
    _validateNonNegative(total, 'total');
    return total * 1.2;
  }

  void _validateNonNegative(double value, String name) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(value, name, 'Must be finite and non-negative');
    }
  }
}
