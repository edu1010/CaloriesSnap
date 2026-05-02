import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/app_localizations.dart';
import '../../data/repositories/meal_repository.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../models/meal.dart';
import '../../services/nutrition/calorie_calculator.dart';
import '../meal_detail/meal_detail_screen.dart';

class DailyDetailScreen extends StatefulWidget {
  const DailyDetailScreen({
    super.key,
    required this.date,
    required this.mealRepository,
    required this.nutritionRepository,
    required this.calorieCalculator,
  });

  final DateTime date;
  final MealRepository mealRepository;
  final NutritionRepository nutritionRepository;
  final CalorieCalculator calorieCalculator;

  @override
  State<DailyDetailScreen> createState() => _DailyDetailScreenState();
}

class _DailyDetailScreenState extends State<DailyDetailScreen> {
  late Future<List<Meal>> _mealsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _mealsFuture = widget.mealRepository.getMealsForDay(widget.date);
  }

  Future<bool> _confirmDelete() async {
    final l10n = context.l10n;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.deleteMeal),
          content: Text(l10n.deleteMealPermanentRemoved),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _deleteMeal(Meal meal) async {
    if (meal.id == null) {
      return;
    }
    final confirmed = await _confirmDelete();
    if (!confirmed) {
      return;
    }
    await widget.mealRepository.deleteMeal(meal.id!);
    if (!mounted) {
      return;
    }
    setState(_reload);
  }

  Future<void> _openMealDetail(Meal meal) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => MealDetailScreen(
              meal: meal,
              mealRepository: widget.mealRepository,
              nutritionRepository: widget.nutritionRepository,
              calorieCalculator: widget.calorieCalculator,
            ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dailyDetail)),
      body: SafeArea(
        child: FutureBuilder<List<Meal>>(
          future: _mealsFuture,
          builder: (context, snapshot) {
            final meals = snapshot.data ?? <Meal>[];
            final total = meals.fold<double>(
              0,
              (sum, meal) => sum + meal.totalKcal,
            );

            return ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Card(
                  child: ListTile(
                    title: Text(DateFormat.yMMMMd().format(widget.date)),
                    subtitle: Text(l10n.mealsAndCalories(meals.length, total)),
                  ),
                ),
                const SizedBox(height: 8),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                if (snapshot.connectionState != ConnectionState.waiting &&
                    meals.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(l10n.noMealsRegisteredForDay),
                    ),
                  ),
                ...meals.map(
                  (meal) => Card(
                    child: ListTile(
                      leading:
                          (meal.imagePath != null &&
                                  File(meal.imagePath!).existsSync())
                              ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(meal.imagePath!),
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                ),
                              )
                              : const SizedBox(
                                width: 52,
                                height: 52,
                                child: ColoredBox(color: Color(0xFFE8ECE9)),
                              ),
                      title: Text(
                        '${l10n.mealTypeLabel(meal.mealType)} | ${meal.totalKcal.toStringAsFixed(0)} kcal',
                      ),
                      subtitle: Text(DateFormat.Hm().format(meal.dateTime)),
                      trailing: IconButton(
                        onPressed: () => _deleteMeal(meal),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: l10n.delete,
                      ),
                      onTap: () => _openMealDetail(meal),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
