import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/l10n/meal_registration_localizations.dart';
import '../../core/utils/food_text.dart';
import '../../data/repositories/meal_repository.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../models/food_item.dart';
import '../../models/ingredient.dart';
import '../../services/nutrition/calorie_calculator.dart';
import '../../services/nutrition/food_search.dart';
import '../../services/food_detection/food_detection_service.dart';
import '../../services/food_detection/meal_analysis_service.dart';
import 'food_search_sheet.dart';
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
    this.description,
    this.photoAnalysisService,
    this.seedFromDescription = false,
    this.fromBarcode = false,
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

  /// What the user wrote about the dish; foods it names that are not in the
  /// list yet are offered as one-tap additions.
  final String? description;

  final MealAnalysisService? photoAnalysisService;
  final bool seedFromDescription;
  final bool fromBarcode;

  @override
  State<FoodConfirmationScreen> createState() => _FoodConfirmationScreenState();
}

class _FoodConfirmationScreenState extends State<FoodConfirmationScreen> {
  late final List<_EditableFoodEntry> _foods;
  _EditableFoodEntry? _selectedPhotoEntry;
  String? _selectedPhotoName;
  List<FoodSuggestion> _descriptionSuggestions = const <FoodSuggestion>[];
  final MealAnalysisCancellation _cancellation = MealAnalysisCancellation();
  List<DetectedFood>? _classifierCandidates;
  MealDetection? _advancedDetection;
  MealAnalysisStage? _stage;
  Object? _analysisError;
  bool _usedFallback = false;
  bool _draftEdited = false;
  bool _descriptionSeeded = false;

  @override
  void initState() {
    super.initState();
    final description = widget.description?.trim();
    if (description != null && description.isNotEmpty) {
      _descriptionSuggestions = widget.nutritionRepository.search
          .suggestFromText(description);
    }
    _foods = widget.initialFoods.map(_buildEntryFromFood).toList();
    if (widget.photoCandidates?.isNotEmpty == true && _foods.isNotEmpty) {
      _selectedPhotoEntry = _foods.first;
      _selectedPhotoName = _foods.first.name;
    }
    if (widget.photoAnalysisService != null && widget.imagePath != null) {
      _stage = MealAnalysisStage.classifying;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _analyzePhoto();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.seedFromDescription || _descriptionSeeded) return;
    _descriptionSeeded = true;
    final language = Localizations.localeOf(context).languageCode;
    for (final suggestion in _descriptionSuggestions) {
      final ingredient = suggestion.ingredient;
      final variant = suggestion.variant;
      final grams = suggestion.grams;
      final unresolved = suggestion.hasUnresolvedQuantity;
      _foods.add(
        _EditableFoodEntry(
          name: ingredient.variantName(variant, language),
          grams: grams ?? (unresolved ? 0 : ingredient.portionsOf(variant)[1]),
          kcalPer100g: variant.kcalPer100g,
          portionSize: grams == null && !unresolved ? 'medium' : 'custom',
          estimatedGrams:
              unresolved ? null : grams == null || suggestion.gramsEstimated,
          quantity: suggestion.quantity,
          preparationQuestion: _preparationQuestion(suggestion),
        ),
      );
    }
  }

  @override
  void dispose() {
    _cancellation.cancel();
    for (final item in _foods) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _analyzePhoto() async {
    final service = widget.photoAnalysisService!;
    final imagePath = widget.imagePath!;
    final language = Localizations.localeOf(context).languageCode;

    void onStage(MealAnalysisStage stage) {
      if (mounted) setState(() => _stage = stage);
    }

    try {
      final result =
          service is ProgressiveMealAnalysisService
              ? await service.analyzeProgressively(
                imagePath,
                languageCode: language,
                description: widget.description,
                onStage: onStage,
                onClassifierResult: _showClassifierResult,
                cancellation: _cancellation,
              )
              : await service.analyze(
                imagePath,
                languageCode: language,
                description: widget.description,
                onStage: onStage,
              );
      if (!mounted) return;
      if (result.engine == MealAnalysisEngine.classifier &&
          _classifierCandidates == null) {
        _showClassifierResult(result);
      }
      setState(() {
        _stage = null;
        _usedFallback = result.vlmFailure != null;
        if (result.engine == MealAnalysisEngine.vlm) {
          _advancedDetection = result;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = null;
        _analysisError = error;
      });
    }
  }

  void _showClassifierResult(MealDetection result) {
    if (!mounted) return;
    setState(() {
      _classifierCandidates = result.candidates;
      if (_foods.isEmpty && !_draftEdited && result.foods.isNotEmpty) {
        final candidate = result.foods.first;
        final entry = _entryFromDetection(candidate);
        _foods.add(entry);
        _selectedPhotoEntry = entry;
        _selectedPhotoName = candidate.name;
      }
    });
  }

  _EditableFoodEntry _entryFromDetection(DetectedFood food) =>
      _EditableFoodEntry(
        name: food.name,
        grams: food.suggestedGrams,
        kcalPer100g: food.kcalPer100g,
        portionSize: _guessPortion(food.name, food.suggestedGrams),
        estimatedGrams: true,
        estimatedNutrition: food.estimatedNutrition,
      );

  _PreparationQuestion? _preparationQuestion(FoodSuggestion suggestion) {
    if (suggestion.grams == null ||
        suggestion.gramsEstimated ||
        suggestion.preparationSpecified) {
      return null;
    }
    final ingredient = suggestion.ingredient;
    IngredientVariant? raw;
    IngredientVariant? cooked;
    for (final variant in ingredient.variants) {
      if (variant.preparation == Preparation.raw) raw = variant;
      if (variant.preparation == Preparation.boiled ||
          variant.preparation == Preparation.cooked) {
        cooked ??= variant;
      }
    }
    if (raw == null ||
        cooked == null ||
        (raw.kcalPer100g - cooked.kcalPer100g).abs() < 75) {
      return null;
    }
    return _PreparationQuestion(ingredient, raw, cooked);
  }

  _EditableFoodEntry _buildEntryFromFood(FoodItem food) {
    return _EditableFoodEntry(
      id: food.id,
      name: food.name,
      grams: food.grams,
      kcalPer100g: food.kcalPer100g,
      portionSize: _guessPortion(food.name, food.grams),
      estimatedGrams:
          widget.detection != null || widget.photoCandidates != null
              ? true
              : null,
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
      _draftEdited = true;
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
      _draftEdited = true;
      final previous = _selectedPhotoEntry;
      if (_selectedPhotoName == candidate.name && previous != null) return;
      if (_alreadyListed(candidate, except: previous)) return;
      final entry = _entryFromDetection(candidate);
      if (previous == null) {
        _foods.insert(0, entry);
      } else {
        final index = _foods.indexOf(previous);
        if (previous.estimatedGrams == false) {
          entry.grams = previous.grams;
          entry.gramsController.text = previous.gramsController.text;
          entry.portionSize = 'custom';
          entry.estimatedGrams = false;
          entry.edited = true;
        }
        _foods[index] = entry;
        previous.dispose();
      }
      _selectedPhotoEntry = entry;
      _selectedPhotoName = candidate.name;
    });
  }

  String _foodKey(String name) {
    final known = widget.nutritionRepository.findByName(name.trim());
    return foodWords(known?.name ?? name).map(singularFoodWord).join(' ');
  }

  _EditableFoodEntry? _matchingEntry(
    DetectedFood food, {
    _EditableFoodEntry? except,
  }) {
    final key = _foodKey(food.name);
    for (final item in _foods) {
      if (!identical(item, except) &&
          _foodKey(item.nameController.text) == key) {
        return item;
      }
    }
    return null;
  }

  bool _alreadyListed(DetectedFood food, {_EditableFoodEntry? except}) =>
      _matchingEntry(food, except: except) != null;

  void _applySuggestedWeight(_EditableFoodEntry item, double suggestedGrams) {
    setState(() {
      _draftEdited = true;
      item.edited = true;
      item.grams = suggestedGrams;
      item.gramsController.text = _quantityText(suggestedGrams);
      item.portionSize = 'custom';
      item.quantity = null;
    });
  }

  void _addAdvancedFoods(Iterable<DetectedFood> foods, {bool replace = false}) {
    setState(() {
      _draftEdited = true;
      final photo = _selectedPhotoEntry;
      if (replace && photo != null && !photo.edited) {
        _foods.remove(photo);
        photo.dispose();
        _selectedPhotoEntry = null;
        _selectedPhotoName = null;
      }
      for (final food in foods) {
        if (!_alreadyListed(food)) _foods.add(_entryFromDetection(food));
      }
    });
  }

  void _setPreparation(_EditableFoodEntry item, IngredientVariant variant) {
    final question = item.preparationQuestion!;
    final language = Localizations.localeOf(context).languageCode;
    setState(() {
      _draftEdited = true;
      item.edited = true;
      item.name = question.ingredient.variantName(variant, language);
      item.nameController.text = item.name;
      item.kcalPer100g = variant.kcalPer100g;
      item.kcalController.text = _quantityText(variant.kcalPer100g);
      item.preparationQuestion = null;
    });
  }

  /// Opens the food search. [initial] jumps straight to one food (e.g. one
  /// named in the description) with [grams] preset when the user wrote them.
  Future<void> _addFood({
    FoodSearchHit? initial,
    double? grams,
    bool inputEstimated = false,
  }) async {
    final picked = await showFoodSearchSheet(
      context,
      repository: widget.nutritionRepository,
      initial: initial,
      initialGrams: grams,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _draftEdited = true;
      _foods.add(
        _EditableFoodEntry(
          name: picked.name,
          grams: picked.grams,
          kcalPer100g: picked.kcalPer100g,
          portionSize: picked.portionSize,
          estimatedGrams:
              picked.portionSize != 'custom' ||
              (inputEstimated && picked.grams == grams),
        ),
      );
    });
  }

  /// Foods from the description that no listed item already covers.
  List<FoodSuggestion> get _pendingSuggestions {
    if (_descriptionSuggestions.isEmpty) return const <FoodSuggestion>[];
    final listed =
        _foods
            .map(
              (item) =>
                  foodWords(
                    item.nameController.text,
                  ).map(singularFoodWord).toSet(),
            )
            .toList();
    bool covered(String name) {
      final words = foodWords(name).map(singularFoodWord).toSet();
      return words.isNotEmpty && listed.any((item) => item.containsAll(words));
    }

    return _descriptionSuggestions.where((suggestion) {
      final ingredient = suggestion.ingredient;
      final names = <String>[
        ingredient.nameEs,
        ingredient.name,
        ...ingredient.aliases,
        ingredient.variantName(suggestion.variant, 'es'),
        ingredient.variantName(suggestion.variant, 'en'),
      ];
      return !names.any(covered);
    }).toList();
  }

  List<Widget> _buildMissingSection(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final suggestions = _pendingSuggestions;
    return <Widget>[
      Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l10n.missingIngredient,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('add-missing-ingredient'),
                    onPressed: () => _addFood(),
                    icon: const Icon(Icons.search),
                    label: Text(l10n.addIngredient),
                  ),
                ],
              ),
              if (suggestions.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(l10n.fromYourDescription),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: <Widget>[
                    for (final suggestion in suggestions)
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: Text(
                          suggestion.ingredient.variantName(
                            suggestion.variant,
                            language,
                          ),
                        ),
                        onPressed:
                            () => _addFood(
                              initial: FoodSearchHit(
                                suggestion.ingredient,
                                variantIndex: suggestion.variantIndex,
                              ),
                              grams: suggestion.grams,
                              inputEstimated: suggestion.gramsEstimated,
                            ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ];
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

  bool get _isPhotoFlow =>
      widget.detection != null ||
      widget.photoCandidates != null ||
      widget.photoAnalysisService != null ||
      widget.seedFromDescription ||
      _descriptionSuggestions.isNotEmpty;

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

  Widget _buildAdvancedSuggestions(
    BuildContext context,
    MealDetection detection,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final suggestions =
        detection.foods.where((food) => !_alreadyListed(food)).toList();
    final weights = <({_EditableFoodEntry entry, DetectedFood food})>[];
    for (final food in detection.foods) {
      final entry = _matchingEntry(food);
      if (entry != null &&
          !entry.edited &&
          entry.estimatedGrams == true &&
          (entry.grams - food.suggestedGrams).abs() >= 5) {
        weights.add((entry: entry, food: food));
      }
    }
    final estimated =
        suggestions
            .where((food) => food.estimatedNutrition)
            .map((food) => food.name)
            .toList();
    final canReplace =
        detection.foods.length > 1 &&
        _selectedPhotoEntry?.edited == false &&
        suggestions.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.advancedSuggestions, style: theme.textTheme.titleSmall),
            if (detection.dishName case final dish? when dish.isNotEmpty)
              Text(dish),
            if (suggestions.isEmpty && weights.isEmpty)
              Text(l10n.nothingToAdd)
            else
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final food in suggestions)
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: Text(
                        l10n.suggestedPortion(
                          food.name,
                          _quantityText(food.suggestedGrams),
                        ),
                      ),
                      onPressed: () => _addAdvancedFoods(<DetectedFood>[food]),
                    ),
                  for (final adjustment in weights)
                    ActionChip(
                      avatar: const Icon(
                        Icons.monitor_weight_outlined,
                        size: 18,
                      ),
                      label: Text(
                        l10n.adjustToSuggestedPortion(
                          adjustment.food.name,
                          _quantityText(adjustment.food.suggestedGrams),
                        ),
                      ),
                      onPressed:
                          () => _applySuggestedWeight(
                            adjustment.entry,
                            adjustment.food.suggestedGrams,
                          ),
                    ),
                ],
              ),
            if (canReplace) ...<Widget>[
              Text(l10n.reviewAiBreakdownHelp),
              TextButton(
                onPressed:
                    () => _addAdvancedFoods(detection.foods, replace: true),
                child: Text(l10n.reviewAiBreakdown),
              ),
            ],
            if (estimated.isNotEmpty)
              Text(
                l10n.aiEstimatedEnergy(estimated.join(', ')),
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  String _stageLabel(AppLocalizations l10n, MealAnalysisStage stage) =>
      switch (stage) {
        MealAnalysisStage.classifying => l10n.detectingFoods,
        MealAnalysisStage.loadingModel => l10n.loadingAiModel,
        MealAnalysisStage.analyzing => l10n.analyzingWithAi,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasImage =
        widget.imagePath != null &&
        widget.imagePath!.isNotEmpty &&
        File(widget.imagePath!).existsSync();
    final classifierCandidates =
        _classifierCandidates ?? widget.photoCandidates;
    final stage = _stage;
    final analysisError = _analysisError;
    final advancedDetection = _advancedDetection;

    return Scaffold(
      appBar: AppBar(
        title: Text(hasImage ? l10n.confirmDetectedFoods : l10n.confirmFoods),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addFood(),
        icon: const Icon(Icons.add),
        label: Text(l10n.addFood),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (hasImage || widget.fromBarcode)
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
                              cacheWidth: 1200,
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
                    label: Text(
                      stage == null || _foods.isEmpty
                          ? l10n.continueText
                          : l10n.saveWithoutWaiting,
                    ),
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
                // Room below the last card for the floating button.
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                children: <Widget>[
                  if (stage != null) ...<Widget>[
                    Text(
                      _stageLabel(l10n, stage),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 6, bottom: 12),
                      child: LinearProgressIndicator(),
                    ),
                  ],
                  if (analysisError != null)
                    Text(l10n.failedToProcessImage(analysisError)),
                  if (_usedFallback ||
                      widget.detection?.vlmFailure != null) ...<Widget>[
                    Text(
                      l10n.aiFallbackNotice,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_analyzedByVlm)
                    ..._buildVlmSummary(context)
                  else if (classifierCandidates != null &&
                      (classifierCandidates.isNotEmpty ||
                          stage == null)) ...<Widget>[
                    Text(l10n.photoPortionHint),
                    const SizedBox(height: 8),
                    if (classifierCandidates.isEmpty)
                      Text(l10n.noReliableDish)
                    else ...<Widget>[
                      Text(
                        l10n.possibleDish,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (classifierCandidates.first.requiresConfirmation)
                        Text(l10n.uncertainDish),
                      Text(l10n.alternativeDishes),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children:
                            classifierCandidates
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
                  if (advancedDetection != null)
                    _buildAdvancedSuggestions(context, advancedDetection),
                  if (_isPhotoFlow) ..._buildMissingSection(context),
                  ...List<Widget>.generate(_foods.length, (index) {
                    final item = _foods[index];
                    final nutrition = widget.nutritionRepository.findByName(
                      item.name,
                    );
                    final question = item.preparationQuestion;
                    final quantity = item.quantity;
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
                                        _draftEdited = true;
                                        item.edited = true;
                                        item.preparationQuestion = null;
                                        item.name = value;
                                        final match = widget.nutritionRepository
                                            .findByName(value.trim());
                                        if (match != null) {
                                          item.kcalPer100g = match.kcalPer100g;
                                          item.kcalController.text =
                                              _quantityText(match.kcalPer100g);
                                          item.estimatedNutrition = false;
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  child: TextField(
                                    controller: item.gramsController,
                                    decoration: InputDecoration(
                                      labelText: switch (item.estimatedGrams) {
                                        true => l10n.estimatedGrams,
                                        false => l10n.currentWeight,
                                        null => l10n.grams,
                                      },
                                      helperText:
                                          quantity == null
                                              ? null
                                              : item.grams <= 0
                                              ? l10n.enterQuantityWeight(
                                                quantity.text,
                                              )
                                              : item.estimatedGrams == true
                                              ? l10n.convertedQuantity(
                                                quantity.text,
                                              )
                                              : null,
                                      helperMaxLines: 2,
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
                                        _draftEdited = true;
                                        item.edited = true;
                                        item.grams = parsed;
                                        item.portionSize = 'custom';
                                        item.estimatedGrams = false;
                                        item.quantity = null;
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
                                      helperText:
                                          item.estimatedNutrition
                                              ? l10n.energyEstimatedByAi
                                              : null,
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
                                        _draftEdited = true;
                                        item.edited = true;
                                        item.preparationQuestion = null;
                                        item.kcalPer100g = parsed;
                                        item.estimatedNutrition = false;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                            if (question != null) ...<Widget>[
                              const SizedBox(height: 8),
                              Text(l10n.weighedRawOrCooked),
                              Wrap(
                                spacing: 8,
                                children: <Widget>[
                                  ActionChip(
                                    label: Text(l10n.rawWeight),
                                    onPressed:
                                        () =>
                                            _setPreparation(item, question.raw),
                                  ),
                                  ActionChip(
                                    label: Text(l10n.cookedWeight),
                                    onPressed:
                                        () => _setPreparation(
                                          item,
                                          question.cooked,
                                        ),
                                  ),
                                ],
                              ),
                            ],
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
                                  _draftEdited = true;
                                  item.edited = true;
                                  item.portionSize = value;
                                  if (value != 'custom' && nutrition != null) {
                                    final grams = nutrition.gramsForPortion(
                                      value,
                                    );
                                    item.grams = grams;
                                    item.gramsController.text = _quantityText(
                                      grams,
                                    );
                                    item.estimatedGrams = true;
                                    item.quantity = null;
                                    item.preparationQuestion = null;
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
    this.estimatedGrams,
    this.estimatedNutrition = false,
    this.preparationQuestion,
    this.quantity,
  }) : nameController = TextEditingController(text: name),
       gramsController = TextEditingController(
         text: grams > 0 ? _quantityText(grams) : '',
       ),
       kcalController = TextEditingController(text: _quantityText(kcalPer100g));

  final int? id;
  String name;
  double grams;
  double kcalPer100g;
  String portionSize;
  bool? estimatedGrams;
  bool estimatedNutrition;
  bool edited = false;
  _PreparationQuestion? preparationQuestion;
  FoodQuantity? quantity;

  final TextEditingController nameController;
  final TextEditingController gramsController;
  final TextEditingController kcalController;

  void dispose() {
    nameController.dispose();
    gramsController.dispose();
    kcalController.dispose();
  }
}

class _PreparationQuestion {
  const _PreparationQuestion(this.ingredient, this.raw, this.cooked);

  final Ingredient ingredient;
  final IngredientVariant raw;
  final IngredientVariant cooked;
}

String _quantityText(double quantity) =>
    quantity.toString().replaceFirst(RegExp(r'\.0$'), '');
