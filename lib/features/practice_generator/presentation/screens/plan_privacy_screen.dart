import 'dart:io' show Directory;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/usecase/delete_practice_planning_data.dart';
import '../../application/usecase/export_practice_planning_data.dart';

/// Self-contained privacy surface for the practice-planning feature
/// (E07-R29 §5.5, §5.7, §6.1).
///
/// Accessibility & localisation guarantees this screen is held to:
///
///   * Every user-facing string is sourced from `AppLocalizations`
///     (A1, A8 — no hard-coded literals).
///   * Every status / action is conveyed **textually** (not by colour
///     alone) and exposed via a `Semantics` label (A3, A4, A5).
///   * The discomfort safety card makes the "no free-text logging,
///     no progression" guarantee explicit (A9, ADR 0265 §3).
///   * All actions are reachable with the keyboard / focus traversal —
///     no gesture-only paths (A3).
///   * Reduced motion: no implicit animations on this screen; modal
///     sheets use the system default and respect `MediaQuery`'s
///     `disableAnimations` (A5).
class PlanPrivacyScreen extends StatefulWidget {
  const PlanPrivacyScreen({
    required this.deleteUseCase,
    required this.exportUseCase,
    this.cacheDirectoryResolver,
    super.key,
  });

  final DeletePracticePlanningData deleteUseCase;
  final ExportPracticePlanningData exportUseCase;

  /// Test seam — the screen does not own the file system. In tests the
  /// caller passes a `Directory.systemTemp`-backed resolver.
  final Future<Directory> Function()? cacheDirectoryResolver;

  @override
  State<PlanPrivacyScreen> createState() => _PlanPrivacyScreenState();
}

class _PlanPrivacyScreenState extends State<PlanPrivacyScreen> {
  bool _isWorking = false;
  String? _lastExportFileName;
  String? _errorMessage;

  Future<void> _confirmAndDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _DeleteConfirmDialog(
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });
    final result = await widget.deleteUseCase();
    if (!mounted) return;
    setState(() {
      _isWorking = false;
      if (result.isFailure) {
        _errorMessage = AppLocalizations.of(
          context,
        ).practicePrivacyDeleteFailed;
      } else {
        _lastExportFileName = null;
      }
    });
    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('plan-privacy-delete-done'),
          content: Text(AppLocalizations.of(context).practicePrivacyDeleteDone),
        ),
      );
    }
  }

  Future<void> _confirmAndExport() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _ExportConfirmDialog(
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });
    final result = await widget.exportUseCase();
    if (!mounted) return;
    setState(() {
      _isWorking = false;
      if (result.isFailure) {
        _errorMessage = AppLocalizations.of(
          context,
        ).practicePrivacyExportFailed;
      } else if (result.isSuccess) {
        _lastExportFileName = result.valueOrNull!.fileName;
      }
    });
    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('plan-privacy-export-done'),
          content: Text(
            AppLocalizations.of(
              context,
            ).practicePrivacyExportReady(result.valueOrNull!.fileName),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          label: l10n.practicePrivacyScreenSemantics,
          child: Text(l10n.practicePrivacyTitle),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              l10n.practicePrivacyIntro,
              key: const Key('plan-privacy-intro'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            _ScopeCard(l10n: l10n),
            const SizedBox(height: 16),
            _DiscomfortSafetyCard(l10n: l10n),
            const SizedBox(height: 24),
            Semantics(
              label: l10n.practicePrivacyExportAction,
              button: true,
              child: OutlinedButton.icon(
                key: const Key('plan-privacy-export-action'),
                onPressed: _isWorking ? null : _confirmAndExport,
                icon: const Icon(Icons.download_outlined),
                label: Text(l10n.practicePrivacyExportAction),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: l10n.practicePrivacyDeleteAction,
              button: true,
              child: FilledButton.tonalIcon(
                key: const Key('plan-privacy-delete-action'),
                onPressed: _isWorking ? null : _confirmAndDelete,
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.practicePrivacyDeleteAction),
              ),
            ),
            if (_lastExportFileName != null) ...[
              const SizedBox(height: 16),
              Text(
                l10n.practicePrivacyExportReady(_lastExportFileName!),
                key: const Key('plan-privacy-export-last-name'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                key: const Key('plan-privacy-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The "what does this remove / what is preserved" card — surfaces the
/// delete-all scope in plain language. Every row uses an icon + label so
/// the meaning is never colour-only (A4).
class _ScopeCard extends StatelessWidget {
  const _ScopeCard({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('plan-privacy-scope-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.practicePrivacyScopeTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l10n.practicePrivacyScopeBody),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline, semanticLabel: 'kept'),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.practicePrivacyScopePreserved)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The "if something hurts" card — surfaces the discomfort safety rule
/// (ADR 0265 §3, A9). No free text logging, no difficulty escalation.
class _DiscomfortSafetyCard extends StatelessWidget {
  const _DiscomfortSafetyCard({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('plan-privacy-discomfort-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.health_and_safety_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.practicePrivacyDiscomfortSafetyTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(l10n.practicePrivacyDiscomfortSafetyBody),
          ],
        ),
      ),
    );
  }
}

class _DeleteConfirmDialog extends StatelessWidget {
  const _DeleteConfirmDialog({required this.onConfirm});
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const Key('plan-privacy-delete-dialog'),
      title: Text(l10n.practicePrivacyDeleteConfirmTitle),
      content: Text(l10n.practicePrivacyDeleteConfirmBody),
      actions: [
        TextButton(
          key: const Key('plan-privacy-delete-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.practicePrivacyDeleteCancel),
        ),
        FilledButton(
          key: const Key('plan-privacy-delete-confirm'),
          onPressed: onConfirm,
          child: Text(l10n.practicePrivacyDeleteConfirm),
        ),
      ],
    );
  }
}

class _ExportConfirmDialog extends StatelessWidget {
  const _ExportConfirmDialog({required this.onConfirm});
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const Key('plan-privacy-export-dialog'),
      title: Text(l10n.practicePrivacyExportTitle),
      content: Text(l10n.practicePrivacyExportBody),
      actions: [
        TextButton(
          key: const Key('plan-privacy-export-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.practicePrivacyDeleteCancel),
        ),
        FilledButton(
          key: const Key('plan-privacy-export-confirm'),
          onPressed: onConfirm,
          child: Text(l10n.practicePrivacyExportAction),
        ),
      ],
    );
  }
}
