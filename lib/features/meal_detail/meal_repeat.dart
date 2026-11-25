import 'package:flutter/widgets.dart';

import '../../data/repositories/meal_repository.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../models/food_item.dart';
import '../../models/meal.dart';
import '../../services/nutrition/calorie_calculator.dart';
import '../register_meal/food_confirmation_screen.dart';

/// Editable copies of [meal]'s foods for logging it again as a new meal.
///
/// Database ids are dropped so nothing in the copy points back at the
/// original rows; the original meal is never modified.
List<FoodItem> repeatableFoods(Meal meal) {
  return meal.foods
      .map(
        (food) => FoodItem(
          name: food.name,
          grams: food.grams,
          kcalPer100g: food.kcalPer100g,
          calculatedKcal: food.calculatedKcal,
        ),
      )
      .toList();
}

/// The existing confirmation flow, prefilled with [meal] as a brand-new meal.
///
/// - `mealId` is null, so saving inserts instead of updating the original.
/// - `mealDateTime` is null, so the summary stamps it with `DateTime.now()`
///   at save time (i.e. today).
/// - The photo is not carried over: the original meal owns its image file,
///   and sharing the path would let edits/deletes of either meal affect the
///   other. The repeat is a photo-less meal.
FoodConfirmationScreen buildRepeatMealScreen({
  required Meal meal,
  required MealRepository mealRepository,
  required NutritionRepository nutritionRepository,
  required CalorieCalculator calorieCalculator,
}) {
  return FoodConfirmationScreen(
    imagePath: null,
    initialFoods: repeatableFoods(meal),
    mealRepository: mealRepository,
    nutritionRepository: nutritionRepository,
    calorieCalculator: calorieCalculator,
    initialMealType: meal.mealType,
    initialNotes: meal.notes,
  );
}

/// Strings for the repeat action, kept local to this feature so the shared
/// localization file does not need to change.
extension MealRepeatStrings on BuildContext {
  bool get _repeatIsSpanish => Localizations.localeOf(
    this,
  ).languageCode.toLowerCase().startsWith('es');

  String get repeatMealLabel =>
      _repeatIsSpanish ? 'Repetir comida' : 'Repeat meal';
}
