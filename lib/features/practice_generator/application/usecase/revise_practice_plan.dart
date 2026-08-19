/// Immutable, caller-fed proposals for future-only plan revisions.
library;

import '../../domain/id/planner_ids.dart';
import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/plan_change_set.dart';
import '../../domain/model/plan_revision.dart';
import '../../domain/model/practice_block.dart';

/// The learner's explicit response to a plan-change proposal.
enum PlanChangeConfirmation { pending, accepted, rejected }

/// Inputs for one revision proposal. The caller supplies every state snapshot.
final class RevisePracticePlanRequest {
  RevisePracticePlanRequest({
    required this.previous,
    required this.nextRevisionId,
    required this.candidateSnapshot,
    required Iterable<PlanChange> changes,
    required this.reason,
    required this.confirmation,
  }) : changes = List<PlanChange>.unmodifiable(changes);

  final PlanRevision previous;
  final RevisionId nextRevisionId;
  final AdaptivePracticePlan candidateSnapshot;
  final List<PlanChange> changes;
  final PlanRevisionReason reason;
  final PlanChangeConfirmation confirmation;
}

/// An auditable proposal. A pending or rejected major proposal has no revision.
final class PlanRevisionProposal {
  const PlanRevisionProposal({
    required this.changeSet,
    required this.confirmation,
    required this.requiresUserConfirmation,
    required this.revision,
  });

  final PlanChangeSet changeSet;
  final PlanChangeConfirmation confirmation;
  final bool requiresUserConfirmation;
  final PlanRevision? revision;

  bool get isActive => revision != null;
}

/// Makes a revision only after immutable-past and confirmation checks pass.
///
/// The confirmation boundary is two affected future items. It is deliberately
/// inclusive: one is a local adjustment; two or more can reshape a learner's
/// schedule and therefore require an explicit decision.
final class RevisePracticePlan {
  RevisePracticePlan({required this.clock});

  static const int confirmationThreshold = 2;

  final DateTime Function() clock;

  PlanRevisionProposal call(RevisePracticePlanRequest request) {
    _validateSamePlan(request);
    _validateImmutablePast(
      request.previous.snapshot,
      request.candidateSnapshot,
    );
    for (final change in request.changes) {
      _validateFutureTarget(request.previous.snapshot, change.target);
    }

    final requiresConfirmation =
        request.changes.length >= confirmationThreshold ||
        request.changes.any(_isStructuralChange);
    final changeSet = PlanChangeSet(
      fromRevisionId: request.previous.id,
      toRevisionId: request.nextRevisionId,
      changes: _withConfirmation(request.changes, requiresConfirmation),
    );
    final canActivate =
        !requiresConfirmation ||
        request.confirmation == PlanChangeConfirmation.accepted;
    if (!canActivate) {
      return PlanRevisionProposal(
        changeSet: changeSet,
        confirmation: request.confirmation,
        requiresUserConfirmation: requiresConfirmation,
        revision: null,
      );
    }

    final snapshot = request.candidateSnapshot.copyWith(
      activeRevisionId: request.nextRevisionId,
    );
    final revision = PlanRevision(
      id: request.nextRevisionId,
      planId: request.previous.planId,
      number: request.previous.number + 1,
      createdAt: clock(),
      reason: request.reason,
      changeSet: changeSet,
      snapshot: snapshot,
      previous: request.previous,
    );
    return PlanRevisionProposal(
      changeSet: changeSet,
      confirmation: request.confirmation,
      requiresUserConfirmation: requiresConfirmation,
      revision: revision,
    );
  }

  void _validateSamePlan(RevisePracticePlanRequest request) {
    if (request.candidateSnapshot.id != request.previous.planId) {
      throw ArgumentError.value(
        request.candidateSnapshot,
        'candidateSnapshot',
        'must belong to the previous revision plan',
      );
    }
  }

  void _validateImmutablePast(
    AdaptivePracticePlan previous,
    AdaptivePracticePlan candidate,
  ) {
    for (final oldDay in previous.days) {
      final nextDay = candidate.days.where((day) => day.id == oldDay.id);
      if (nextDay.length != 1) {
        throw StateError('Candidate must retain day ${oldDay.id.value}');
      }
      final replacement = nextDay.single;
      if (oldDay.status == PracticeItemStatus.completed &&
          replacement != oldDay) {
        throw StateError('Completed day ${oldDay.id.value} cannot be changed');
      }
      for (final oldBlock in oldDay.blocks) {
        final nextBlock = replacement.blocks.where(
          (block) => block.id == oldBlock.id,
        );
        if (nextBlock.length != 1) {
          throw StateError('Candidate must retain block ${oldBlock.id.value}');
        }
        if (oldBlock.status == PracticeItemStatus.completed &&
            nextBlock.single != oldBlock) {
          throw StateError(
            'Completed block ${oldBlock.id.value} cannot be changed',
          );
        }
      }
    }
  }

  void _validateFutureTarget(AdaptivePracticePlan plan, String target) {
    final targetRef = _PlanChangeTarget.parse(target);
    final days = plan.days.where((day) => day.id.value == targetRef.dayId);
    if (days.length != 1) throw StateError('Unknown change target $target');
    final day = days.single;
    if (day.status == PracticeItemStatus.completed) {
      throw StateError('Completed day ${day.id.value} cannot be changed');
    }
    final blockId = targetRef.blockId;
    if (blockId == null) return;
    final blocks = day.blocks.where((block) => block.id.value == blockId);
    if (blocks.length != 1) throw StateError('Unknown change target $target');
    if (blocks.single.status == PracticeItemStatus.completed) {
      throw StateError('Completed block $blockId cannot be changed');
    }
  }

  Iterable<PlanChange> _withConfirmation(
    Iterable<PlanChange> changes,
    bool requiresConfirmation,
  ) => changes.map(
    (change) => PlanChange(
      type: change.type,
      target: change.target,
      before: change.before,
      after: change.after,
      reason: change.reason,
      evidenceRefs: change.evidenceRefs,
      confidence: change.confidence,
      requiresUserConfirmation: requiresConfirmation,
      reversible: change.reversible,
    ),
  );

  bool _isStructuralChange(PlanChange change) =>
      change.type == PlanChangeType.added ||
      change.type == PlanChangeType.removed ||
      change.type == PlanChangeType.moved ||
      change.before.containsKey('primaryFocusSkillIds') ||
      change.after.containsKey('primaryFocusSkillIds') ||
      change.before.containsKey('timeBudgetMicros') ||
      change.after.containsKey('timeBudgetMicros');
}

final class _PlanChangeTarget {
  const _PlanChangeTarget({required this.dayId, required this.blockId});

  final String dayId;
  final String? blockId;

  static _PlanChangeTarget parse(String target) {
    final match = RegExp(r'^day:(.+?)(?::block:(.+))?$').firstMatch(target);
    if (match == null) {
      throw ArgumentError.value(
        target,
        'target',
        'must be day:<dayId> or day:<dayId>:block:<blockId>',
      );
    }
    return _PlanChangeTarget(dayId: match.group(1)!, blockId: match.group(2));
  }
}
