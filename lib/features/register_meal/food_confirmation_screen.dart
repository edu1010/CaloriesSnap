import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/repositories/meal_repository.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../models/food_item.dart';
import '../../models/nutrition_food.dart';
import '../../services/nutrition/calorie_calculator.dart';
import '../../services/food_detection/food_detection_service.dart';
import '../../services/food_detection/meal_analysis_service.dart';
import 'meal_summary_screen.dart';

class FoodConfirmationScreen extends StatefulWidget {
  const FoodConfirmationScreen({
    super.key,
    this.imagePath,
    required this.initialFoods,
    required this.mealRepository,
    required this.nutritionRepository,
    required this.calorieCalculator,
    this.mealId,
    this.mealDateTime,
    this.initialMealType,
    this.initialNotes,
    this.photoCandidates,
    this.detection,
  });

  final String? imagePath;
  final List<FoodItem> initialFoods;
  final MealRepository mealRepository;
  final NutritionRepository nutritionRepository;
  final CalorieCalculator calorieCalculator;
  final int? mealId;
  final DateTime? mealDateTime;
  final String? initialMealType;
  final String? initialNotes;

  /// Null for barcode/edit flows; empty means the photo model abstained.
  final List<DetectedFood>? photoCandidates;

  /// The photo analysis behind [initialFoods], when there was one.
  final MealDetection? detection;

  @override
  State<FoodConfirmationScreen> createState() => _FoodConfirmationScreenState();
}

class _FoodConfirmationScreenState extends State<FoodConfirmationScreen> {
  late final List<_EditableFoodEntry> _foods;
  _EditableFoodEntry? _selectedPhotoEntry;
  String? _selectedPhotoName;

  @override
  void initState() {
    super.initState();
    _foods = widget.initialFoods.map(_buildEntryFromFood).toList();
    if (widget.photoCandidates?.isNotEmpty == true && _foods.isNotEmpty) {
      _selectedPhotoEntry = _foods.first;
      _selectedPhotoName = _foods.first.name;
    }
  }

  @override
  void dispose() {
    for (final item in _foods) {
      item.dispose();
    }
    super.dispose();
  }

  _EditableFoodEntry _buildEntryFromFood(FoodItem food) {
    return _EditableFoodEntry(
      id: food.id,
      name: food.name,
      grams: food.grams,
      kcalPer100g: food.kcalPer100g,
      portionSize: _guessPortion(food.name, food.grams),
    );
  }

  String _guessPortion(String name, double grams) {
    final nutrition = widget.nutritionRepository.findByName(name);
    if (nutrition == null) {
      return 'custom';
    }
    if ((nutrition.defaultGramsSmall - grams).abs() < 0.1) {
      return 'small';
    }
    if ((nutrition.defaultGramsMedium - grams).abs() < 0.1) {
      return 'medium';
    }
    if ((nutrition.defaultGramsLarge - grams).abs() < 0.1) {
      return 'large';
    }
    return 'custom';
  }

  double _entryCalories(_EditableFoodEntry item) {
    return widget.calorieCalculator.calculateFoodCalories(
      item.grams,
      item.kcalPer100g,
    );
  }

  double get _totalCalories {
    return _foods.fold<double>(0, (sum, item) => sum + _entryCalories(item));
  }

  void _removeAt(int index) {
    setState(() {
      if (identical(_foods[index], _selectedPhotoEntry)) {
        _selectedPhotoEntry = null;
        _selectedPhotoName = null;
      }
      _foods[index].dispose();
      _foods.removeAt(index);
    });
  }

  double? _parseNumber(String value) {
    final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  void _choosePhotoCandidate(DetectedFood candidate) {
    setState(() {
      final previous = _selectedPhotoEntry;
      if (previous != null) {
        _foods.remove(previous);
        previous.dispose();
      }
      final entry = _EditableFoodEntry(
        name: candidate.name,
        grams: candidate.suggestedGrams,
        kcalPer100g: candidate.kcalPer100g,
        portionSize: 'medium',
      );
      _foods.insert(0, entry);
      _selectedPhotoEntry = entry;
      _selectedPhotoName = candidate.name;
    });
  }

  Future<void> _addFood() async {
    final l10n = context.l10n;
    final languageCode = Localizations.localeOf(context).languageCode;
    final nutritionFoods = widget.nutritionRepository.foods;
    NutritionFood? selectedNutrition =
        nutritionFoods.isNotEmpty ? nutritionFoods.first : null;

    final nameController = TextEditingController(
      text: selectedNutrition?.localizedName(languageCode) ?? '',
    );
    final gramsController = TextEditingController(
      text: (selectedNutrition?.defaultGramsMedium ?? 100).toStringAsFixed(0),
    );
    final kcalController = TextEditingController(
      text: (selectedNutrition?.kcalPer100g ?? 100).toStringAsFixed(0),
    );
    var selectedPortion = 'medium';

    final result = await showDialog<_EditableFoodEntry>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text(l10n.addFood),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DropdownButtonFormField<NutritionFood?>(
                      initialValue: selectedNutrition,
                      items: <DropdownMenuItem<NutritionFood?>>[
                        DropdownMenuItem<NutritionFood?>(
                          value: null,
                          child: Text(l10n.customFood),
                        ),
                        ...nutritionFoods.map(
                          (item) => DropdownMenuItem<NutritionFood?>(
                            value: item,
                            child: Text(item.localizedName(languageCode)),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setLocalState(() {
                          selectedNutrition = value;
                          if (value != null) {
                            selectedPortion = 'medium';
                            nameController.text = value.localizedName(
                              languageCode,
                            );
                            gramsController.text = value.defaultGramsMedium
                                .toStringAsFixed(0);
                            kcalController.text = value.kcalPer100g
                                .toStringAsFixed(0);
                          }
                        });
                      },
                      decoration: InputDecoration(labelText: l10n.knownFood),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(labelText: l10n.name),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: gramsController,
                      decoration: InputDecoration(
                        labelText: l10n.estimatedGrams,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: kcalController,
                      decoration: InputDecoration(labelText: l10n.kcalPer100g),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedPortion,
                      items:
                          AppConstants.portionSizes
                              .map(
                                (item) => DropdownMenuItem<String>(
                                  value: item,
                                  child: Text(l10n.portionLabel(item)),
                                ),
                              )
                              .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setLocalState(() {
                          selectedPortion = value;
                          if (selectedNutrition != null && value != 'custom') {
                            gramsController.text = selectedNutrition!
                                .gramsForPortion(value)
                                .toStringAsFixed(0);
                          }
                        });
                      },
                      decoration: InputDecoration(labelText: l10n.portionSize),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final grams = _parseNumber(gramsController.text.trim());
                    final kcalPer100g = _parseNumber(
                      kcalController.text.trim(),
                    );
                    if (name.isEmpty ||
                        grams == null ||
                        grams <= 0 ||
                        kcalPer100g == null ||
                        kcalPer100g < 0 ||
                        kcalPer100g > 1000 ||
                        !(grams * kcalPer100g).isFinite) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.invalidFoodValues)),
                      );
                      return;
                    }
                    Navigator.pop(
                      context,
                      _EditableFoodEntry(
                        name: name,
                        grams: grams,
                        kcalPer100g: kcalPer100g,
                        portionSize: selectedPortion,
                      ),
                    );
                  },
                  child: Text(l10n.addFood),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    gramsController.dispose();
    kcalController.dispose();

    if (result != null) {
      setState(() {
        _foods.add(result);
      });
    }
  }

  Future<void> _continue() async {
    final l10n = context.l10n;
    for (final item in _foods) {
      final grams = _parseNumber(item.gramsController.text);
      final kcal = _parseNumber(item.kcalController.text);
      if (item.nameController.text.trim().isEmpty ||
          grams == null ||
          grams <= 0 ||
          kcal == null ||
          kcal < 0 ||
          kcal > 1000 ||
          !(grams * kcal).isFinite) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.invalidFoodValues)));
        return;
      }
      item.name = item.nameController.text.trim();
      item.grams = grams;
      item.kcalPer100g = kcal;
    }
    if (_foods.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.addAtLeastOneFoodItem)));
      return;
    }

    final foods =
        _foods
            .map(
              (item) => FoodItem(
                id: item.id,
                name: item.name,
                grams: item.grams,
                kcalPer100g: item.kcalPer100g,
                calculatedKcal: _entryCalories(item),
              ),
            )
            .toList();

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder:
            (_) => MealSummaryScreen(
              imagePath: widget.imagePath,
              foods: foods,
              mealRepository: widget.mealRepository,
              calorieCalculator: widget.calorieCalculator,
              mealId: widget.mealId,
              mealDateTime: widget.mealDateTime,
              initialMealType: widget.initialMealType,
              initialNotes: widget.initialNotes,
            ),
      ),
    );

    if (saved == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  bool get _analyzedByVlm {
    final detection = widget.detection;
    return detection != null &&
        detection.engine == MealAnalysisEngine.vlm &&
        detection.foods.isNotEmpty;
  }

  List<Widget> _buildVlmSummary(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final detection = widget.detection!;
    final dish = detection.dishName;
    final estimated =
        detection.foods
            .where((food) => food.estimatedNutrition)
            .map((food) => food.name)
            .toList();
    return <Widget>[
      if (dish != null && dish.isNotEmpty)
        Text(l10n.analyzedByAi(dish), style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(l10n.aiPortionHint),
      if (estimated.isNotEmpty) ...<Widget>[
        const SizedBox(height: 4),
        Text(
          l10n.aiEstimatedEnergy(estimated.join(', ')),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      const SizedBox(height: 12),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasImage =
        widget.imagePath != null &&
        widget.imagePath!.isNotEmpty &&
        File(widget.imagePath!).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(hasImage ? l10n.confirmDetectedFoods : l10n.confirmFoods),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addFood,
        icon: const Icon(Icons.add),
        label: Text(l10n.addFood),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16),
              child:
                  hasImage
                      ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          height: 160,
                          width: double.infinity,
                          child: Image.file(
                            File(widget.imagePath!),
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                      : Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color:
                              Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.qr_code_2),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.mealStartedFromBarcode,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${l10n.approximateCalories}: ${_totalCalories.toStringAsFixed(0)} kcal',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _continue,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(l10n.continueText),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                l10n.estimationDisclaimer,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  if (widget.detection?.vlmFailure != null) ...<Widget>[
                    Text(
                      l10n.aiFallbackNotice,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_analyzedByVlm)
                    ..._buildVlmSummary(context)
                  else if (widget.photoCandidates != null) ...<Widget>[
                    Text(l10n.photoPortionHint),
                    const SizedBox(height: 8),
                    if (widget.photoCandidates!.isEmpty)
                      Text(l10n.noReliableDish)
                    else ...<Widget>[
                      Text(
                        l10n.possibleDish,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (widget.photoCandidates!.first.requiresConfirmation)
                        Text(l10n.uncertainDish),
                      Text(l10n.alternativeDishes),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children:
                            widget.photoCandidates!
                                .map(
                                  (candidate) => ChoiceChip(
                                    label: Text(candidate.name),
                                    tooltip:
                                        '${l10n.modelScore}: ${(candidate.confidence * 100).toStringAsFixed(0)}%',
                                    selected:
                                        _selectedPhotoName == candidate.name,
                                    onSelected:
                                        (_) => _choosePhotoCandidate(candidate),
                                  ),
                                )
                                .toList(),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                  ...List<Widget>.generate(_foods.length, (index) {
                    final item = _foods[index];
                    final nutrition = widget.nutritionRepository.findByName(
                      item.name,
                    );
                    return Card(
                      key: ObjectKey(item),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: TextField(
                                    controller: item.nameController,
                                    decoration: InputDecoration(
                                      labelText: l10n.name,
                                    ),
                                    onChanged: (value) {
                                      setState(() {
                                        item.name = value;
                                        final match = widget.nutritionRepository
                                            .findByName(value.trim());
                                        if (match != null) {
                                          item.kcalPer100g = match.kcalPer100g;
                                          item.kcalController.text = match
                                              .kcalPer100g
                                              .toStringAsFixed(0);
                                        }
                                      });
                                    },
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _removeAt(index),
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: l10n.remove,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: TextField(
                                    controller: item.gramsController,
                                    decoration: InputDecoration(
                                      labelText: l10n.estimatedGrams,
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    onChanged: (value) {
                                      final parsed = _parseNumber(value.trim());
                                      if (parsed == null ||
                                          parsed <= 0 ||
                                          !(parsed * item.kcalPer100g)
                                              .isFinite) {
                                        return;
                                      }
                                      setState(() {
                                        item.grams = parsed;
                                        item.portionSize = 'custom';
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: item.kcalController,
                                    decoration: InputDecoration(
                                      labelText: l10n.kcalPer100g,
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    onChanged: (value) {
                                      final parsed = _parseNumber(value.trim());
                                      if (parsed == null ||
                                          parsed < 0 ||
                                          parsed > 1000 ||
                                          !(parsed * item.grams).isFinite) {
                                        return;
                                      }
                                      setState(() {
                                        item.kcalPer100g = parsed;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              key: ValueKey(item.portionSize),
                              initialValue: item.portionSize,
                              items:
                                  AppConstants.portionSizes
                                      .map(
                                        (portion) => DropdownMenuItem<String>(
                                          value: portion,
                                          child: Text(
                                            l10n.portionLabel(portion),
                                          ),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                setState(() {
                                  item.portionSize = value;
                                  if (value != 'custom' && nutrition != null) {
                                    final grams = nutrition.gramsForPortion(
                                      value,
                                    );
                                    item.grams = grams;
                                    item.gramsController.text = grams
                                        .toStringAsFixed(0);
                                  }
                                });
                              },
                              decoration: InputDecoration(
                                labelText: l10n.portionSize,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(l10n.estimatedCalories(_entryCalories(item))),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableFoodEntry {
  _EditableFoodEntry({
    this.id,
    required this.name,
    required this.grams,
    required this.kcalPer100g,
    required this.portionSize,
  }) : nameController = TextEditingController(text: name),
       gramsController = TextEditingController(text: grams.toStringAsFixed(0)),
       kcalController = TextEditingController(
         text: kcalPer100g.toStringAsFixed(0),
       );

  final int? id;
  String name;
  double grams;
  double kcalPer100g;
  String portionSize;

  final TextEditingController nameController;
  final TextEditingController gramsController;
  final TextEditingController kcalController;

  void dispose() {
    nameController.dispose();
    gramsController.dispose();
    kcalController.dispose();
  }
}
