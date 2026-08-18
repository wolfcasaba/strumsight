import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/practice_block.dart';
import '../../domain/model/skill_priority.dart';

/// Presents the deterministic, factor-based reason a candidate ended up in
/// the plan (SDD Ch8 Kör 21, ADR 0264 §1, ADR 0261 §3).
///
/// The sheet never generates free text from `SkillPriority` numbers. Each
/// line is a reason code (`block.reasonCodes` from the generator) translated
/// from ARB by [_localizedFactorLine]; the `evidenceRefs` list is shown as
/// the chip strip so the learner sees *which* evidence supported the
/// decision. When the matching factor's `normalizedValue` is below the
/// confidence threshold, the sheet appends an explicit uncertainty line
/// (A6) — the ARB string is `planPreviewReasonUncertain` so the wording
/// stays identical in both languages.
class PlanReasonSheet extends StatelessWidget {
  const PlanReasonSheet({
    required this.block,
    required this.priority,
    super.key,
  });

  final PracticeBlock block;

  /// Optional: when the caller has the [SkillPriority] for the block's
  /// primary skill, the sheet can append the uncertainty line (A6). When
  /// `null`, the sheet renders only the reason-code lines.
  final SkillPriority? priority;

  /// Confidence threshold below which the uncertainty line is shown.
  /// The brief anchors this in ADR 0261 §3 (cap on inference under
  /// uncertainty); the default of 0.5 mirrors the engine's own
  /// `evidenceWeightPolicy.lowConfidenceThreshold` baseline.
  static const double uncertaintyThreshold = 0.5;

  static Future<void> show(
    BuildContext context, {
    required PracticeBlock block,
    SkillPriority? priority,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => PlanReasonSheet(
      block: block,
      priority: priority,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.planPreviewReasonTitle,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final code in block.reasonCodes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  _localizedFactorLine(l10n, code),
                  key: Key('plan-reason-line-$code'),
                ),
              ),
            if (block.evidenceRefs.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l10n.planPreviewReasonEvidenceLabel,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  for (final ref in block.evidenceRefs)
                    Chip(
                      key: Key('plan-reason-evidence-$ref'),
                      label: Text(ref),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            if (_isUncertain) ...[
              const SizedBox(height: 12),
              Text(
                l10n.planPreviewReasonUncertain,
                key: const Key('plan-reason-uncertain'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.tertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('plan-reason-close'),
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(l10n.planPreviewReasonClose),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _isUncertain {
    final priority = this.priority;
    if (priority == null) return false;
    final uncertaintyFactor = priority.factorFor(SkillPriorityFactorKind.uncertainty);
    if (uncertaintyFactor == null) return false;
    return uncertaintyFactor.normalizedValue >= uncertaintyThreshold;
  }
}

String _localizedFactorLine(AppLocalizations l10n, String code) =>
    switch (code) {
      'goal.primary' => l10n.planPreviewReasonGoalPrimary,
      'schedule.decision.selected' => l10n.planPreviewReasonScheduleSelected,
      'evidence.tempo-accuracy' => l10n.planPreviewReasonEvidenceTempo,
      'preview.day.removed' => l10n.planPreviewReasonDayRemoved,
      _ => l10n.planPreviewReasonGeneric(code),
    };
