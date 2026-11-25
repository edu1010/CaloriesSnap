import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/utils/responsive_utils.dart';
import '../../models/calorie_goals.dart';
import '../../models/daily_activity.dart';
import '../../models/energy_summary.dart';
import '../../services/activity/activity_store.dart';
import '../../services/activity/activity_sync_coordinator.dart';
import '../../services/activity/activity_sync_source.dart';
import '../../services/activity/energy_dashboard_service.dart';
import 'csv_import_card.dart';
import 'goals_card.dart';
import 'manual_activity_dialog.dart';
import 'sync_card.dart';
import 'today_panel.dart';
import 'week_panel.dart';

/// Goals, today's energy and the Monday–Sunday week. The "today" panel always
/// shows the current day; week navigation only changes the week panel.
class ActivityDashboardScreen extends StatefulWidget {
  const ActivityDashboardScreen({
    super.key,
    required this.dashboardService,
    required this.syncCoordinator,
    this.pickCsvFile,
  });

  final EnergyDashboardService dashboardService;
  final ActivitySyncCoordinator syncCoordinator;

  /// Replaces the system file picker, for tests.
  final CsvFilePicker? pickCsvFile;

  @override
  State<ActivityDashboardScreen> createState() =>
      _ActivityDashboardScreenState();
}

class _ActivityDashboardScreenState extends State<ActivityDashboardScreen> {
  EnergyDashboardData? _today;
  EnergyDashboardData? _week;
  Object? _error;
  bool _loading = true;
  int _loadToken = 0;

  /// A day of the week being shown; null for the current week.
  DateTime? _weekAnchor;

  ActivitySyncAvailability? _availability;
  bool _availabilityCheckFailed = false;
  ActivitySyncState? _syncState;
  ActivitySyncOutcome? _lastOutcome;
  bool _syncing = false;

  ActivityStore get _store => widget.dashboardService.store;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSyncInfo();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final today = await widget.dashboardService.load();
      final anchor = _weekAnchor;
      final week =
          anchor == null
              ? today
              : await widget.dashboardService.load(day: anchor);
      if (!mounted || token != _loadToken) {
        return;
      }
      setState(() {
        _today = today;
        _week = week;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || token != _loadToken) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadSyncInfo() async {
    try {
      final availability = await widget.syncCoordinator.checkAvailability();
      final state = await widget.syncCoordinator.lastState();
      if (!mounted) {
        return;
      }
      setState(() {
        _availability = availability;
        _availabilityCheckFailed = false;
        _syncState = state;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _availabilityCheckFailed = true;
      });
    }
  }

  Future<void> _refresh() async {
    await Future.wait(<Future<void>>[_load(), _loadSyncInfo()]);
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _shiftWeek(int weeks) {
    final today = _today;
    final week = _week;
    if (today == null || week == null) {
      return;
    }
    final shown = week.week.weekStart;
    final current = today.week.weekStart;
    final target = DateTime(shown.year, shown.month, shown.day + 7 * weeks);
    if (target.isAfter(current)) {
      return;
    }
    _weekAnchor = target == current ? null : target;
    _load();
  }

  Future<void> _editGoals() async {
    final current = _today?.goals ?? CalorieGoals.empty;
    final goals = await showDialog<CalorieGoals>(
      context: context,
      builder: (_) => GoalEditorDialog(goals: current),
    );
    if (goals == null || !mounted) {
      return;
    }
    try {
      await _store.saveGoals(goals);
    } catch (error) {
      if (mounted) {
        _showSnack(context.l10n.failedToSave(error));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    _showSnack(context.l10n.goalsSaved);
    await _load();
  }

  Future<void> _editManual(DateTime day) async {
    final List<DailyActivity> records;
    try {
      records = await _store.recordsForDay(day);
    } catch (error) {
      if (mounted) {
        _showSnack(context.l10n.failedToLoadDashboard(error));
      }
      return;
    }
    if (!mounted) {
      return;
    }

    DailyActivity? manual;
    DailyActivity? imported;
    for (final record in records) {
      if (record.source == ActivitySource.manual) {
        manual = record;
      } else if (imported == null ||
          record.source.index < imported.source.index) {
        imported = record;
      }
    }

    final result = await showDialog<ManualActivityResult>(
      context: context,
      builder:
          (_) => ManualActivityDialog(
            date: day,
            existing: manual,
            imported: imported,
          ),
    );
    if (result == null || !mounted) {
      return;
    }

    try {
      if (result.delete) {
        await _store.delete(day, ActivitySource.manual);
      } else {
        await _store.upsert(result.activity!);
      }
    } catch (error) {
      if (mounted) {
        _showSnack(context.l10n.failedToSave(error));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    _showSnack(
      result.delete
          ? context.l10n.manualEntryDeleted
          : context.l10n.manualEntrySaved,
    );
    await _load();
  }

  Future<void> _sync() async {
    if (_syncing) {
      return;
    }
    setState(() {
      _syncing = true;
    });
    ActivitySyncOutcome outcome;
    ActivitySyncState? state;
    try {
      outcome = await widget.syncCoordinator.sync();
      state = await widget.syncCoordinator.lastState();
    } catch (error) {
      outcome = ActivitySyncOutcome(
        status: ActivitySyncStatus.failed,
        message: error.toString(),
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _syncing = false;
      _lastOutcome = outcome;
      _syncState = state ?? _syncState;
    });
    _showSnack(
      syncStatusText(
        context.l10n,
        outcome.status,
        importedDays: outcome.importedDays,
        message: outcome.message,
      ),
    );
    if (outcome.isSuccess) {
      await _load();
    } else if (outcome.status != ActivitySyncStatus.permissionDenied &&
        outcome.status != ActivitySyncStatus.failed) {
      await _loadSyncInfo();
    }
  }

  Future<void> _openProviderSetup() async {
    var opened = false;
    try {
      opened = await widget.syncCoordinator.source.openProviderSetup();
    } catch (_) {
      opened = false;
    }
    if (!mounted) {
      return;
    }
    if (!opened) {
      _showSnack(context.l10n.couldNotOpenHealthConnect);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.goalsAndActivity),
        actions: <Widget>[
          IconButton(
            key: const Key('refresh_button'),
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refresh,
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final today = _today;
    final week = _week;
    final error = _error;

    if (error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.error_outline,
                size: 40,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.failedToLoadDashboard(error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retry),
              ),
            ],
          ),
        ),
      );
    }
    if (today == null || week == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final wide = ResponsiveUtils.isWideLayout(context);
    const gap = SizedBox(height: 12);

    final goalsCard = GoalsCard(goals: today.goals, onEdit: _editGoals);
    final todayPanel = TodayPanel(
      day: today.day,
      canSync: _availability == ActivitySyncAvailability.available,
      syncing: _syncing,
      onEditManual: () => _editManual(today.day.date),
      onSync: _sync,
    );
    final weekPanel = WeekPanel(
      week: week.week,
      canGoNext: week.week.weekStart.isBefore(today.week.weekStart),
      onPrevious: () => _shiftWeek(-1),
      onNext: () => _shiftWeek(1),
      onDayTap: _editManual,
    );
    final syncCard = SyncCard(
      availability: _availability,
      checkFailed: _availabilityCheckFailed,
      syncState: _syncState,
      lastOutcome: _lastOutcome,
      syncing: _syncing,
      onSync: _sync,
      onOpenSetup: _openProviderSetup,
      onRecheck: _loadSyncInfo,
    );
    final csvCard = CsvImportCard(
      store: _store,
      onImported: _load,
      pickFile: widget.pickCsvFile,
    );

    final Widget content;
    if (wide) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[goalsCard, gap, todayPanel, gap, syncCard],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[weekPanel, gap, csvCard],
            ),
          ),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          goalsCard,
          gap,
          todayPanel,
          gap,
          weekPanel,
          gap,
          syncCard,
          gap,
          csvCard,
        ],
      );
    }

    return Column(
      children: <Widget>[
        SizedBox(
          height: 4,
          child: _loading ? const LinearProgressIndicator() : null,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: content,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
