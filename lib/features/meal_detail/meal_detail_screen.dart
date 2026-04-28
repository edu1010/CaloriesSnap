import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../data/repositories/meal_repository.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../models/meal.dart';
import '../../services/nutrition/calorie_calculator.dart';
import '../register_meal/food_confirmation_screen.dart';

class MealDetailScreen extends StatefulWidget {
  const MealDetailScreen({
    super.key,
    required this.meal,
    required this.mealRepository,
    required this.nutritionRepository,
    required this.calorieCalculator,
  });

  final Meal meal;
  final MealRepository mealRepository;
  final NutritionRepository nutritionRepository;
  final CalorieCalculator calorieCalculator;

  @override
  State<MealDetailScreen> createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends State<MealDetailScreen> {
  Meal? _meal;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _meal = widget.meal;
    _refreshMeal();
  }

  Future<void> _refreshMeal() async {
    final id = _meal?.id;
    if (id == null) {
      return;
    }

    setState(() {
      _loading = true;
    });

    final latest = await widget.mealRepository.getMealById(id);
    if (!mounted) {
      return;
    }

    setState(() {
      _meal = latest ?? _meal;
      _loading = false;
    });
  }

  Future<void> _editMeal() async {
    final meal = _meal;
    if (meal == null || meal.imagePath == null || meal.imagePath!.isEmpty) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FoodConfirmationScreen(
          imagePath: meal.imagePath!,
          initialFoods: meal.foods,
          mealRepository: widget.mealRepository,
          nutritionRepository: widget.nutritionRepository,
          calorieCalculator: widget.calorieCalculator,
          mealId: meal.id,
          mealDateTime: meal.dateTime,
          initialMealType: meal.mealType,
          initialNotes: meal.notes,
        ),
      ),
    );

    if (!mounted) {
      return;
    }
    await _refreshMeal();
  }

  Future<void> _deleteMeal() async {
    final meal = _meal;
    if (meal?.id == null) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete meal'),
          content: const Text('This meal will be permanently deleted.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    await widget.mealRepository.deleteMeal(meal!.id!);
    if (!mounted) {
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final meal = _meal;
    if (meal == null) {
      return const Scaffold(
        body: Center(
          child: Text('Meal not found'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meal detail'),
      ),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                if (meal.imagePath != null && File(meal.imagePath!).existsSync())
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Image.file(
                        File(meal.imagePath!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${meal.mealType} | ${DateFormat.yMMMd().add_Hm().format(meal.dateTime)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${AppConstants.approximateCaloriesLabel}: ${meal.totalKcal.toStringAsFixed(0)} kcal',
                        ),
                        Text(
                          '${AppConstants.estimatedRangeLabel}: '
                          '${meal.lowerEstimateKcal.toStringAsFixed(0)}-'
                          '${meal.upperEstimateKcal.toStringAsFixed(0)} kcal',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppConstants.estimationDisclaimer,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Foods',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...meal.foods.map(
                  (food) => Card(
                    child: ListTile(
                      title: Text(food.name),
                      subtitle: Text(
                        '${food.grams.toStringAsFixed(0)} g | '
                        '${food.kcalPer100g.toStringAsFixed(0)} kcal/100g',
                      ),
                      trailing: Text('${food.calculatedKcal.toStringAsFixed(0)} kcal'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    title: const Text('Notes'),
                    subtitle: Text(meal.notes.isEmpty ? 'No notes' : meal.notes),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _editMeal,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _deleteMeal,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (_loading)
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}

