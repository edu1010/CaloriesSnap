import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../models/calorie_goals.dart';
import 'activity_format.dart';
import 'activity_widgets.dart';

class GoalsCard extends StatelessWidget {
  const GoalsCard({super.key, required this.goals, required this.onEdit});

  final CalorieGoals goals;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final format = ActivityFormat.of(context);

    String goalText(double? kcal) {
      return kcal == null ? l10n.notSet : l10n.kcalAmount(format.whole(kcal));
    }

    return SectionCard(
      title: l10n.intakeGoals,
      icon: Icons.flag_outlined,
      trailing: IconButton(
        key: const Key('edit_goals_button'),
        onPressed: onEdit,
        icon: const Icon(Icons.edit_outlined),
        tooltip: l10n.editGoals,
      ),
      children: <Widget>[
        MetricLine(
          key: const Key('daily_goal_line'),
          icon: Icons.today_outlined,
          label: l10n.dailyGoal,
          value: goalText(goals.dailyKcal),
        ),
        MetricLine(
          key: const Key('weekly_goal_line'),
          icon: Icons.date_range_outlined,
          label: l10n.weeklyGoal,
          value: goalText(goals.weeklyKcal),
        ),
        Text(
          l10n.goalsIndependentHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Edits both goals. Pops with the new [CalorieGoals], or null on cancel.
/// Fields start from the saved values only: nothing is suggested and the
/// weekly goal is never derived from the daily one.
class GoalEditorDialog extends StatefulWidget {
  const GoalEditorDialog({super.key, required this.goals});

  final CalorieGoals goals;

  @override
  State<GoalEditorDialog> createState() => _GoalEditorDialogState();
}

class _GoalEditorDialogState extends State<GoalEditorDialog> {
  static final RegExp _wholePattern = RegExp(r'^\d{1,9}$');

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _dailyController;
  late final TextEditingController _weeklyController;

  @override
  void initState() {
    super.initState();
    _dailyController = TextEditingController(
      text: _initialText(widget.goals.dailyKcal),
    );
    _weeklyController = TextEditingController(
      text: _initialText(widget.goals.weeklyKcal),
    );
  }

  @override
  void dispose() {
    _dailyController.dispose();
    _weeklyController.dispose();
    super.dispose();
  }

  String _initialText(double? kcal) => kcal == null ? '' : '${kcal.round()}';

  double? _parse(String text) {
    final trimmed = text.trim();
    return _wholePattern.hasMatch(trimmed) ? double.parse(trimmed) : null;
  }

  String? _validate(
    String? text,
    bool Function(double? value) isValid,
    double max,
  ) {
    final trimmed = (text ?? '').trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final value = _parse(trimmed);
    if (value == null || !isValid(value)) {
      return context.l10n.goalInvalid(ActivityFormat.of(context).whole(max));
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      CalorieGoals(
        dailyKcal: _parse(_dailyController.text),
        weeklyKcal: _parse(_weeklyController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return AlertDialog(
      scrollable: true,
      title: Text(l10n.editGoals),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.goalsEditorHint, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('goal_daily_field'),
              controller: _dailyController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.dailyGoalFieldLabel,
                errorMaxLines: 3,
              ),
              validator:
                  (text) => _validate(
                    text,
                    CalorieGoals.isValidDaily,
                    CalorieGoals.maxDailyKcal,
                  ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('goal_weekly_field'),
              controller: _weeklyController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: l10n.weeklyGoalFieldLabel,
                errorMaxLines: 3,
              ),
              validator:
                  (text) => _validate(
                    text,
                    CalorieGoals.isValidWeekly,
                    CalorieGoals.maxWeeklyKcal,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.goalsIndependentHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('goal_save_button'),
          onPressed: _submit,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
