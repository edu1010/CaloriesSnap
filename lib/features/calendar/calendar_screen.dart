import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/l10n/app_localizations.dart';
import '../../data/repositories/meal_repository.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../models/daily_summary.dart';
import '../../services/nutrition/calorie_calculator.dart';
import 'daily_detail_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.mealRepository,
    required this.nutritionRepository,
    required this.calorieCalculator,
  });

  final MealRepository mealRepository;
  final NutritionRepository nutritionRepository;
  final CalorieCalculator calorieCalculator;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  Map<DateTime, DailySummary> _summaries = <DateTime, DailySummary>{};
  bool _loading = false;

  DateTime _normalize(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  @override
  void initState() {
    super.initState();
    _loadMonth(_focusedDay);
  }

  Future<void> _loadMonth(DateTime month) async {
    setState(() {
      _loading = true;
    });
    final data = await widget.mealRepository.getDailySummariesForMonth(month);
    if (!mounted) {
      return;
    }
    setState(() {
      _summaries = data;
      _loading = false;
    });
  }

  List<DailySummary> _eventLoader(DateTime day) {
    final summary = _summaries[_normalize(day)];
    return summary == null ? <DailySummary>[] : <DailySummary>[summary];
  }

  Future<void> _openDayDetail(DateTime day) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => DailyDetailScreen(
              date: day,
              mealRepository: widget.mealRepository,
              nutritionRepository: widget.nutritionRepository,
              calorieCalculator: widget.calorieCalculator,
            ),
      ),
    );
    if (!mounted) {
      return;
    }
    await _loadMonth(_focusedDay);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selectedSummary = _summaries[_normalize(_selectedDay)];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.calendar)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: TableCalendar<DailySummary>(
                    firstDay: DateTime.utc(2020, 1, 1),
                    lastDay: DateTime.utc(2035, 12, 31),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
                    eventLoader: _eventLoader,
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                      });
                      _openDayDetail(selectedDay);
                    },
                    onPageChanged: (focusedDay) {
                      _focusedDay = focusedDay;
                      _loadMonth(focusedDay);
                    },
                    calendarBuilders: CalendarBuilders<DailySummary>(
                      markerBuilder: (context, day, events) {
                        if (events.isEmpty) {
                          return null;
                        }
                        final summary = events.first;
                        return Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${summary.mealsCount} | ${summary.totalKcal.toStringAsFixed(0)}',
                              style: Theme.of(
                                context,
                              ).textTheme.labelSmall?.copyWith(fontSize: 10),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const LinearProgressIndicator()
              else
                Card(
                  child: ListTile(
                    title: Text(DateFormat.yMMMMd().format(_selectedDay)),
                    subtitle: Text(
                      selectedSummary == null
                          ? l10n.noMealsRegistered
                          : l10n.mealsAndCalories(
                            selectedSummary.mealsCount,
                            selectedSummary.totalKcal,
                          ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openDayDetail(_selectedDay),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
