/// Learner-facing, confirmation-before-activation view of a plan diff.
library;

import 'package:flutter/material.dart';

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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.planChangeReviewTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.planChangeReviewIntro),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: proposal.changeSet.changes.length,
                itemBuilder: (context, index) =>
                    _ChangeCard(change: proposal.changeSet.changes[index]),
              ),
            ),
            if (proposal.requiresUserConfirmation)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('plan-change-review-reject'),
                        onPressed: onRejected,
                        child: Text(l10n.planChangeReviewReject),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const Key('plan-change-review-accept'),
                        onPressed: onAccepted,
                        child: Text(l10n.planChangeReviewAccept),
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
    return Card(
      key: Key('plan-change-review-${change.target}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(change.target, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(l10n.planChangeReviewBefore),
            Text(_mapText(change.before)),
            const SizedBox(height: 8),
            Text(l10n.planChangeReviewAfter),
            Text(_mapText(change.after)),
            const SizedBox(height: 8),
            Text('${l10n.planChangeReviewReason}: ${change.reason.code}'),
            Text(
              '${l10n.planChangeReviewConfidence}: '
              '${change.confidence.toStringAsFixed(2)}',
            ),
            Text(
              '${l10n.planChangeReviewEvidence}: '
              '${change.evidenceRefs.join(', ')}',
            ),
            Text(
              '${l10n.planChangeReviewReversible}: '
              '${change.reversible ? l10n.planChangeReviewYes : l10n.planChangeReviewNo}',
            ),
          ],
        ),
      ),
    );
  }
}

String _mapText(Map<String, Object?> values) =>
    values.entries.map((entry) => '${entry.key}: ${entry.value}').join(', ');
