/// Turns an active plan plus the learner's local `today` into an auditable
/// [PlanRevisionProposal] — the producer the change-review screen was
/// missing (2026-09-06).
///
/// Until now `RevisePracticePlan` existed but nothing ever CALLED it with a
/// real plan: the change-review route was unreachable because no code built
/// a `PlanRevisionProposal`. This use case is that producer, and it invents
/// nothing — every input comes from an existing domain service:
///
///   * which days count as missed is [MissedDayPolicy]'s verdict
///     (ADR 0269, non-punitive: rest and unavailable days are NOT misses);
///   * whether the learner must confirm the change set is
///     [RevisePracticePlan]'s own threshold;
///   * the immutable-past and future-target invariants are checked by
///     [RevisePracticePlan], not re-implemented here.
///
/// ## What the proposed revision does
///
/// It **expires** every missed day (and its still-open blocks) and moves
/// nothing forward. That is the plan's stated policy, not a shortcut:
/// "Missed days never carry their quota forward" (ADR 0258 §3, A1 —
/// `missed_day_policy.dart`). A revision that piled the missed minutes onto
/// the next day would contradict the very policy that identified them.
///
/// ## Deliberate boundary
///
/// [RescheduleMode.readinessProposal] and
/// [RescheduleMode.readinessProposalReducedDifficulty] (a break of 21+ days)
/// additionally call for a *readiness* block at a reduced difficulty. Authoring
/// that block means re-running candidate selection against the catalog, which
/// is a generation concern, not a revision one — so this use case does NOT
/// fabricate one. It still expires the missed days (the part it can honestly
/// produce) and reports the mode on the decision, so the follow-up work is
/// visible rather than silently missing.
library;

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../data/local/local_practice_plan_repository.dart';
import '../../domain/id/planner_ids.dart';
import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/plan_change_set.dart';
import '../../domain/model/plan_enums.dart' show BlockKind;
import '../../domain/model/plan_revision.dart';
import '../../domain/model/practice_block.dart';
import '../../domain/model/practice_day.dart';
import '../../domain/model/weekly_availability.dart';
import '../../domain/policy/missed_day_policy.dart';
import 'revise_practice_plan.dart';

/// A proposal together with the request that produced it.
///
/// The request travels with the proposal so accepting it applies EXACTLY the
/// change set the learner reviewed — re-deriving it from the plan after the
/// tap would silently swap in a different change set if anything moved in
/// between.
final class PlanCatchUpProposal {
  const PlanCatchUpProposal({required this.proposal, required this.request});

  final PlanRevisionProposal proposal;
  final RevisePracticePlanRequest request;

  /// True when the change set is large or structural enough that
  /// [RevisePracticePlan] refuses to activate it without an explicit
  /// learner decision — i.e. when the change-review screen is the correct
  /// next destination.
  bool get requiresReview => proposal.requiresUserConfirmation;
}

final class ProposePlanCatchUp {
  ProposePlanCatchUp({
    required this.revise,
    required this.repository,
    required this.today,
    required this.generateId,
    MissedDayPolicy? policy,
  }) : policy = policy ?? MissedDayPolicy();

  final RevisePracticePlan revise;
  final LocalPracticePlanRepository repository;
  final LocalDate Function() today;
  final String Function() generateId;
  final MissedDayPolicy policy;

  /// Returns the proposal, or a `null` value when the plan needs no
  /// revision at all (no missed day). A `null` success is NOT an error: it
  /// is the "your plan is up to date" answer.
  Future<AppResult<PlanCatchUpProposal?>> call(
    AdaptivePracticePlan plan,
  ) async {
    final localToday = today();
    final decision = policy.evaluate(
      MissedDayInput(
        today: localToday,
        // The next scheduled day's own budget, carried through untouched —
        // the typed no-growth invariant (ADR 0258 §3). This use case never
        // grows it.
        nextDayBudget: _nextScheduledBudget(plan, localToday),
        observations: <MissedDayObservation>[
          for (final day in plan.days)
            MissedDayObservation(
              localDate: day.localDate,
              status: day.status,
              reasonCodes: day.reasonCodes,
              hasPrimaryFocus: _isMissable(day),
            ),
        ],
      ),
    );
    if (decision.missedDayCount == 0) {
      return const Success<PlanCatchUpProposal?>(null);
    }

    final missedDates = <LocalDate>{
      for (final row in decision.classifications)
        if (row.contributesToCount) row.localDate,
    };

    final archive = await repository.readArchive(plan.id);
    final ArchivedPracticeLog log;
    switch (archive) {
      case Success<ArchivedPracticeLog>(:final value):
        log = value;
      case Failure<ArchivedPracticeLog>(:final error):
        return Failure<PlanCatchUpProposal?>(error);
    }

    final PlanRevision previous;
    try {
      previous = _previousRevision(plan, log);
    } on ArgumentError catch (error, stackTrace) {
      return Failure<PlanCatchUpProposal?>(
        UnknownFailure(cause: error, stackTrace: stackTrace),
      );
    }

    final request = RevisePracticePlanRequest(
      previous: previous,
      nextRevisionId: RevisionId.generate(generateId),
      candidateSnapshot: plan.copyWith(
        days: <PracticeDay>[
          for (final day in plan.days)
            if (missedDates.contains(day.localDate)) _expire(day) else day,
        ],
      ),
      changes: <PlanChange>[
        for (final day in plan.days)
          if (missedDates.contains(day.localDate)) _changeFor(day),
      ],
      reason: PlanRevisionReason.systemAdaptation,
      // The learner has not decided yet — that is precisely what the
      // change-review screen is for. Passing `accepted` here to get a
      // ready-made revision would record a confirmation that never happened.
      confirmation: PlanChangeConfirmation.pending,
    );

    final PlanRevisionProposal proposal;
    try {
      proposal = revise(request);
    } on StateError catch (error, stackTrace) {
      return Failure<PlanCatchUpProposal?>(
        UnknownFailure(cause: error, stackTrace: stackTrace),
      );
    } on ArgumentError catch (error, stackTrace) {
      return Failure<PlanCatchUpProposal?>(
        UnknownFailure(cause: error, stackTrace: stackTrace),
      );
    }
    return Success<PlanCatchUpProposal?>(
      PlanCatchUpProposal(proposal: proposal, request: request),
    );
  }

  /// A day can be missed only while it is still open AND it actually carried
  /// a planned primary-focus block.
  ///
  /// The `canTransitionTo(expired)` half is what makes the action idempotent:
  /// a day this use case has already expired can no longer transition, so a
  /// second "adjust my plan" tap does not re-propose it (and never asks the
  /// domain for an illegal transition).
  bool _isMissable(PracticeDay day) =>
      day.canTransitionTo(PracticeItemStatus.expired) &&
      day.blocks.any(
        (block) =>
            block.kind == BlockKind.primaryFocus &&
            block.canTransitionTo(PracticeItemStatus.expired),
      );

  PracticeDay _expire(PracticeDay day) => day
      .replaceContent(
        blocks: <PracticeBlock>[
          for (final block in day.blocks)
            if (block.canTransitionTo(PracticeItemStatus.expired))
              block.transitionTo(PracticeItemStatus.expired)
            else
              block,
        ],
      )
      .transitionTo(PracticeItemStatus.expired);

  PlanChange _changeFor(PracticeDay day) => PlanChange(
    type: PlanChangeType.statusChanged,
    target: 'day:${day.id.value}',
    before: <String, Object?>{'status': day.status.code},
    after: <String, Object?>{'status': PracticeItemStatus.expired.code},
    reason: PlanChangeReason.missedPractice,
    evidenceRefs: <String>['missedDay:${day.localDate}'],
    // A calendar day that has passed is an observation, not an estimate.
    confidence: 1,
    // Set authoritatively by RevisePracticePlan for the whole change set.
    requiresUserConfirmation: false,
    // The status machine has no path out of `expired`: within this plan the
    // change cannot be undone. The previous revision's snapshot still exists,
    // but nothing in the shipped UI restores it — claiming `true` here would
    // promise a control the learner does not have.
    reversible: false,
  );

  Duration _nextScheduledBudget(AdaptivePracticePlan plan, LocalDate today) {
    for (final day in plan.days) {
      if (day.localDate.compareTo(today) >= 0) return day.timeBudget;
    }
    return Duration.zero;
  }

  /// The revision the active plan currently IS.
  ///
  /// When the archive holds the matching record its real number, timestamp
  /// and reason are used. When it does not — the very first generation is
  /// activated without an archive entry — the plan itself is revision 1 and
  /// its own `createdAt` is the honest timestamp; both facts come from the
  /// plan, neither is invented.
  PlanRevision _previousRevision(
    AdaptivePracticePlan plan,
    ArchivedPracticeLog log,
  ) {
    for (final archived in log.revisions) {
      if (archived.id == plan.activeRevisionId) {
        return PlanRevision(
          id: archived.id,
          planId: plan.id,
          number: archived.number,
          createdAt: archived.createdAt,
          reason: archived.reason,
          snapshot: plan,
        );
      }
    }
    return PlanRevision(
      id: plan.activeRevisionId,
      planId: plan.id,
      number: 1,
      createdAt: plan.createdAt,
      reason: PlanRevisionReason.initialGeneration,
      snapshot: plan,
    );
  }
}
