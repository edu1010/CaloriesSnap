import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../services/activity/activity_csv_importer.dart';
import '../../services/activity/activity_store.dart';
import 'activity_format.dart';
import 'activity_widgets.dart';

/// A file chosen for import; the content is only read once the size is known
/// to be acceptable.
class PickedCsvFile {
  const PickedCsvFile({
    required this.name,
    required this.size,
    required this.readBytes,
  });

  final String name;
  final int size;
  final Future<List<int>> Function() readBytes;
}

typedef CsvFilePicker = Future<PickedCsvFile?> Function();

Future<PickedCsvFile?> pickCsvFileFromDisk() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: <String>['csv'],
  );
  if (result == null || result.files.isEmpty) {
    return null;
  }
  final file = result.files.single;
  final path = file.path;
  final bytes = file.bytes;
  return PickedCsvFile(
    name: file.name,
    size: file.size,
    readBytes: () async {
      if (path != null) {
        return File(path).readAsBytes();
      }
      if (bytes != null) {
        return bytes;
      }
      throw const FileSystemException('No readable content');
    },
  );
}

class CsvImportCard extends StatefulWidget {
  const CsvImportCard({
    super.key,
    required this.store,
    required this.onImported,
    this.pickFile,
  });

  static const maxBytes = 2 * 1024 * 1024;

  final ActivityStore store;
  final VoidCallback onImported;
  final CsvFilePicker? pickFile;

  @override
  State<CsvImportCard> createState() => _CsvImportCardState();
}

class _CsvImportCardState extends State<CsvImportCard> {
  bool _busy = false;

  Future<void> _import() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      await _run();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _run() async {
    final PickedCsvFile? file;
    try {
      file = await (widget.pickFile ?? pickCsvFileFromDisk)();
    } catch (error) {
      if (mounted) {
        await _showMessage(context.l10n.csvUnreadable(error));
      }
      return;
    }
    if (file == null || !mounted) {
      return;
    }
    final fileName = file.name;
    if (file.size > CsvImportCard.maxBytes) {
      await _showMessage(context.l10n.csvTooLarge);
      return;
    }

    final String content;
    try {
      final bytes = await file.readBytes();
      if (!mounted) {
        return;
      }
      if (bytes.length > CsvImportCard.maxBytes) {
        await _showMessage(context.l10n.csvTooLarge);
        return;
      }
      content = utf8.decode(bytes);
    } on FormatException {
      if (mounted) {
        await _showMessage(context.l10n.csvNotUtf8);
      }
      return;
    } catch (error) {
      if (mounted) {
        await _showMessage(context.l10n.csvUnreadable(error));
      }
      return;
    }

    final parsed = ActivityCsvImporter.parse(content, origin: fileName);
    if (!mounted) {
      return;
    }
    if (!parsed.headerValid) {
      await showDialog<void>(
        context: context,
        builder: (_) => _InvalidHeaderDialog(fileName: fileName),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _CsvSummaryDialog(fileName: fileName, parsed: parsed),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    var stored = 0;
    try {
      for (final day in parsed.days) {
        await widget.store.upsert(day);
        stored++;
      }
    } catch (error) {
      if (mounted) {
        _showSnack(context.l10n.failedToSave(error));
      }
      if (stored > 0) {
        widget.onImported();
      }
      return;
    }
    if (!mounted) {
      return;
    }
    _showSnack(context.l10n.csvImported(stored));
    widget.onImported();
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _showMessage(String text) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final l10n = dialogContext.l10n;
        return AlertDialog(
          scrollable: true,
          title: Text(l10n.importCsv),
          content: Text(text),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.close),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return SectionCard(
      key: const Key('csv_card'),
      title: l10n.importCsv,
      icon: Icons.upload_file_outlined,
      children: <Widget>[
        Text(
          l10n.importCsvDescription,
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.csvExpectedColumns(ActivityCsvImporter.columns.join(', ')),
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.csvPrecedenceNote,
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('csv_import_button'),
          onPressed: _busy ? null : _import,
          icon: const Icon(Icons.upload_file_outlined),
          label: Text(l10n.chooseCsvFile),
        ),
      ],
    );
  }
}

class _InvalidHeaderDialog extends StatelessWidget {
  const _InvalidHeaderDialog({required this.fileName});

  final String fileName;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return AlertDialog(
      scrollable: true,
      icon: Icon(Icons.error_outline, color: theme.colorScheme.error),
      title: Text(l10n.csvInvalidHeaderTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.csvFileName(fileName)),
          const SizedBox(height: 8),
          Text(l10n.csvInvalidHeaderBody),
          const SizedBox(height: 8),
          SelectableText(
            ActivityCsvImporter.columns.join(','),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}

class _CsvSummaryDialog extends StatelessWidget {
  const _CsvSummaryDialog({required this.fileName, required this.parsed});

  static const _shownErrors = 5;

  final String fileName;
  final ActivityCsvParseResult parsed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final format = ActivityFormat.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final days = parsed.days;
    final errors = parsed.errors;

    DateTime? first;
    DateTime? last;
    for (final day in days) {
      if (first == null || day.date.isBefore(first)) {
        first = day.date;
      }
      if (last == null || day.date.isAfter(last)) {
        last = day.date;
      }
    }

    return AlertDialog(
      scrollable: true,
      title: Text(l10n.csvSummaryTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.csvFileName(fileName),
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 8),
          if (days.isEmpty)
            Text(l10n.csvNoValidRows)
          else ...<Widget>[
            Text(
              l10n.csvValidDays(days.length),
              style: theme.textTheme.titleMedium,
            ),
            Text(
              l10n.dateRange(format.fullDate(first!), format.fullDate(last!)),
            ),
          ],
          if (errors.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.warning_amber_outlined,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.csvRejectedRows(errors.length),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            for (final error in errors.take(_shownErrors))
              Text(
                l10n.csvRowError(error.line, error.reason),
                style: theme.textTheme.bodySmall,
              ),
            if (errors.length > _shownErrors)
              Text(
                l10n.csvMoreErrors(errors.length - _shownErrors),
                style: theme.textTheme.bodySmall,
              ),
          ],
          const SizedBox(height: 12),
          Text(
            l10n.csvPrecedenceNote,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(days.isEmpty ? l10n.close : l10n.cancel),
        ),
        if (days.isNotEmpty)
          FilledButton(
            key: const Key('csv_confirm_button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.importAction),
          ),
      ],
    );
  }
}
