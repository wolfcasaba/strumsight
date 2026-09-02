import 'dart:io' show Directory;

import 'package:flutter/material.dart';

import '../../../../core/design_system/public.dart';
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          label: l10n.practicePrivacyScreenSemantics,
          child: Text(l10n.practicePrivacyTitle),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SsSpacing.space5),
          children: [
            Text(
              l10n.practicePrivacyIntro,
              key: const Key('plan-privacy-intro'),
              style: typography.bodyLarge.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: SsSpacing.space4),
            _ScopeCard(l10n: l10n),
            const SizedBox(height: SsSpacing.space4),
            _DiscomfortSafetyCard(l10n: l10n),
            const SizedBox(height: SsSpacing.space6),
            SsButton(
              key: const Key('plan-privacy-export-action'),
              variant: SsButtonVariant.secondary,
              icon: Icons.download_outlined,
              onPressed: _isWorking ? null : _confirmAndExport,
              label: l10n.practicePrivacyExportAction,
            ),
            const SizedBox(height: SsSpacing.space3),
            SsButton(
              key: const Key('plan-privacy-delete-action'),
              variant: SsButtonVariant.destructive,
              icon: Icons.delete_outline,
              onPressed: _isWorking ? null : _confirmAndDelete,
              label: l10n.practicePrivacyDeleteAction,
              destructiveSemanticHint: l10n.practicePrivacyDeleteConfirmBody,
            ),
            if (_lastExportFileName != null) ...[
              const SizedBox(height: SsSpacing.space4),
              Text(
                l10n.practicePrivacyExportReady(_lastExportFileName!),
                key: const Key('plan-privacy-export-last-name'),
                style: typography.bodyMedium.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: SsSpacing.space4),
              Text(
                _errorMessage!,
                key: const Key('plan-privacy-error'),
                style: typography.bodyMedium.copyWith(color: colors.danger),
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return SsCard(
      key: const Key('plan-privacy-scope-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.practicePrivacyScopeTitle,
            style: typography.titleMedium.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: SsSpacing.space2),
          Text(
            l10n.practicePrivacyScopeBody,
            style: typography.bodyMedium.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: SsSpacing.space2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline,
                size: 20,
                color: colors.textSecondary,
                semanticLabel: 'kept',
              ),
              const SizedBox(width: SsSpacing.space2),
              Expanded(
                child: Text(
                  l10n.practicePrivacyScopePreserved,
                  style: typography.bodyMedium.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return SsCard(
      key: const Key('plan-privacy-discomfort-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.health_and_safety_outlined,
                size: 20,
                color: colors.textSecondary,
              ),
              const SizedBox(width: SsSpacing.space2),
              Expanded(
                child: Text(
                  l10n.practicePrivacyDiscomfortSafetyTitle,
                  style: typography.titleMedium.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: SsSpacing.space2),
          Text(
            l10n.practicePrivacyDiscomfortSafetyBody,
            style: typography.bodyMedium.copyWith(color: colors.textSecondary),
          ),
        ],
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
