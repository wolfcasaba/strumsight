/// Learner-facing, confirmation-before-activation view of a plan diff.
library;

import 'package:flutter/material.dart';

import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/usecase/revise_practice_plan.dart';
import '../../domain/model/plan_change_set.dart';

/// Shows an auditable major plan proposal before the caller may activate it.
///
/// This widget has no repository or controller dependency: its callbacks hand
/// the learner's decision to the caller that owns persistence and activation.
class PlanChangeReviewScreen extends StatelessWidget {
  const PlanChangeReviewScreen({
    required this.proposal,
    required this.onAccepted,
    required this.onRejected,
    super.key,
  });

  final PlanRevisionProposal proposal;
  final VoidCallback onAccepted;
  final VoidCallback onRejected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.planChangeReviewTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(SsSpacing.space4),
              child: Text(
                l10n.planChangeReviewIntro,
                style: typography.bodyMedium.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: SsSpacing.space4,
                ),
                itemCount: proposal.changeSet.changes.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: SsSpacing.space2),
                itemBuilder: (context, index) =>
                    _ChangeCard(change: proposal.changeSet.changes[index]),
              ),
            ),
            if (proposal.requiresUserConfirmation)
              Padding(
                padding: const EdgeInsets.all(SsSpacing.space4),
                child: Row(
                  children: [
                    Expanded(
                      child: SsButton(
                        key: const Key('plan-change-review-reject'),
                        variant: SsButtonVariant.secondary,
                        onPressed: onRejected,
                        label: l10n.planChangeReviewReject,
                      ),
                    ),
                    const SizedBox(width: SsSpacing.space3),
                    Expanded(
                      child: SsButton(
                        key: const Key('plan-change-review-accept'),
                        onPressed: onAccepted,
                        label: l10n.planChangeReviewAccept,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.change});

  final PlanChange change;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final labelStyle = typography.labelLarge.copyWith(
      color: colors.textSecondary,
    );
    final valueStyle = typography.bodyMedium.copyWith(
      color: colors.textPrimary,
    );
    return SsCard(
      key: Key('plan-change-review-${change.target}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            change.target,
            style: typography.titleMedium.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: SsSpacing.space2),
          Text(l10n.planChangeReviewBefore, style: labelStyle),
          Text(_mapText(change.before), style: valueStyle),
          const SizedBox(height: SsSpacing.space2),
          Text(l10n.planChangeReviewAfter, style: labelStyle),
          Text(_mapText(change.after), style: valueStyle),
          const SizedBox(height: SsSpacing.space2),
          Text(
            '${l10n.planChangeReviewReason}: ${change.reason.code}',
            style: valueStyle,
          ),
          Text(
            '${l10n.planChangeReviewConfidence}: '
            '${change.confidence.toStringAsFixed(2)}',
            style: valueStyle,
          ),
          Text(
            '${l10n.planChangeReviewEvidence}: '
            '${change.evidenceRefs.join(', ')}',
            style: valueStyle,
          ),
          Text(
            '${l10n.planChangeReviewReversible}: '
            '${change.reversible ? l10n.planChangeReviewYes : l10n.planChangeReviewNo}',
            style: valueStyle,
          ),
        ],
      ),
    );
  }
}

String _mapText(Map<String, Object?> values) =>
    values.entries.map((entry) => '${entry.key}: ${entry.value}').join(', ');
