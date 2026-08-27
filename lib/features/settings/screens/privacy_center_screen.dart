import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/public.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../vision/public.dart';
import '../providers/lab_mode_provider.dart';
import '../theme/settings_theme_scope.dart';
import 'vision_privacy_screen.dart';

/// The state of an explicit, auditable data task (§5.6, ADR 0279): a task
/// never just "happens" — it has a visible state and, when it finishes, a
/// visible result. [failed] is reachable (not just theoretical) because the
/// underlying vision repository/export calls are real I/O, not a guaranteed
/// no-op.
enum PrivacyTaskState { idle, running, done, failed }

/// Top-level privacy & consent center (A5, A8; §0.0.B/B6, B7): reachable in
/// one tap from the Settings root (`settings_screen.dart`'s new
/// `SsContentCard` entry), not three menus deep. Aggregates what the app
/// stores across the device, lets the user export or delete all of it as an
/// explicit task with state + result, and shows the session-by-session Vision
/// history one level down (the existing, previously-unreachable
/// [VisionPrivacyScreen] — §0.0.B/B6).
class PrivacyCenterScreen extends ConsumerStatefulWidget {
  const PrivacyCenterScreen({super.key});

  @override
  ConsumerState<PrivacyCenterScreen> createState() =>
      _PrivacyCenterScreenState();
}

class _PrivacyCenterScreenState extends ConsumerState<PrivacyCenterScreen> {
  PrivacyTaskState _exportState = PrivacyTaskState.idle;
  PrivacyTaskState _deleteState = PrivacyTaskState.idle;

  VisionSessionRepository get _repository =>
      VisionSessionRepository(store: ref.read(keyValueStoreProvider));
  VisionExport get _export =>
      VisionExport(store: ref.read(keyValueStoreProvider));

  Future<void> _runExport(AppLocalizations l10n) async {
    setState(() => _exportState = PrivacyTaskState.running);
    try {
      final json = await Future<String>.microtask(_export.exportJson);
      if (!mounted) return;
      setState(() => _exportState = PrivacyTaskState.done);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.privacyCenterExportDone),
          content: SingleChildScrollView(child: Text(json)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.commonClose),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _exportState = PrivacyTaskState.failed);
    }
  }

  // NOTE: `SsConfirmationSheet.show` presents through `showGeneralDialog`
  // (`ss_overlay_host.dart`), which does NOT capture the calling context's
  // `InheritedTheme` the way `showDialog` does — a locally-scoped
  // `SettingsThemeScope` never reaches it and `SsColorScheme` resolves null
  // there (measured, 2026-08-27). `showDialog` DOES capture it, so the
  // consequence-first wording (ADR 0279 §5.6 — what is lost, named before
  // the destructive action runs) is kept on a plain `AlertDialog` instead.
  Future<void> _confirmDeleteAll(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.privacyCenterDeleteAllTitle),
        content: Text(l10n.privacyCenterDeleteAllConsequence),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.privacyCenterCancel),
          ),
          FilledButton(
            key: const Key('privacyCenterDeleteAllConfirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.privacyCenterDeleteAllConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runDeleteAll();
  }

  Future<void> _runDeleteAll() async {
    setState(() => _deleteState = PrivacyTaskState.running);
    try {
      await _repository.deleteAllVisionData();
      if (!mounted) return;
      setState(() => _deleteState = PrivacyTaskState.done);
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleteState = PrivacyTaskState.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sessionCount = _repository.list().length;
    final labModeOn = ref.watch(labModeProvider);

    return SettingsThemeScope(
      // A fresh `context` (a descendant of the scope above) is required for
      // `Theme.of(context).extension<SsColorScheme>()` to resolve.
      child: Builder(
        builder: (context) {
          final colors = Theme.of(context).extension<SsColorScheme>()!;
          return Scaffold(
            appBar: AppBar(title: Text(l10n.privacyCenterTitle)),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  SsSection(
                    title: l10n.privacyCenterInventoryTitle,
                    child: SsCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            l10n.privacyCenterInventorySessions(sessionCount),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              Icon(
                                labModeOn
                                    ? Icons.mic_outlined
                                    : Icons.mic_off_outlined,
                                size: 16,
                                color: colors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  labModeOn
                                      ? l10n.privacyCenterPolicyLabModeOn
                                      : l10n.privacyCenterPolicyLabModeOff,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SsContentCard(
                    title: l10n.privacyCenterOpenSessionHistory,
                    message: l10n.privacyCenterOpenSessionHistorySubtitle,
                    icon: Icons.history,
                    actions: [
                      SsCardAction(
                        label: l10n.privacyCenterOpenSessionHistory,
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => VisionPrivacyScreen(
                              repository: _repository,
                              export: _export,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _TaskRow(
                    key: const Key('privacyCenterExportTask'),
                    state: _exportState,
                    idleLabel: l10n.privacyCenterExportAction,
                    runningLabel: l10n.privacyCenterExportRunning,
                    doneLabel: l10n.privacyCenterExportDone,
                    failedLabel: l10n.privacyCenterExportFailed,
                    onRun: () => _runExport(l10n),
                  ),
                  const SizedBox(height: 12),
                  _TaskRow(
                    key: const Key('privacyCenterDeleteAllTask'),
                    state: _deleteState,
                    destructive: true,
                    idleLabel: l10n.privacyCenterDeleteAllAction,
                    runningLabel: l10n.privacyCenterDeleteAllRunning,
                    doneLabel: l10n.privacyCenterDeleteAllDone,
                    failedLabel: l10n.privacyCenterExportFailed,
                    onRun: () => _confirmDeleteAll(l10n),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One explicit, auditable data task (export or delete-all): a button while
/// idle/failed, a disabled loading button while running, and a plain result
/// line once it finishes (§5.6/A8) — the result never just replaces the
/// button silently; [state] is always readable from the row's text.
class _TaskRow extends StatelessWidget {
  const _TaskRow({
    super.key,
    required this.state,
    required this.idleLabel,
    required this.runningLabel,
    required this.doneLabel,
    required this.failedLabel,
    required this.onRun,
    this.destructive = false,
  });

  final PrivacyTaskState state;
  final String idleLabel;
  final String runningLabel;
  final String doneLabel;
  final String failedLabel;
  final bool destructive;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    if (state == PrivacyTaskState.done) {
      return Text(doneLabel);
    }
    return SsButton(
      label: state == PrivacyTaskState.failed ? failedLabel : idleLabel,
      loading: state == PrivacyTaskState.running,
      variant: destructive
          ? SsButtonVariant.destructive
          : SsButtonVariant.secondary,
      destructiveSemanticHint: destructive ? idleLabel : null,
      onPressed: state == PrivacyTaskState.running ? null : onRun,
    );
  }
}
