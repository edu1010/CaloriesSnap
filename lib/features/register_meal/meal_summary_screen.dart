import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../data/repositories/meal_repository.dart';
import '../../models/food_item.dart';
import '../../models/meal.dart';
import '../../services/nutrition/calorie_calculator.dart';

class MealSummaryScreen extends StatefulWidget {
  const MealSummaryScreen({
    super.key,
    required this.imagePath,
    required this.foods,
    required this.mealRepository,
    required this.calorieCalculator,
    this.mealId,
    this.mealDateTime,
    this.initialMealType,
    this.initialNotes,
  });

  final String imagePath;
  final List<FoodItem> foods;
  final MealRepository mealRepository;
  final CalorieCalculator calorieCalculator;
  final int? mealId;
  final DateTime? mealDateTime;
  final String? initialMealType;
  final String? initialNotes;

  @override
  State<MealSummaryScreen> createState() => _MealSummaryScreenState();
}

class _MealSummaryScreenState extends State<MealSummaryScreen> {
  late String _mealType;
  late final TextEditingController _notesController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _mealType = widget.initialMealType ?? AppConstants.mealTypes.first;
    _notesController = TextEditingController(text: widget.initialNotes ?? '');
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  double get _totalKcal => widget.calorieCalculator.calculateMealTotal(widget.foods);
  double get _lower => widget.calorieCalculator.calculateLowerEstimate(_totalKcal);
  double get _upper => widget.calorieCalculator.calculateUpperEstimate(_totalKcal);

  Future<void> _saveMeal() async {
    setState(() {
      _saving = true;
    });

    final meal = Meal(
      id: widget.mealId,
      dateTime: widget.mealDateTime ?? DateTime.now(),
      mealType: _mealType,
      imagePath: widget.imagePath,
      foods: widget.foods,
      totalKcal: _totalKcal,
      lowerEstimateKcal: _lower,
      upperEstimateKcal: _upper,
      notes: _notesController.text.trim(),
    );

    try {
      if (widget.mealId == null) {
        await widget.mealRepository.insertMeal(meal);
      } else {
        await widget.mealRepository.updateMeal(meal);
      }

      if (!mounted) {
        return;
      }

      if (widget.mealId == null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save meal: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meal summary'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.file(
                  File(widget.imagePath),
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
                      '${AppConstants.approximateCaloriesLabel}: ${_totalKcal.toStringAsFixed(0)} kcal',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${AppConstants.estimatedRangeLabel}: '
                      '${_lower.toStringAsFixed(0)}-${_upper.toStringAsFixed(0)} kcal',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Estimated: ${_totalKcal.toStringAsFixed(0)} kcal, '
                      'likely range: ${_lower.toStringAsFixed(0)}-${_upper.toStringAsFixed(0)} kcal',
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
            const SizedBox(height: 12),
            Text(
              'Foods',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...widget.foods.map(
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
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _mealType,
              items: AppConstants.mealTypes
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item,
                      child: Text(item),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _mealType = value;
                });
              },
              decoration: const InputDecoration(labelText: 'Meal type'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Optional meal notes',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _saveMeal,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save meal'),
            ),
          ],
        ),
      ),
    );
  }
}

