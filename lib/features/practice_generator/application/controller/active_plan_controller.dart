/// Explicit learner-initiated changes to an immutable active plan.
library;

import '../../domain/id/planner_ids.dart';
import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/exercise_candidate.dart';
import '../../domain/model/exercise_prescription.dart';
import '../../domain/model/plan_change_set.dart';
import '../../domain/model/plan_enums.dart';
import '../../domain/model/practice_block.dart';
import '../../domain/model/practice_day.dart';

/// A candidate resolver keeps this controller Flutter- and storage-free.
typedef ActivePlanCandidateResolver =
    ExerciseCandidate Function(PracticeBlock block);

/// Resolves all fallback candidates for a rewritten prescription.
typedef ActivePlanFallbackResolver =
    Iterable<ExerciseCandidate> Function(PracticeBlock block);

/// A new immutable snapshot plus the explanation of the learner's action.
final class ActivePlanUpdate {
  const ActivePlanUpdate({required this.plan, required this.changeSet});

  final AdaptivePracticePlan plan;
  final PlanChangeSet changeSet;
}

/// Builds user-requested plan revisions without executing practice blocks.
///
/// Persistence belongs to the composition layer; this controller returns the
/// complete new snapshot and its structured [PlanChangeSet] for it to save.
final class ActivePlanController {
  ActivePlanController({
    required this.generateRevisionId,
    required this.resolveCandidate,
    this.resolveFallbacks = _noFallbacks,
  });

  final RevisionId Function() generateRevisionId;
  final ActivePlanCandidateResolver resolveCandidate;
  final ActivePlanFallbackResolver resolveFallbacks;

  /// Makes the first pending block as short as its catalog contract allows.
  ActivePlanUpdate shorten({
    required AdaptivePracticePlan plan,
    required PracticeDay day,
  }) {
    final target = _firstPending(day);
    if (target == null) return _unchanged(plan);
    final candidate = resolveCandidate(target);
    final prescription = target.prescription;
    final shortened = ExercisePrescription(
      candidate: candidate,
      activeDuration: candidate.supportedDurations.minimum,
      restDuration: prescription.restDuration,
      tempoBpm: prescription.tempoBpm,
      repetition: prescription.repetition,
      loopCount: prescription.loopCount,
      hardElapsedLimit: prescription.hardElapsedLimit,
      successCriteria: prescription.successCriteria,
      fallbackCandidates: resolveFallbacks(target),
      progressionRule: prescription.progressionRule,
    );
    final rewritten = target.replaceContent(
      prescription: shortened,
      estimatedElapsed: shortened.elapsed,
    );
    final nextDay = day.replaceContent(
      blocks: [
        for (final block in day.blocks)
          if (block.id == target.id) rewritten else block,
      ],
    );
    return _replaceDay(
      plan: plan,
      previous: day,
      next: nextDay,
      target: 'block:${target.id.value}',
      before: <String, Object?>{
        'activeDurationMicros': prescription.activeDuration.inMicroseconds,
      },
      after: <String, Object?>{
        'activeDurationMicros': shortened.activeDuration.inMicroseconds,
      },
      type: PlanChangeType.updated,
    );
  }

  /// Pausing changes lifecycle state but retains every scheduled day.
  ActivePlanUpdate pause(AdaptivePracticePlan plan) => _replacePlan(
    plan: plan,
    next: plan.copyWith(status: PlanStatus.paused),
    target: 'plan:${plan.id.value}',
    before: <String, Object?>{'status': plan.status.code},
    after: <String, Object?>{'status': PlanStatus.paused.code},
    type: PlanChangeType.statusChanged,
  );

  /// Marks the first pending block skipped; it never deletes planned data.
  ActivePlanUpdate skip({
    required AdaptivePracticePlan plan,
    required PracticeDay day,
  }) {
    final target = _firstPending(day);
    if (target == null) return _unchanged(plan);
    final nextDay = day.replaceContent(
      blocks: [
        for (final block in day.blocks)
          if (block.id == target.id)
            block.transitionTo(PracticeItemStatus.skipped)
          else
            block,
      ],
    );
    return _replaceDay(
      plan: plan,
      previous: day,
      next: nextDay,
      target: 'block:${target.id.value}',
      before: <String, Object?>{'status': target.status.code},
      after: <String, Object?>{'status': PracticeItemStatus.skipped.code},
      type: PlanChangeType.statusChanged,
    );
  }

  ActivePlanUpdate _replaceDay({
    required AdaptivePracticePlan plan,
    required PracticeDay previous,
    required PracticeDay next,
    required String target,
    required Map<String, Object?> before,
    required Map<String, Object?> after,
    required PlanChangeType type,
  }) => _replacePlan(
    plan: plan,
    next: plan.copyWith(
      days: [
        for (final day in plan.days)
          if (day.id == previous.id) next else day,
      ],
    ),
    target: target,
    before: before,
    after: after,
    type: type,
  );

  ActivePlanUpdate _replacePlan({
    required AdaptivePracticePlan plan,
    required AdaptivePracticePlan next,
    required String target,
    required Map<String, Object?> before,
    required Map<String, Object?> after,
    required PlanChangeType type,
  }) {
    final revisionId = generateRevisionId();
    final revised = next.copyWith(activeRevisionId: revisionId);
    return ActivePlanUpdate(
      plan: revised,
      changeSet: PlanChangeSet(
        fromRevisionId: plan.activeRevisionId,
        toRevisionId: revisionId,
        changes: <PlanChange>[
          PlanChange(
            type: type,
            target: target,
            before: before,
            after: after,
            reason: PlanChangeReason.learnerReschedule,
            evidenceRefs: const <String>[],
            confidence: 1,
            requiresUserConfirmation: false,
            reversible: true,
          ),
        ],
      ),
    );
  }

  ActivePlanUpdate _unchanged(AdaptivePracticePlan plan) {
    final revisionId = generateRevisionId();
    return ActivePlanUpdate(
      plan: plan.copyWith(activeRevisionId: revisionId),
      changeSet: PlanChangeSet(
        fromRevisionId: plan.activeRevisionId,
        toRevisionId: revisionId,
        changes: const <PlanChange>[],
      ),
    );
  }

  PracticeBlock? _firstPending(PracticeDay day) {
    final pending =
        day.blocks
            .where(
              (block) =>
                  block.status == PracticeItemStatus.planned ||
                  block.status == PracticeItemStatus.ready,
            )
            .toList(growable: false)
          ..sort((left, right) => left.order.compareTo(right.order));
    return pending.isEmpty ? null : pending.first;
  }

  static Iterable<ExerciseCandidate> _noFallbacks(PracticeBlock _) =>
      const <ExerciseCandidate>[];
}
