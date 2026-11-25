import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../models/energy_summary.dart';
import 'activity_format.dart';
import 'activity_widgets.dart';

class WeekPanel extends StatelessWidget {
  const WeekPanel({
    super.key,
    required this.week,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
    required this.onDayTap,
  });

  final WeekEnergy week;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final format = ActivityFormat.of(context);
    final elapsed = week.elapsedDays;
    final goal = week.goalKcal;
    final active = week.activeBurnedKcal;
    final total = week.totalBurnedKcal;
    final net = week.netKcal;
    final steps = week.steps;
    final distance = week.distanceMeters;
    final minutes = week.activeMinutes;

    return SectionCard(
      key: const Key('week_panel'),
      title: l10n.week,
      subtitle: l10n.dateRange(
        format.dayMonth(week.days.first.date),
        format.fullDate(week.days.last.date),
      ),
      icon: Icons.date_range_outlined,
      leading: IconButton(
        key: const Key('previous_week_button'),
        onPressed: onPrevious,
        icon: const Icon(Icons.chevron_left),
        tooltip: l10n.previousWeek,
      ),
      trailing: IconButton(
        key: const Key('next_week_button'),
        onPressed: canGoNext ? onNext : null,
        icon: const Icon(Icons.chevron_right),
        tooltip: l10n.nextWeek,
      ),
      children: <Widget>[
        MetricLine(
          key: const Key('week_consumed'),
          icon: Icons.restaurant_menu_outlined,
          label: l10n.consumed,
          value: l10n.kcalAmount(format.whole(week.consumedKcal)),
          detail: l10n.mealsLoggedOnDays(week.daysWithMeals),
        ),
        if (goal == null)
          InfoLine(text: l10n.noWeeklyGoalSet, icon: Icons.flag_outlined)
        else ...<Widget>[
          MetricLine(
            icon: Icons.flag_outlined,
            label: l10n.weeklyGoal,
            value: l10n.kcalAmount(format.whole(goal)),
          ),
          GoalProgress(consumedKcal: week.consumedKcal, goalKcal: goal),
        ],
        const Divider(height: 24),
        MetricLine(
          key: const Key('week_active'),
          icon: Icons.local_fire_department_outlined,
          label: l10n.activeBurned,
          value: active == null ? null : l10n.kcalAmount(format.whole(active)),
          detail: l10n.dataForDays(week.daysWithActiveBurned, elapsed),
        ),
        MetricLine(
          key: const Key('week_total'),
          icon: Icons.whatshot_outlined,
          label: l10n.totalBurned,
          value: total == null ? null : l10n.kcalAmount(format.whole(total)),
          detail: l10n.dataForDays(week.daysWithTotalBurned, elapsed),
        ),
        if (net == null)
          InfoLine(
            key: const Key('week_net_unavailable'),
            text: l10n.netEnergyUnavailable,
          )
        else
          MetricLine(
            key: const Key('week_net'),
            icon: Icons.balance_outlined,
            label: l10n.netEnergy,
            value: l10n.kcalAmount(format.signedWhole(net)),
            detail:
                week.isNetComplete
                    ? l10n.netCompleteDays(elapsed)
                    : l10n.netPartialDays(week.daysWithTotalBurned, elapsed),
          ),
        if (steps != null)
          MetricLine(
            icon: Icons.directions_walk_outlined,
            label: l10n.steps,
            value: format.whole(steps),
            detail: l10n.dataForDays(week.daysWithSteps, elapsed),
          ),
        if (distance != null)
          MetricLine(
            icon: Icons.straighten_outlined,
            label: l10n.distance,
            value: l10n.distanceKm(format.kilometres(distance)),
            detail: l10n.dataForDays(week.daysWithDistance, elapsed),
          ),
        if (minutes != null)
          MetricLine(
            icon: Icons.timer_outlined,
            label: l10n.activeMinutes,
            value: l10n.minutesAmount(format.whole(minutes)),
            detail: l10n.dataForDays(week.daysWithActiveMinutes, elapsed),
          ),
        const Divider(height: 24),
        _DayTable(week: week, onDayTap: onDayTap),
        const SizedBox(height: 8),
        Text(
          l10n.tapDayToEditHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DayTable extends StatelessWidget {
  const _DayTable({required this.week, required this.onDayTap});

  final WeekEnergy week;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    var scale = 0.0;
    for (final day in week.days) {
      scale = math.max(scale, day.consumedKcal);
      scale = math.max(scale, day.goalKcal ?? 0);
    }

    return Column(
      children: <Widget>[
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: Text(l10n.dayColumn, style: headerStyle),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    l10n.consumedKcalColumn,
                    style: headerStyle,
                    textAlign: TextAlign.end,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: Text(
                    l10n.burnedKcalColumn,
                    style: headerStyle,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
        ),
        for (final day in week.days)
          _DayRow(
            day: day,
            today: week.today,
            scale: scale,
            onTap: () => onDayTap(day.date),
          ),
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.today,
    required this.scale,
    required this.onTap,
  });

  final DayEnergy day;
  final DateTime today;
  final double scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final format = ActivityFormat.of(context);
    final future = day.date.isAfter(today);
    final isToday = day.date == today;
    final label = '${format.weekday(day.date)} ${day.date.day}';
    final style = theme.textTheme.bodyMedium;

    if (future) {
      return Semantics(
        label: '${format.longDate(day.date)}: ${l10n.futureDay}',
        child: ExcludeSemantics(
          child: Opacity(
            opacity: 0.38,
            child: Padding(
              key: Key('week_day_${day.date.weekday}'),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: <Widget>[Expanded(child: Text(label, style: style))],
              ),
            ),
          ),
        ),
      );
    }

    final consumed =
        day.hasMeals ? format.whole(day.consumedKcal) : ActivityFormat.missing;
    final String burned;
    if (day.activeBurnedKcal != null) {
      burned = format.whole(day.activeBurnedKcal!);
    } else if (day.totalBurnedKcal != null) {
      burned = l10n.totalOnly(format.whole(day.totalBurnedKcal!));
    } else {
      burned = ActivityFormat.missing;
    }
    String spoken(String value) {
      return value == ActivityFormat.missing ? l10n.noData : value;
    }

    return Semantics(
      button: true,
      label: l10n.dayRowSemantics(
        format.longDate(day.date),
        spoken(consumed),
        spoken(burned),
      ),
      child: ExcludeSemantics(
        child: InkWell(
          key: Key('week_day_${day.date.weekday}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: Text(
                        label,
                        style: style?.copyWith(
                          fontWeight: isToday ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Text(
                        consumed,
                        style: style,
                        textAlign: TextAlign.end,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: Text(
                        burned,
                        style: style,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
                if (day.hasMeals && scale > 0) ...<Widget>[
                  const SizedBox(height: 4),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FractionallySizedBox(
                      widthFactor: (day.consumedKcal / scale).clamp(0.02, 1.0),
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
