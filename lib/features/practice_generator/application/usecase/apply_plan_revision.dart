/// Applies a plan revision the learner has explicitly accepted
/// (2026-09-06).
///
/// The change-review screen only reports a DECISION; persisting is this use
/// case's job. It re-runs [RevisePracticePlan] on the very request the
/// learner reviewed, this time with [PlanChangeConfirmation.accepted], so
/// every immutable-past and future-target invariant is checked again by the
/// domain — the acceptance tap cannot bypass a rule the proposal itself was
/// held to.
///
/// Two writes, in this order:
///   1. the archive entry (append-only history), then
///   2. the active pointer (`activate`).
///
/// The order matters: the pointer is the last thing written, so a crash in
/// between leaves an orphan archive record — never an active plan whose
/// revision is missing from the history.
library;

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../data/local/local_practice_plan_repository.dart';
import '../../data/local/practice_plan_serializer.dart' show ArchivedRevision;
import '../../domain/model/adaptive_practice_plan.dart';
import 'revise_practice_plan.dart';

final class ApplyPlanRevision {
  const ApplyPlanRevision({required this.revise, required this.repository});

  final RevisePracticePlan revise;
  final LocalPracticePlanRepository repository;

  Future<AppResult<AdaptivePracticePlan>> call(
    RevisePracticePlanRequest reviewed,
  ) async {
    final PlanRevisionProposal accepted;
    try {
      accepted = revise(
        RevisePracticePlanRequest(
          previous: reviewed.previous,
          nextRevisionId: reviewed.nextRevisionId,
          candidateSnapshot: reviewed.candidateSnapshot,
          changes: reviewed.changes,
          reason: reviewed.reason,
          confirmation: PlanChangeConfirmation.accepted,
        ),
      );
    } on Object catch (error, stackTrace) {
      return Failure<AdaptivePracticePlan>(
        UnknownFailure(cause: error, stackTrace: stackTrace),
      );
    }

    final revision = accepted.revision;
    if (revision == null) {
      // Defensive: an accepted request always produces a revision under the
      // current policy. Reporting a failure is still the honest answer —
      // silently returning the OLD plan would look like a successful save.
      return const Failure<AdaptivePracticePlan>(
        ValidationFailure(cause: 'accepted revision was not activatable'),
      );
    }

    final archived = await repository.appendRevision(
      ArchivedRevision(
        id: revision.id,
        planId: revision.planId,
        number: revision.number,
        createdAt: revision.createdAt,
        reason: revision.reason,
        previousRevisionId: revision.previousRevisionId,
        snapshot: revision.snapshot,
      ),
    );
    if (archived case Failure<void>(:final error)) {
      return Failure<AdaptivePracticePlan>(error);
    }

    final activated = await repository.activateAndReport(revision.snapshot);
    return switch (activated) {
      Success<ActivePlanActivationOutcome>() => Success<AdaptivePracticePlan>(
        revision.snapshot,
      ),
      Failure<ActivePlanActivationOutcome>(:final error) =>
        Failure<AdaptivePracticePlan>(error),
    };
  }
}
