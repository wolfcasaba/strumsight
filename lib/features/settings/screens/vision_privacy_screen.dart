/// Standalone privacy control for local, aggregate-only Vision data.
///
/// Route wiring is intentionally deferred: callers construct this screen with
/// the local repository and export service, so it has no hidden provider or
/// network dependency.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/design_system/public.dart';
import '../../../core/storage/storage_keys.dart';
import '../../../l10n/app_localizations.dart';
import '../../vision/public.dart';

class VisionPrivacyScreen extends StatefulWidget {
  const VisionPrivacyScreen({
    required this.repository,
    required this.export,
    super.key,
  });

  final VisionSessionRepository repository;
  final VisionExport export;

  @override
  State<VisionPrivacyScreen> createState() => _VisionPrivacyScreenState();
}

class _VisionPrivacyScreenState extends State<VisionPrivacyScreen> {
  Future<void> _confirmDeleteAll(AppLocalizations l10n) {
    // Consequence-first confirmation (ADR 0279 §5.6): the sheet names what is
    // lost BEFORE the destructive action runs, not an "Are you sure?" alone.
    return SsConfirmationSheet.show(
      context,
      title: l10n.visionPrivacyDeleteAllTitle,
      consequence: l10n.visionPrivacyDeleteAllBody,
      confirmLabel: l10n.visionPrivacyDeleteAllConfirm,
      cancelLabel: l10n.commonCancel,
      onConfirm: () => unawaited(_deleteAll(l10n)),
    );
  }

  Future<void> _deleteAll(AppLocalizations l10n) async {
    await widget.repository.deleteAllVisionData();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.visionPrivacyDeleteAllDone)));
  }

  Future<void> _deleteSession(
    AppLocalizations l10n,
    VisionSessionHistoryEntry entry,
  ) async {
    await widget.repository.deleteSession(entry.sessionId);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.visionPrivacySessionDeleted)));
  }

  Future<void> _showExport(AppLocalizations l10n) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.visionPrivacyExportTitle),
        content: SingleChildScrollView(child: Text(widget.export.exportJson())),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = widget.repository.list();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.visionPrivacyTitle)),
      body: SafeArea(
        child: Semantics(
          container: true,
          label: l10n.visionPrivacySemantics,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(
                l10n.visionPrivacyIntro,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Text(
                l10n.visionPrivacyScopeTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(l10n.visionPrivacyScopeBody),
              const SizedBox(height: 8),
              for (final key in StorageKeys.visionData)
                _StorageKeyRow(storageKey: key),
              for (final key in StorageKeys.visionData)
                _StorageKeyRow(storageKey: StorageKeys.quarantineOf(key)),
              const SizedBox(height: 8),
              Text(
                l10n.visionPrivacyLabDataBody,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              Text(
                l10n.visionPrivacyHistoryTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l10n.visionPrivacyHistoryEmpty),
                )
              else
                for (final entry in entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.sessionId),
                    subtitle: Text(entry.endedAt.toIso8601String()),
                    trailing: IconButton(
                      key: Key('visionPrivacyDeleteSession-${entry.sessionId}'),
                      tooltip: l10n.visionPrivacyDeleteSession,
                      onPressed: () => _deleteSession(l10n, entry),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              const SizedBox(height: 16),
              SsButton(
                key: const Key('visionPrivacyExport'),
                variant: SsButtonVariant.secondary,
                icon: Icons.download_outlined,
                label: l10n.visionPrivacyExportAction,
                onPressed: () => _showExport(l10n),
              ),
              const SizedBox(height: 8),
              SsButton(
                key: const Key('visionPrivacyDeleteAll'),
                variant: SsButtonVariant.destructive,
                icon: Icons.delete_forever_outlined,
                label: l10n.visionPrivacyDeleteAllAction,
                destructiveSemanticHint: l10n.visionPrivacyDeleteAllBody,
                onPressed: () => _confirmDeleteAll(l10n),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StorageKeyRow extends StatelessWidget {
  const _StorageKeyRow({required this.storageKey});

  final String storageKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('•'),
        const SizedBox(width: 8),
        Expanded(child: Text(storageKey)),
      ],
    ),
  );
}
