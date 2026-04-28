import '../../models/food_item.dart';

class CalorieCalculator {
  double calculateFoodCalories(double grams, double kcalPer100g) {
    return (grams * kcalPer100g) / 100.0;
  }

  double calculateMealTotal(List<FoodItem> foods) {
    return foods.fold<double>(0, (total, item) => total + item.calculatedKcal);
  }

  double calculateLowerEstimate(double total) {
    return total * 0.8;
  }

  double calculateUpperEstimate(double total) {
    return total * 1.2;
  }
}
