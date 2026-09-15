/// Today's learner-initiated plan change as a reviewable proposal
/// (E17-R06 — the `PlanChangeReviewScreen` entry point from `TodayPlan`).
///
/// The review screen is caller-fed: it renders a [PlanRevisionProposal] and
/// hands the learner's accept / reject decision back. This use case is the
/// production caller. It composes ONLY existing pieces — the
/// [ActivePlanController] that rewrites the first pending block of a day
/// to its shortest catalog-supported duration, and [RevisePracticePlan],
/// which turns that rewrite into an auditable proposal after the
/// immutable-past and confirmation checks — and adds no new plan
/// behaviour.
library;

import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/plan_change_set.dart';
import '../../domain/model/plan_revision.dart';
import '../../domain/model/practice_day.dart';
import '../../domain/model/weekly_availability.dart';
import '../controller/active_plan_controller.dart';
import 'revise_practice_plan.dart';

/// A proposal together with the request that produced it, so an accepted
/// review can be re-run through [RevisePracticePlan] with the learner's
/// confirmation and yield the activatable revision.
final class TodayPlanChangeProposal {
  const TodayPlanChangeProposal({
    required this.request,
    required this.proposal,
  });

  final RevisePracticePlanRequest request;
  final PlanRevisionProposal proposal;
}

/// Proposes shortening today's first pending block of the active plan.
final class ProposeTodayPlanChange {
  ProposeTodayPlanChange({
    required this.activePlanController,
    required this.revisePracticePlan,
  });

  final ActivePlanController activePlanController;
  final RevisePracticePlan revisePracticePlan;

  /// `null` when [plan] schedules nothing on [today] — there is no change
  /// to review. [currentRevisionNumber] is the persisted revision count
  /// the active snapshot sits at (1 when only the initial generation
  /// exists), so the proposed revision numbers itself correctly.
  TodayPlanChangeProposal? call({
    required AdaptivePracticePlan plan,
    required LocalDate today,
    required int currentRevisionNumber,
  }) {
    final day = _dayOn(plan, today);
    if (day == null) return null;

    final update = activePlanController.shorten(plan: plan, day: day);
    final previous = PlanRevision(
      id: plan.activeRevisionId,
      planId: plan.id,
      number: currentRevisionNumber,
      createdAt: plan.createdAt,
      reason: PlanRevisionReason.initialGeneration,
      snapshot: plan,
    );
    final request = RevisePracticePlanRequest(
      previous: previous,
      nextRevisionId: update.plan.activeRevisionId,
      candidateSnapshot: update.plan,
      changes: update.changeSet.changes.map(
        (change) => _withDayScopedTarget(change, day),
      ),
      reason: PlanRevisionReason.learnerReschedule,
      confirmation: PlanChangeConfirmation.pending,
    );
    return TodayPlanChangeProposal(
      request: request,
      proposal: revisePracticePlan(request),
    );
  }

  static PracticeDay? _dayOn(AdaptivePracticePlan plan, LocalDate today) {
    for (final day in plan.days) {
      if (day.localDate == today) return day;
    }
    return null;
  }

  /// [ActivePlanController] addresses a block as `block:<blockId>`;
  /// [RevisePracticePlan] validates targets in its own
  /// `day:<dayId>[:block:<blockId>]` scheme. The two contracts are bridged
  /// here, at the one seam that joins them, without changing either.
  static PlanChange _withDayScopedTarget(PlanChange change, PracticeDay day) {
    const blockPrefix = 'block:';
    if (!change.target.startsWith(blockPrefix)) return change;
    final blockId = change.target.substring(blockPrefix.length);
    return PlanChange(
      type: change.type,
      target: 'day:${day.id.value}:block:$blockId',
      before: change.before,
      after: change.after,
      reason: change.reason,
      evidenceRefs: change.evidenceRefs,
      confidence: change.confidence,
      requiresUserConfirmation: change.requiresUserConfirmation,
      reversible: change.reversible,
    );
  }

  /// The revision an ACCEPTED review yields — the caller activates its
  /// snapshot. `null` only if the revision cannot be made even with the
  /// learner's acceptance (never the case for a proposal this use case
  /// produced, kept nullable to mirror [PlanRevisionProposal.revision]).
  PlanRevision? accept(TodayPlanChangeProposal reviewed) {
    final request = reviewed.request;
    return revisePracticePlan(
      RevisePracticePlanRequest(
        previous: request.previous,
        nextRevisionId: request.nextRevisionId,
        candidateSnapshot: request.candidateSnapshot,
        changes: request.changes,
        reason: request.reason,
        confirmation: PlanChangeConfirmation.accepted,
      ),
    ).revision;
  }
}
