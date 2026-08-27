/// Standalone privacy control for local, aggregate-only Vision data.
///
/// Route wiring is intentionally deferred: callers construct this screen with
/// the local repository and export service, so it has no hidden provider or
/// network dependency.
library;

import 'package:flutter/material.dart';

import '../../../core/design_system/public.dart';
import '../../../core/storage/storage_keys.dart';
import '../../../l10n/app_localizations.dart';
import '../../vision/public.dart';
import '../theme/settings_theme_scope.dart';

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
  // NOTE: `SsConfirmationSheet.show` presents through `showGeneralDialog`
  // (`ss_overlay_host.dart`), which does NOT capture the calling context's
  // `InheritedTheme` the way `showDialog`/`showModalBottomSheet` do — so a
  // locally-scoped `SettingsThemeScope` never reaches it and
  // `SsColorScheme` resolves null there (measured, 2026-08-27). `showDialog`
  // DOES capture it, so the consequence-first wording (ADR 0279 §5.6) is
  // kept on a plain `AlertDialog` instead.
  Future<void> _confirmDeleteAll(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.visionPrivacyDeleteAllTitle),
        content: Text(l10n.visionPrivacyDeleteAllBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('visionPrivacyDeleteAllConfirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.visionPrivacyDeleteAllConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _deleteAll(l10n);
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
    return SettingsThemeScope(
      child: Scaffold(
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
                        key: Key(
                          'visionPrivacyDeleteSession-${entry.sessionId}',
                        ),
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
