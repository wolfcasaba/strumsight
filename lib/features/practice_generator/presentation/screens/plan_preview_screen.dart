import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/id/planner_ids.dart';
import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/plan_enums.dart';
import '../../domain/model/plan_validation_issue.dart';
import '../../domain/service/plan_validator.dart';
import '../controller/plan_preview_controller.dart';
import '../widgets/plan_day_card.dart';
import '../widgets/plan_reason_sheet.dart';

/// Renders a non-integrated preview of an [AdaptivePracticePlan] before
/// activation (SDD Ch8 Kör 21).
///
/// The screen never imports [GenerationOrchestrator] or
/// [PlanGeneratorController] — the plan and its validation context are
/// supplied by the caller, the screen is responsible only for:
///   * rendering days and blocks via [PlanDayCard];
///   * letting the learner tap a block to read the [PlanReasonSheet];
///   * forwarding edits through [PlanPreviewController];
///   * requiring an explicit confirm before activation (A4/A8).
///
/// §5.5: there is no network call in this surface — every text shown comes
/// from the ARB; every block card is local.
class PlanPreviewScreen extends StatefulWidget {
  const PlanPreviewScreen({required this.controller, super.key});

  final PlanPreviewController controller;

  /// Convenience factory used by tests: builds a controller from the given
  /// inputs and wraps it in [PlanPreviewScreen]. Production callers can
  /// still build their own controller (e.g. with a custom validator) and
  /// pass it in directly.
  static Widget withPlan({
    Key? key,
    required AdaptivePracticePlan plan,
    required PlanValidationContext validationContext,
    required PlanPreviewController Function(
      AdaptivePracticePlan,
      PlanValidationContext,
    )
    buildController,
  }) {
    final controller = buildController(plan, validationContext);
    return PlanPreviewScreen(key: key, controller: controller);
  }

  @override
  State<PlanPreviewScreen> createState() => _PlanPreviewScreenState();
}

class _PlanPreviewScreenState extends State<PlanPreviewScreen> {
  bool _warningAcknowledged = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(covariant PlanPreviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onStateChanged);
    widget.controller.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = widget.controller.state;
    return PopScope(
      // §5.1: leaving the screen without confirm must not activate. The
      // canPop=true is the explicit signal that closing never triggers a
      // hidden side-effect.
      canPop: true,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.planPreviewTitle)),
        body: SafeArea(
          child: Column(
            children: [
              if (state.hasBlockingError)
                _FindingsBanner(
                  issues: state.validation.issues
                      .where((issue) => issue.blocksActivation)
                      .toList(growable: false),
                  isError: true,
                ),
              if (!state.hasBlockingError && state.hasWarning)
                _FindingsBanner(
                  issues: state.validation.issues
                      .where(
                        (issue) => issue.severity == ValidationSeverity.warning,
                      )
                      .toList(growable: false),
                  isError: false,
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      l10n.planPreviewIntro,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    for (final day in state.plan.days)
                      PlanDayCard(
                        day: day,
                        onReasonRequested: (block) {
                          PlanReasonSheet.show(context, block: block);
                        },
                        onBlockDurationChanged: (blockId, next) {
                          widget.controller.editBlockActiveDuration(
                            BlockId(blockId),
                            next,
                          );
                        },
                      ),
                  ],
                ),
              ),
              _ConfirmBar(
                state: state,
                warningAcknowledged: _warningAcknowledged,
                onAcknowledgeWarning: () =>
                    setState(() => _warningAcknowledged = true),
                onConfirm: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  final l10nOnTap = l10n;
                  final result = await widget.controller.confirmConfirmed();
                  if (!mounted) return;
                  if (result.isFailure) {
                    messenger.showSnackBar(
                      SnackBar(
                        key: const Key('plan-preview-confirm-error'),
                        content: Text(l10nOnTap.planPreviewConfirmFailed),
                      ),
                    );
                    return;
                  }
                  navigator.maybePop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FindingsBanner extends StatelessWidget {
  const _FindingsBanner({required this.issues, required this.isError});

  final List<PlanValidationIssue> issues;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      key: Key('plan-preview-findings-${isError ? 'error' : 'warning'}'),
      width: double.infinity,
      color: isError
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.tertiaryContainer,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isError
                ? l10n.planPreviewErrorBannerTitle
                : l10n.planPreviewWarningBannerTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              color: isError
                  ? theme.colorScheme.onErrorContainer
                  : theme.colorScheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                issue.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isError
                      ? theme.colorScheme.onErrorContainer
                      : theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({
    required this.state,
    required this.warningAcknowledged,
    required this.onAcknowledgeWarning,
    required this.onConfirm,
  });

  final PlanPreviewState state;
  final bool warningAcknowledged;
  final VoidCallback onAcknowledgeWarning;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final requiresAcknowledgement = state.hasWarning && !warningAcknowledged;
    final blocked = state.hasBlockingError;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (requiresAcknowledgement)
              OutlinedButton(
                key: const Key('plan-preview-acknowledge-warning'),
                onPressed: onAcknowledgeWarning,
                child: Text(l10n.planPreviewAcknowledgeWarning),
              ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('plan-preview-confirm'),
              onPressed: blocked || requiresAcknowledgement ? null : onConfirm,
              child: Text(
                blocked
                    ? l10n.planPreviewConfirmBlocked
                    : l10n.planPreviewConfirm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
