/// Immutable full snapshots of an adaptive practice plan (ADR 0256).
library;

import '../id/planner_ids.dart';
import 'adaptive_practice_plan.dart';
import 'plan_change_set.dart';

enum PlanRevisionReason {
  initialGeneration('initialGeneration'),
  learnerReschedule('learnerReschedule'),
  systemAdaptation('systemAdaptation'),
  modelSuggestionAccepted('modelSuggestionAccepted'),
  goalChanged('goalChanged');

  const PlanRevisionReason(this.code);

  final String code;
}

/// An append-only revision. [snapshot] is a complete immutable plan value,
/// never a delta or a pointer to mutable current-plan state.
final class PlanRevision {
  PlanRevision({
    required this.id,
    required this.planId,
    required int number,
    required DateTime createdAt,
    required this.reason,
    required this.snapshot,
    this.changeSet,
    PlanRevision? previous,
  }) : number = _positive(number),
       createdAt = createdAt.toUtc(),
       previousRevisionId = previous?.id {
    if (snapshot.id != planId) {
      throw ArgumentError.value(snapshot, 'snapshot', 'must belong to planId');
    }
    if (previous != null) {
      if (previous.planId != planId) {
        throw ArgumentError.value(
          previous,
          'previous',
          'must belong to planId',
        );
      }
      if (number <= previous.number) {
        throw ArgumentError.value(
          number,
          'number',
          'must be strictly greater than the previous revision number',
        );
      }
    }
  }

  final RevisionId id;
  final PlanId planId;
  final int number;
  final DateTime createdAt;
  final PlanRevisionReason reason;
  final PlanChangeSet? changeSet;
  final AdaptivePracticePlan snapshot;
  final RevisionId? previousRevisionId;
}

int _positive(int value) {
  if (value <= 0) {
    throw ArgumentError.value(value, 'number', 'must be positive');
  }
  return value;
}
