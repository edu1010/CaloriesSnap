import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../models/ingredient.dart';
import '../../services/nutrition/food_search.dart';

/// What the user chose to add to the meal.
class PickedFood {
  const PickedFood({
    required this.name,
    required this.grams,
    required this.kcalPer100g,
    required this.portionSize,
  });

  final String name;
  final double grams;
  final double kcalPer100g;

  /// small / medium / large / custom, as in AppConstants.portionSizes.
  final String portionSize;
}

/// Opens the food picker: search the nutrition tables, choose how it was
/// prepared ("arroz" -> crudo / hervido / frito) and the portion.
///
/// [initial] opens straight on that food, e.g. one mentioned in the user's
/// description; [initialGrams] presets the weight they wrote.
Future<PickedFood?> showFoodSearchSheet(
  BuildContext context, {
  required NutritionRepository repository,
  FoodSearchHit? initial,
  double? initialGrams,
}) {
  return showModalBottomSheet<PickedFood>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder:
        (context) => FractionallySizedBox(
          heightFactor: 0.92,
          child: FoodSearchSheet(
            repository: repository,
            initial: initial,
            initialGrams: initialGrams,
          ),
        ),
  );
}

enum _Mode { search, detail, custom }

class FoodSearchSheet extends StatefulWidget {
  const FoodSearchSheet({
    super.key,
    required this.repository,
    this.initial,
    this.initialGrams,
  });

  final NutritionRepository repository;
  final FoodSearchHit? initial;
  final double? initialGrams;

  @override
  State<FoodSearchSheet> createState() => _FoodSearchSheetState();
}

class _FoodSearchSheetState extends State<FoodSearchSheet> {
  static const List<String> _portions = <String>['small', 'medium', 'large'];

  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _gramsController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _kcalController = TextEditingController();

  _Mode _mode = _Mode.search;
  Ingredient? _ingredient;
  int _variantIndex = 0;
  String _portion = 'medium';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _open(initial, grams: widget.initialGrams, notify: false);
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _gramsController.dispose();
    _nameController.dispose();
    _kcalController.dispose();
    super.dispose();
  }

  String get _language => Localizations.localeOf(context).languageCode;

  IngredientVariant get _variant => _ingredient!.variants[_variantIndex];

  double? _parse(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    return value != null && value.isFinite ? value : null;
  }

  void _open(FoodSearchHit hit, {double? grams, bool notify = true}) {
    void apply() {
      _mode = _Mode.detail;
      _ingredient = hit.ingredient;
      _variantIndex = hit.selectedIndex;
      if (grams != null && grams > 0) {
        _portion = 'custom';
        _gramsController.text = grams.toStringAsFixed(0);
      } else {
        _setPortion('medium');
      }
    }

    if (notify) {
      setState(apply);
    } else {
      apply();
    }
  }

  void _setPortion(String portion) {
    _portion = portion;
    final index = _portions.indexOf(portion);
    if (index < 0) return;
    final grams = _ingredient!.portionsOf(_variant)[index];
    _gramsController.text = grams.toStringAsFixed(0);
  }

  void _selectVariant(int index) {
    setState(() {
      _variantIndex = index;
      if (_portion != 'custom') _setPortion(_portion);
    });
  }

  void _startCustom() {
    setState(() {
      _mode = _Mode.custom;
      _nameController.text = _queryController.text.trim();
      _gramsController.text = '100';
      _kcalController.text = '';
    });
  }

  void _back() {
    setState(() {
      _mode = _Mode.search;
      _ingredient = null;
    });
  }

  void _addSelected() {
    final grams = _parse(_gramsController.text);
    if (grams == null || grams <= 0 || grams > 5000) {
      _showInvalid();
      return;
    }
    final ingredient = _ingredient!;
    Navigator.of(context).pop(
      PickedFood(
        name: ingredient.variantName(_variant, _language),
        grams: grams,
        kcalPer100g: _variant.kcalPer100g,
        portionSize: _portion,
      ),
    );
  }

  void _addCustom() {
    final name = _nameController.text.trim();
    final grams = _parse(_gramsController.text);
    final kcal = _parse(_kcalController.text);
    if (name.isEmpty ||
        grams == null ||
        grams <= 0 ||
        grams > 5000 ||
        kcal == null ||
        kcal < 0 ||
        kcal > 1000) {
      _showInvalid();
      return;
    }
    Navigator.of(context).pop(
      PickedFood(
        name: name,
        grams: grams,
        kcalPer100g: kcal,
        portionSize: 'custom',
      ),
    );
  }

  void _showInvalid() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.invalidFoodValues)));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: switch (_mode) {
        _Mode.search => _buildSearch(context),
        _Mode.detail => _buildDetail(context),
        _Mode.custom => _buildCustom(context),
      },
    );
  }

  Widget _buildSearch(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final hits = widget.repository.search.search(
      _queryController.text,
      languageCode: _language,
      limit: 60,
    );
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            key: const Key('food-search-field'),
            controller: _queryController,
            autofocus: widget.initial == null,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.searchFoodHint,
              border: const OutlineInputBorder(),
              suffixIcon:
                  _queryController.text.isEmpty
                      ? null
                      : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: l10n.cancel,
                        onPressed: () => setState(_queryController.clear),
                      ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: ListView(
            children: <Widget>[
              if (hits.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l10n.noFoodResults),
                ),
              for (final hit in hits) _buildHitTile(hit, theme),
              ListTile(
                leading: const Icon(Icons.edit_note_outlined),
                title: Text(l10n.customFood),
                onTap: _startCustom,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHitTile(FoodSearchHit hit, ThemeData theme) {
    final l10n = context.l10n;
    final ingredient = hit.ingredient;
    final String title;
    final String subtitle;
    if (ingredient.isDish) {
      title = ingredient.localizedName(_language);
      subtitle =
          '${l10n.dish} · ${ingredient.variants.first.kcalPer100g.toStringAsFixed(0)} kcal/100 g';
    } else if (hit.variantIndex != null) {
      title = ingredient.variantName(hit.variant, _language);
      subtitle = '${hit.variant.kcalPer100g.toStringAsFixed(0)} kcal/100 g';
    } else {
      title = ingredient.localizedName(_language);
      subtitle = ingredient.variants
          .map((variant) => ingredient.variantLabel(variant, _language))
          .join(' · ');
    }
    return ListTile(
      key: ValueKey<String>('food-hit-${ingredient.id}'),
      leading: Icon(
        ingredient.isDish ? Icons.restaurant_outlined : Icons.eco_outlined,
        color: theme.colorScheme.primary,
      ),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _open(hit),
    );
  }

  Widget _buildDetail(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final ingredient = _ingredient!;
    final variant = _variant;
    final grams = _parse(_gramsController.text) ?? 0;
    final kcal = grams * variant.kcalPer100g / 100;
    final portions = ingredient.portionsOf(variant);

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 16, 16),
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: _back,
                  ),
                  Expanded(
                    child: Text(
                      ingredient.variantName(variant, _language),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (ingredient.variants.length > 1) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(l10n.preparation, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: <Widget>[
                          for (var i = 0; i < ingredient.variants.length; i++)
                            ChoiceChip(
                              label: Text(
                                ingredient.variantLabel(
                                  ingredient.variants[i],
                                  _language,
                                ),
                              ),
                              selected: i == _variantIndex,
                              onSelected: (_) => _selectVariant(i),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    _NutritionPanel(variant: variant),
                    const SizedBox(height: 16),
                    Text(l10n.portionSize, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: <Widget>[
                        for (var i = 0; i < _portions.length; i++)
                          ChoiceChip(
                            label: Text(
                              '${l10n.portionLabel(_portions[i])} · ${portions[i].toStringAsFixed(0)} g',
                            ),
                            selected: _portion == _portions[i],
                            onSelected:
                                (_) => setState(() => _setPortion(_portions[i])),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('food-grams-field'),
                      controller: _gramsController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.grams,
                        suffixText: 'g',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() => _portion = 'custom'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.portionEnergy(grams, kcal),
                      style: theme.textTheme.titleMedium,
                    ),
                    if (!ingredient.isDish) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        l10n.nutritionSourceNote(
                          ciqualCode: variant.ciqualCode,
                          addedOilGrams: variant.addedOilGrams,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('food-add-button'),
              onPressed: _addSelected,
              icon: const Icon(Icons.add),
              label: Text(l10n.addToMeal),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustom(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 16, 16),
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: _back,
                  ),
                  Expanded(
                    child: Text(
                      l10n.customFood,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  children: <Widget>[
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(labelText: l10n.name),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _gramsController,
                      decoration: InputDecoration(labelText: l10n.grams),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _kcalController,
                      decoration: InputDecoration(labelText: l10n.kcalPer100g),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _addCustom,
              icon: const Icon(Icons.add),
              label: Text(l10n.addToMeal),
            ),
          ),
        ),
      ],
    );
  }
}

/// kcal and, when known, macronutrients per 100 g.
class _NutritionPanel extends StatelessWidget {
  const _NutritionPanel({required this.variant});

  final IngredientVariant variant;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    String format(double value) =>
        value == value.roundToDouble()
            ? value.toStringAsFixed(0)
            : value.toStringAsFixed(1);

    Widget cell(String label, String value) => Expanded(
      child: Column(
        children: <Widget>[
          Text(value, style: theme.textTheme.titleMedium),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.per100g, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                cell('kcal', format(variant.kcalPer100g)),
                if (variant.hasMacros) ...<Widget>[
                  cell(l10n.protein, '${format(variant.proteinPer100g!)} g'),
                  cell(l10n.carbs, '${format(variant.carbsPer100g!)} g'),
                  cell(l10n.fat, '${format(variant.fatPer100g!)} g'),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
