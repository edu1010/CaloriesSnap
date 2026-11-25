import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../models/daily_activity.dart';
import '../../services/activity/activity_sync_coordinator.dart';
import '../../services/activity/activity_sync_source.dart';
import 'activity_format.dart';
import 'activity_widgets.dart';

String syncStatusText(
  AppLocalizations l10n,
  ActivitySyncStatus status, {
  int importedDays = 0,
  String? message,
}) {
  switch (status) {
    case ActivitySyncStatus.success:
      return l10n.syncSuccess(importedDays);
    case ActivitySyncStatus.unsupportedPlatform:
      return l10n.syncUnsupportedPlatform;
    case ActivitySyncStatus.providerNotInstalled:
      return l10n.syncProviderNotInstalled;
    case ActivitySyncStatus.providerUpdateRequired:
      return l10n.syncProviderUpdateRequired;
    case ActivitySyncStatus.permissionDenied:
      return l10n.syncPermissionDenied;
    case ActivitySyncStatus.failed:
      return l10n.syncFailed(message);
  }
}

/// Maps a persisted [ActivitySyncState.lastError] back to wording.
String syncErrorText(AppLocalizations l10n, String errorName) {
  for (final status in ActivitySyncStatus.values) {
    if (status.name == errorName && status != ActivitySyncStatus.success) {
      return syncStatusText(l10n, status);
    }
  }
  return l10n.syncFailed(null);
}

/// Health Connect status and the explicit "synchronise" action. Purely a
/// view: the screen owns the state so other panels can trigger a sync too.
class SyncCard extends StatelessWidget {
  const SyncCard({
    super.key,
    required this.availability,
    required this.checkFailed,
    required this.syncState,
    required this.lastOutcome,
    required this.syncing,
    required this.onSync,
    required this.onOpenSetup,
    required this.onRecheck,
  });

  /// Null while availability is still being checked.
  final ActivitySyncAvailability? availability;
  final bool checkFailed;
  final ActivitySyncState? syncState;

  /// Result of the sync run from this screen, if any.
  final ActivitySyncOutcome? lastOutcome;
  final bool syncing;
  final VoidCallback onSync;
  final VoidCallback onOpenSetup;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final format = ActivityFormat.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final state = syncState;
    final outcome = lastOutcome;
    final lastSuccess = state?.lastSuccessAt;
    final lastError = state?.lastError;
    final available = availability == ActivitySyncAvailability.available;
    final permissionDenied =
        outcome == null
            ? lastError == ActivitySyncStatus.permissionDenied.name
            : outcome.status == ActivitySyncStatus.permissionDenied;

    return SectionCard(
      key: const Key('sync_card'),
      title: l10n.healthConnect,
      icon: Icons.sync_outlined,
      children: <Widget>[
        ..._availabilityWidgets(context),
        if (outcome != null)
          InfoLine(
            key: const Key('sync_outcome'),
            text: syncStatusText(
              l10n,
              outcome.status,
              importedDays: outcome.importedDays,
              message: outcome.message,
            ),
            icon:
                outcome.isSuccess
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
            color:
                outcome.isSuccess
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
          ),
        if (available && permissionDenied && !syncing)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              key: const Key('sync_open_settings_button'),
              onPressed: onOpenSetup,
              icon: const Icon(Icons.open_in_new),
              label: Text(l10n.openHealthConnect),
            ),
          ),
        Text(
          lastSuccess == null
              ? l10n.neverSynchronised
              : l10n.lastSynchronised(format.dateTime(lastSuccess)),
          key: const Key('sync_last'),
          style: theme.textTheme.bodyMedium,
        ),
        if (lastError != null && outcome == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.lastAttemptFailed(syncErrorText(l10n, lastError)),
              key: const Key('sync_last_error'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        const SizedBox(height: 4),
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const Key('sync_which_apps'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            expandedAlignment: Alignment.centerLeft,
            leading: const Icon(Icons.help_outline),
            title: Text(l10n.whichApps),
            children: <Widget>[
              Text(
                l10n.whichAppsBody,
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _availabilityWidgets(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    if (checkFailed) {
      return <Widget>[
        InfoLine(
          text: l10n.syncCheckFailed,
          icon: Icons.error_outline,
          color: theme.colorScheme.error,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton.icon(
            onPressed: onRecheck,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.retry),
          ),
        ),
      ];
    }

    switch (availability) {
      case null:
        return <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: <Widget>[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(l10n.checkingAvailability)),
              ],
            ),
          ),
        ];
      case ActivitySyncAvailability.unsupportedPlatform:
        return <Widget>[
          InfoLine(
            key: const Key('sync_unsupported'),
            text: l10n.syncUnsupportedPlatform,
            icon: Icons.phonelink_off_outlined,
          ),
        ];
      case ActivitySyncAvailability.providerNotInstalled:
      case ActivitySyncAvailability.providerUpdateRequired:
        final missing =
            availability == ActivitySyncAvailability.providerNotInstalled;
        return <Widget>[
          InfoLine(
            text:
                missing
                    ? l10n.syncProviderNotInstalled
                    : l10n.syncProviderUpdateRequired,
            icon: Icons.warning_amber_outlined,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.tonalIcon(
              key: const Key('sync_setup_button'),
              onPressed: onOpenSetup,
              icon: const Icon(Icons.open_in_new),
              label: Text(
                missing ? l10n.installHealthConnect : l10n.updateHealthConnect,
              ),
            ),
          ),
        ];
      case ActivitySyncAvailability.available:
        return <Widget>[
          Text(
            l10n.syncDescription(ActivitySyncCoordinator.defaultDays),
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('sync_button'),
            onPressed: syncing ? null : onSync,
            icon:
                syncing
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.sync),
            label: Text(syncing ? l10n.synchronising : l10n.synchroniseNow),
          ),
          const SizedBox(height: 12),
        ];
    }
  }
}
