import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../models/daily_activity.dart';
import '../../models/energy_summary.dart';
import 'activity_format.dart';
import 'activity_widgets.dart';

class TodayPanel extends StatelessWidget {
  const TodayPanel({
    super.key,
    required this.day,
    required this.canSync,
    required this.syncing,
    required this.onEditManual,
    required this.onSync,
  });

  final DayEnergy day;

  /// True when a sync provider is ready, so the empty state can offer it.
  final bool canSync;
  final bool syncing;
  final VoidCallback onEditManual;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final format = ActivityFormat.of(context);
    final activity = day.activity;
    final goal = day.goalKcal;

    return SectionCard(
      key: const Key('today_panel'),
      title: l10n.todayWithDate(format.longDate(day.date)),
      icon: Icons.today_outlined,
      children: <Widget>[
        MetricLine(
          icon: Icons.restaurant_menu_outlined,
          label: l10n.consumed,
          value: l10n.kcalAmount(format.whole(day.consumedKcal)),
          detail: l10n.mealsCountLabel(day.mealsCount),
        ),
        if (goal == null)
          InfoLine(text: l10n.noDailyGoalSet, icon: Icons.flag_outlined)
        else ...<Widget>[
          MetricLine(
            icon: Icons.flag_outlined,
            label: l10n.dailyGoal,
            value: l10n.kcalAmount(format.whole(goal)),
          ),
          GoalProgress(consumedKcal: day.consumedKcal, goalKcal: goal),
        ],
        const Divider(height: 24),
        if (activity == null)
          _EmptyActivity(
            canSync: canSync,
            syncing: syncing,
            onEditManual: onEditManual,
            onSync: onSync,
          )
        else
          ..._activityLines(context, activity),
      ],
    );
  }

  List<Widget> _activityLines(BuildContext context, DailyActivity activity) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final format = ActivityFormat.of(context);
    final net = day.netKcal;
    final isManual = activity.source == ActivitySource.manual;
    final origin = activity.origin;

    return <Widget>[
      MetricLine(
        icon: Icons.local_fire_department_outlined,
        label: l10n.activeBurned,
        value:
            activity.activeKcal == null
                ? null
                : l10n.kcalAmount(format.whole(activity.activeKcal!)),
      ),
      if (activity.totalKcal != null)
        MetricLine(
          icon: Icons.whatshot_outlined,
          label: l10n.totalBurned,
          value: l10n.kcalAmount(format.whole(activity.totalKcal!)),
        ),
      if (net == null)
        InfoLine(
          key: const Key('today_net_unavailable'),
          text: l10n.netEnergyUnavailable,
        )
      else
        MetricLine(
          key: const Key('today_net'),
          icon: Icons.balance_outlined,
          label: l10n.netEnergy,
          value: l10n.kcalAmount(format.signedWhole(net)),
          detail: l10n.netEnergyExplanation,
        ),
      if (activity.steps != null)
        MetricLine(
          icon: Icons.directions_walk_outlined,
          label: l10n.steps,
          value: format.whole(activity.steps!),
        ),
      if (activity.distanceMeters != null)
        MetricLine(
          icon: Icons.straighten_outlined,
          label: l10n.distance,
          value: l10n.distanceKm(format.kilometres(activity.distanceMeters!)),
        ),
      if (activity.activeMinutes != null)
        MetricLine(
          icon: Icons.timer_outlined,
          label: l10n.activeMinutes,
          value: l10n.minutesAmount(format.whole(activity.activeMinutes!)),
        ),
      Text(
        l10n.dataSource(activitySourceName(l10n, activity.source)),
        key: const Key('today_source'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      if (origin != null && origin.isNotEmpty)
        Text(
          l10n.dataOrigin(origin),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      if (!isManual) ...<Widget>[
        const SizedBox(height: 4),
        Text(
          l10n.manualReplacesImportedNote,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const Key('today_manual_button'),
        onPressed: onEditManual,
        icon: Icon(isManual ? Icons.edit_outlined : Icons.edit_note_outlined),
        label: Text(isManual ? l10n.editManualEntry : l10n.enterManually),
      ),
    ];
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({
    required this.canSync,
    required this.syncing,
    required this.onEditManual,
    required this.onSync,
  });

  final bool canSync;
  final bool syncing;
  final VoidCallback onEditManual;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Column(
      key: const Key('today_no_activity'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.sensors_off_outlined, color: muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.noActivityToday,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          l10n.noActivityHint,
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: 12),
        InfoLine(
          key: const Key('today_net_unavailable'),
          text: l10n.netEnergyUnavailable,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.tonalIcon(
              key: const Key('today_manual_button'),
              onPressed: onEditManual,
              icon: const Icon(Icons.edit_note_outlined),
              label: Text(l10n.enterManually),
            ),
            if (canSync)
              OutlinedButton.icon(
                key: const Key('today_sync_button'),
                onPressed: syncing ? null : onSync,
                icon: const Icon(Icons.sync),
                label: Text(l10n.synchroniseNow),
              ),
          ],
        ),
      ],
    );
  }
}
