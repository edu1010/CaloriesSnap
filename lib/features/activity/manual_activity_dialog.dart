import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../models/daily_activity.dart';
import 'activity_format.dart';

class ManualActivityResult {
  const ManualActivityResult.save(DailyActivity this.activity) : delete = false;

  const ManualActivityResult.delete() : activity = null, delete = true;

  final DailyActivity? activity;
  final bool delete;
}

enum _Field { activeKcal, totalKcal, steps, distanceMeters, activeMinutes }

/// Adds, edits or deletes the manual record of [date]. Pops with a
/// [ManualActivityResult], or null on cancel; the caller persists it.
class ManualActivityDialog extends StatefulWidget {
  const ManualActivityDialog({
    super.key,
    required this.date,
    this.existing,
    this.imported,
  });

  final DateTime date;

  /// The stored manual record of the day, when there is one.
  final DailyActivity? existing;

  /// The imported record that is used when the day has no manual entry.
  final DailyActivity? imported;

  @override
  State<ManualActivityDialog> createState() => _ManualActivityDialogState();
}

class _ManualActivityDialogState extends State<ManualActivityDialog> {
  static final RegExp _wholePattern = RegExp(r'^\d{1,9}$');
  static final RegExp _decimalPattern = RegExp(r'^\d{1,7}([.,]\d{1,3})?$');

  late final Map<_Field, TextEditingController> _controllers;
  Map<_Field, String> _errors = <_Field, String>{};
  String? _formError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final distance = existing?.distanceMeters;
    _controllers = <_Field, TextEditingController>{
      _Field.activeKcal: TextEditingController(
        text: _wholeText(existing?.activeKcal),
      ),
      _Field.totalKcal: TextEditingController(
        text: _wholeText(existing?.totalKcal),
      ),
      _Field.steps: TextEditingController(text: _wholeText(existing?.steps)),
      _Field.distanceMeters: TextEditingController(
        text: distance == null ? '' : _trimZeros(distance / 1000),
      ),
      _Field.activeMinutes: TextEditingController(
        text: _wholeText(existing?.activeMinutes),
      ),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _wholeText(num? value) => value == null ? '' : '${value.round()}';

  String _trimZeros(double value) {
    final text = value.toStringAsFixed(3);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  void _submit() {
    final l10n = context.l10n;
    final errors = <_Field, String>{};

    double? whole(_Field field) {
      final text = _controllers[field]!.text.trim();
      if (text.isEmpty) {
        return null;
      }
      if (!_wholePattern.hasMatch(text)) {
        errors[field] = l10n.invalidWholeNumber;
        return null;
      }
      return double.parse(text);
    }

    double? decimal(_Field field) {
      final text = _controllers[field]!.text.trim();
      if (text.isEmpty) {
        return null;
      }
      if (!_decimalPattern.hasMatch(text)) {
        errors[field] = l10n.invalidDecimalNumber;
        return null;
      }
      return double.parse(text.replaceAll(',', '.'));
    }

    final activeKcal = whole(_Field.activeKcal);
    final totalKcal = whole(_Field.totalKcal);
    final steps = whole(_Field.steps);
    final distanceKm = decimal(_Field.distanceMeters);
    final activeMinutes = whole(_Field.activeMinutes);

    if (errors.isNotEmpty) {
      setState(() {
        _errors = errors;
        _formError = null;
      });
      return;
    }

    final activity = DailyActivity(
      date: DateTime(widget.date.year, widget.date.month, widget.date.day),
      source: ActivitySource.manual,
      updatedAt: DateTime.now(),
      activeKcal: activeKcal,
      totalKcal: totalKcal,
      steps: steps?.round(),
      distanceMeters: distanceKm == null ? null : distanceKm * 1000,
      activeMinutes: activeMinutes?.round(),
    );

    if (!activity.hasAnyMetric) {
      setState(() {
        _errors = errors;
        _formError = l10n.manualNeedsOneValue;
      });
      return;
    }

    final invalid = activity.invalidField;
    if (invalid != null) {
      final field = _Field.values.firstWhere(
        (candidate) => candidate.name == invalid,
        orElse: () => _Field.activeKcal,
      );
      final activeAlone = DailyActivity(
        date: activity.date,
        source: activity.source,
        updatedAt: activity.updatedAt,
        activeKcal: activeKcal,
      );
      final exceedsTotal =
          field == _Field.activeKcal && activeAlone.invalidField == null;
      setState(() {
        _errors = <_Field, String>{
          field: exceedsTotal ? l10n.activeExceedsTotal : l10n.valueOutOfRange,
        };
        _formError = null;
      });
      return;
    }

    Navigator.of(context).pop(ManualActivityResult.save(activity));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = dialogContext.l10n;
        final imported = widget.imported;
        return AlertDialog(
          scrollable: true,
          title: Text(l10n.deleteManualEntry),
          content: Text(
            imported == null
                ? l10n.deleteManualEntryConfirm
                : l10n.manualFallbackNote(
                  activitySourceName(l10n, imported.source),
                ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const Key('manual_delete_confirm_button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    Navigator.of(context).pop(const ManualActivityResult.delete());
  }

  Widget _field(
    _Field field,
    String label, {
    String? helper,
    bool decimal = false,
    bool last = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: Key('manual_${field.name}_field'),
        controller: _controllers[field],
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        textInputAction: last ? TextInputAction.done : TextInputAction.next,
        onSubmitted: last ? (_) => _submit() : null,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          errorText: _errors[field],
          errorMaxLines: 3,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final format = ActivityFormat.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final imported = widget.imported;

    return AlertDialog(
      scrollable: true,
      title: Text(l10n.manualActivityTitle(format.longDate(widget.date))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.manualAllOptionalHint, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(
            l10n.manualReplacesImportedNote,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 4),
          Text(
            imported == null
                ? l10n.manualFallbackGenericNote
                : l10n.manualFallbackNote(
                  activitySourceName(l10n, imported.source),
                ),
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 16),
          _field(_Field.activeKcal, l10n.activeKcalField),
          _field(
            _Field.totalKcal,
            l10n.totalKcalField,
            helper: l10n.totalKcalHelper,
          ),
          _field(_Field.steps, l10n.steps),
          _field(_Field.distanceMeters, l10n.distanceKmField, decimal: true),
          _field(_Field.activeMinutes, l10n.activeMinutes, last: true),
          if (_formError != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _formError!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      actions: <Widget>[
        if (widget.existing != null)
          TextButton.icon(
            key: const Key('manual_delete_button'),
            onPressed: _confirmDelete,
            icon: const Icon(Icons.delete_outline),
            label: Text(l10n.delete),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('manual_save_button'),
          onPressed: _submit,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
