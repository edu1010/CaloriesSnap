import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../services/food_detection/vlm/vlm_model_catalog.dart';
import '../../services/food_detection/vlm/vlm_model_store.dart';

/// Lets the user download, select and remove the on-device vision model.
class LocalAiSettingsScreen extends StatefulWidget {
  const LocalAiSettingsScreen({super.key, required this.store});

  final VlmModelStore store;

  @override
  State<LocalAiSettingsScreen> createState() => _LocalAiSettingsScreenState();
}

class _LocalAiSettingsScreenState extends State<LocalAiSettingsScreen> {
  int? _deviceRamGb;

  @override
  void initState() {
    super.initState();
    widget.store.deviceRamGb().then((value) {
      if (mounted) setState(() => _deviceRamGb = value);
    });
  }

  Future<void> _download(VlmModelSpec spec) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await widget.store.download(spec);
    } on VlmDownloadCancelled {
      // The user asked for it.
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.downloadFailed(error))),
      );
    }
  }

  static String _size(int bytes) =>
      '${(bytes / 1e9).toStringAsFixed(1)} GB';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final store = widget.store;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.localAi)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final progress = store.progress;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text(l10n.localAiIntro),
                const SizedBox(height: 8),
                Text(
                  l10n.localAiSpeedNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.bolt_outlined),
                    title: Text(l10n.classifierOnly),
                    subtitle: Text(l10n.classifierOnlyDescription),
                    trailing:
                        store.activeModel == null
                            ? Chip(label: Text(l10n.inUse))
                            : TextButton(
                              onPressed: () => store.select(null),
                              child: Text(l10n.use),
                            ),
                  ),
                ),
                for (final spec in store.catalog)
                  _ModelCard(
                    spec: spec,
                    description:
                        spec.id == VlmModelCatalog.light.id
                            ? l10n.lightModelDescription
                            : l10n.preciseModelDescription,
                    size: _size(spec.totalBytes),
                    installed: store.isInstalled(spec),
                    active: store.activeModel?.id == spec.id,
                    progress: progress?.spec.id == spec.id ? progress : null,
                    busy: progress != null,
                    deviceRamGb: _deviceRamGb,
                    onDownload: () => _download(spec),
                    onCancel: store.cancelDownload,
                    onUse: () => store.select(spec),
                    onDelete: () => store.delete(spec),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.spec,
    required this.description,
    required this.size,
    required this.installed,
    required this.active,
    required this.progress,
    required this.busy,
    required this.deviceRamGb,
    required this.onDownload,
    required this.onCancel,
    required this.onUse,
    required this.onDelete,
  });

  final VlmModelSpec spec;
  final String description;
  final String size;
  final bool installed;
  final bool active;
  final VlmDownloadProgress? progress;

  /// Another download is running; only one is allowed at a time.
  final bool busy;
  final int? deviceRamGb;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onUse;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final ram = deviceRamGb;
    final progress = this.progress;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.auto_awesome_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${spec.name} · $size',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (active) Chip(label: Text(l10n.inUse)),
              ],
            ),
            const SizedBox(height: 8),
            Text(description),
            if (ram != null && ram < spec.minDeviceRamGb) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                l10n.lowMemoryWarning(spec.minDeviceRamGb, ram),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            if (progress != null) ...<Widget>[
              LinearProgressIndicator(
                value:
                    progress.phase == VlmDownloadPhase.verifying
                        ? null
                        : progress.fraction,
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      progress.phase == VlmDownloadPhase.verifying
                          ? l10n.verifyingDownload
                          : l10n.downloadingModel(
                            (progress.fraction * 100).floor(),
                          ),
                    ),
                  ),
                  TextButton(
                    onPressed: onCancel,
                    child: Text(l10n.cancelDownload),
                  ),
                ],
              ),
            ] else if (installed)
              Wrap(
                spacing: 8,
                children: <Widget>[
                  if (!active)
                    FilledButton(onPressed: onUse, child: Text(l10n.use)),
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.delete),
                  ),
                ],
              )
            else ...<Widget>[
              FilledButton.icon(
                onPressed: busy ? null : onDownload,
                icon: const Icon(Icons.download_outlined),
                label: Text(l10n.downloadModel(size)),
              ),
              const SizedBox(height: 4),
              Text(l10n.downloadOverWifi, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
