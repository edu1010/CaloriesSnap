import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/utils/responsive_utils.dart';
import '../../data/repositories/meal_repository.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/register_meal/register_meal_screen.dart';
import '../../models/daily_summary.dart';
import '../../services/barcode/open_food_facts_service.dart';
import '../../services/food_detection/food_detection_service.dart';
import '../../services/image/image_storage_service.dart';
import '../../services/nutrition/calorie_calculator.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.mealRepository,
    required this.nutritionRepository,
    required this.foodDetectionService,
    required this.openFoodFactsService,
    required this.imageStorageService,
    required this.calorieCalculator,
  });

  final MealRepository mealRepository;
  final NutritionRepository nutritionRepository;
  final FoodDetectionService foodDetectionService;
  final OpenFoodFactsService openFoodFactsService;
  final ImageStorageService imageStorageService;
  final CalorieCalculator calorieCalculator;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<DailySummary> _todaySummaryFuture;

  @override
  void initState() {
    super.initState();
    _reloadToday();
  }

  void _reloadToday() {
    _todaySummaryFuture = widget.mealRepository.getDailySummary(DateTime.now());
  }

  Future<void> _openRegisterMeal() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => RegisterMealScreen(
              mealRepository: widget.mealRepository,
              nutritionRepository: widget.nutritionRepository,
              foodDetectionService: widget.foodDetectionService,
              openFoodFactsService: widget.openFoodFactsService,
              imageStorageService: widget.imageStorageService,
              calorieCalculator: widget.calorieCalculator,
            ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(_reloadToday);
  }

  Future<void> _openCalendar() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => CalendarScreen(
              mealRepository: widget.mealRepository,
              nutritionRepository: widget.nutritionRepository,
              calorieCalculator: widget.calorieCalculator,
            ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(_reloadToday);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final wide = ResponsiveUtils.isWideLayout(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FutureBuilder<DailySummary>(
                future: _todaySummaryFuture,
                builder: (context, snapshot) {
                  final summary =
                      snapshot.data ??
                      DailySummary(
                        date: DateTime.now(),
                        mealsCount: 0,
                        totalKcal: 0,
                      );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.today,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          _StatCard(
                            title: l10n.approximateCalories,
                            value:
                                '${summary.totalKcal.toStringAsFixed(0)} kcal',
                            icon: Icons.local_fire_department_outlined,
                          ),
                          _StatCard(
                            title: l10n.mealsRegistered,
                            value: summary.mealsCount.toString(),
                            icon: Icons.restaurant_menu_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        l10n.estimationDisclaimer,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (wide)
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _openRegisterMeal,
                                icon: const Icon(Icons.add_a_photo_outlined),
                                label: Text(l10n.registerMeal),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _openCalendar,
                                icon: const Icon(Icons.calendar_month_outlined),
                                label: Text(l10n.calendar),
                              ),
                            ),
                          ],
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            FilledButton.icon(
                              onPressed: _openRegisterMeal,
                              icon: const Icon(Icons.add_a_photo_outlined),
                              label: Text(l10n.registerMeal),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _openCalendar,
                              icon: const Icon(Icons.calendar_month_outlined),
                              label: Text(l10n.calendar),
                            ),
                          ],
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              CircleAvatar(radius: 20, child: Icon(icon)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(value, style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
