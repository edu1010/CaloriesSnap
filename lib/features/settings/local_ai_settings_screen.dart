import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../services/food_detection/vlm/vlm_model_catalog.dart';
import '../../services/food_detection/vlm/vlm_model_store.dart';

/// Lets the user download, select and remove the on-device vision model.
class LocalAiSettingsScreen extends StatefulWidget {
  const LocalAiSettingsScreen({
    super.key,
    required this.store,
    this.firstRun = false,
  });

  final VlmModelStore store;
  final bool firstRun;

  @override
  State<LocalAiSettingsScreen> createState() => _LocalAiSettingsScreenState();
}

class _LocalAiSettingsScreenState extends State<LocalAiSettingsScreen> {
  static const double _maxPanelWidth = 680;
  int? _deviceRamGb;
  bool _finishingOnboarding = false;

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
      if (!messenger.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.downloadFailed(error))),
      );
    }
  }

  Future<void> _finishOnboarding() async {
    final l10n = context.l10n;
    setState(() => _finishingOnboarding = true);
    try {
      await widget.store.finishOnboarding();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.aiSetupSaveFailed)));
    } finally {
      if (mounted) setState(() => _finishingOnboarding = false);
    }
  }

  static String _size(int bytes) =>
      bytes < 1000000000
          ? '${(bytes / 1e6).round()} MB'
          : '${(bytes / 1e9).toStringAsFixed(1)} GB';

  String _description(AppLocalizations l10n, VlmModelSpec spec) {
    if (spec.id == VlmModelCatalog.light.id) return l10n.lightModelDescription;
    if (spec.id == VlmModelCatalog.precise.id) {
      return l10n.preciseModelDescription;
    }
    if (spec.id == VlmModelCatalog.lfm3.id) return l10n.lfm3ModelDescription;
    return l10n.aiAlternativeModel(spec.minDeviceRamGb);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final store = widget.store;
    final firstRun = widget.firstRun;

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final progress = store.progress;
        return Scaffold(
          appBar: AppBar(
            title: Text(firstRun ? l10n.aiSetupTitle : l10n.localAi),
          ),
          body: SafeArea(
            bottom: !firstRun,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxPanelWidth),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    Text(firstRun ? l10n.aiSetupIntro : l10n.localAiIntro),
                    const SizedBox(height: 8),
                    if (firstRun)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.auto_awesome_outlined),
                        title: Text(l10n.aiSetupChangeModel),
                      )
                    else
                      Text(
                        l10n.localAiSpeedNote,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (!firstRun)
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
                        description: _description(l10n, spec),
                        size: _size(spec.totalBytes),
                        installed: store.isInstalled(spec),
                        active: store.activeModel?.id == spec.id,
                        progress:
                            progress?.spec.id == spec.id ? progress : null,
                        busy: progress != null,
                        deviceRamGb: _deviceRamGb,
                        onDownload: () => _download(spec),
                        onCancel: store.cancelDownload,
                        onUse: () => store.select(spec),
                        onDelete: () => store.delete(spec),
                      ),
                  ],
                ),
              ),
            ),
          ),
          bottomNavigationBar:
              firstRun
                  ? SafeArea(
                    child: Align(
                      heightFactor: 1,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: _maxPanelWidth,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed:
                                  _finishingOnboarding
                                      ? null
                                      : _finishOnboarding,
                              child: Text(
                                progress != null
                                    ? l10n.aiSetupContinueDownloading
                                    : store.activeModel != null
                                    ? l10n.continueText
                                    : l10n.aiSetupContinueWithClassifier,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  : null,
        );
      },
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
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(
                    progress.phase == VlmDownloadPhase.verifying
                        ? l10n.verifyingDownload
                        : l10n.downloadingModel(
                          (progress.fraction * 100).floor(),
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
                key: ValueKey('download-ai-${spec.id}'),
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

extension _LocalAiCopy on AppLocalizations {
  bool get _spanish => locale.languageCode == 'es';

  String get aiSetupTitle =>
      _spanish ? 'Configura la IA de tus fotos' : 'Set up AI for meal photos';

  String get aiSetupIntro =>
      _spanish
          ? 'Elige un modelo para identificar varios alimentos en una foto y estimar las raciones. Se activa al terminar la descarga y analiza tus fotos sin conexión. También puedes empezar con el clasificador rápido incluido.'
          : 'Choose a model to identify several foods in one photo and estimate portions. It activates when the download finishes and analyses photos offline. You can also start with the built-in fast classifier.';

  String get aiSetupChangeModel =>
      _spanish
          ? 'Para cambiar de modelo, abre IA local con el icono de destellos en la pantalla de inicio.'
          : 'To change models, open On-device AI using the sparkle icon on the home screen.';

  String get aiSetupContinueWithClassifier =>
      _spanish
          ? 'Empezar con el clasificador rápido'
          : 'Start with the fast classifier';

  String get aiSetupContinueDownloading =>
      _spanish
          ? 'Continuar mientras se descarga'
          : 'Continue while downloading';

  String get aiSetupSaveFailed =>
      _spanish
          ? 'No se pudo guardar la configuración. Vuelve a intentarlo.'
          : 'Could not save your setup. Try again.';

  String aiAlternativeModel(int ramGb) =>
      _spanish
          ? 'Modelo de visión alternativo. RAM recomendada de $ramGb GB o más.'
          : 'Alternative vision model. Recommended RAM is $ramGb GB or more.';

  String get lfm3ModelDescription =>
      _spanish
          ? 'Modelo alternativo de Liquid AI. 8 GB de RAM recomendados. Licencia LFM Open 1.0.'
          : 'Alternative model from Liquid AI. 8 GB RAM recommended. LFM Open License 1.0.';
}
