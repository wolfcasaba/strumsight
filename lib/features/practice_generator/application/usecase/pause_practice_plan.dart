/// Caller-fed pause of an active practice plan (ADR 0269 §5.3, SDD Ch8 Kör 27).
///
/// Pause is a one-line status change. The use case is intentionally tiny:
///
///   * The plan's day list is preserved unchanged.
///   * The plan's `status` flips to [PlanStatus.paused].
///   * The new revision is appended with [PlanRevisionReason.learnerReschedule]
///     — the existing reason is reused (no enum churn), and the resulting
///     revision chain is monotonic.
///
/// While paused, the plan accrues no "missed" days — ADR 0269 §5.3.
/// Today's `clock` is used only for the new revision's `createdAt`
/// timestamp; the `pauseDate` itself comes from the caller so the use
/// case never reads the wall clock for calendar logic (ADR 0258 §4).
library;

import '../../domain/id/planner_ids.dart';
import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/plan_enums.dart';
import '../../domain/model/plan_revision.dart';
import '../../domain/model/weekly_availability.dart';

/// Inputs for [PausePracticePlan]. The use case is caller-fed: the caller
/// supplies the current revision, the new revision id, the local date
/// the learner paused, and the [PlanRevisionReason] the caller wants on
/// the new revision.
final class PausePracticePlanRequest {
  const PausePracticePlanRequest({
    required this.previous,
    required this.nextRevisionId,
    required this.pauseDate,
    required this.reason,
  });

  /// The current active revision that is being paused. The revision's
  /// snapshot must have [PlanStatus.active] — a paused or already-
  /// superseded plan cannot be paused again.
  final PlanRevision previous;

  /// The new revision's id. Assigned by the caller (composition layer
  /// owns id generation).
  final RevisionId nextRevisionId;

  /// The local calendar day the learner paused. Never used for
  /// arithmetic in this use case — it is recorded on the new revision's
  /// chain so the [ResumePracticePlan] use case knows how many days
  /// elapsed during the pause (ADR 0258 §4).
  final LocalDate pauseDate;

  /// Why the pause happened. The default [PlanRevisionReason.learnerReschedule]
  /// already covers the only reason callers need today; the field is
  /// exposed so future callers (e.g. travel mode) can attach their own
  /// typed cause without an enum change here.
  final PlanRevisionReason reason;
}

/// Result of [PausePracticePlan]: the new revision plus the
/// caller-supplied pause date echoed back so a composition layer can
/// persist them together.
final class PausePracticePlanResult {
  const PausePracticePlanResult({
    required this.revision,
    required this.pauseDate,
  });

  final PlanRevision revision;
  final LocalDate pauseDate;
}

/// Pure use case. Persisting the new revision is the caller's job.
final class PausePracticePlan {
  PausePracticePlan({required this.clock});

  /// Returns the current wall-clock UTC time. Used only for the new
  /// revision's `createdAt` timestamp. Calendar arithmetic uses the
  /// caller-supplied [PausePracticePlanRequest.pauseDate].
  final DateTime Function() clock;

  PausePracticePlanResult call(PausePracticePlanRequest request) {
    final previous = request.previous;
    _validatePausable(previous);
    final next = previous.snapshot.copyWith(
      status: PlanStatus.paused,
      activeRevisionId: request.nextRevisionId,
    );
    final revision = PlanRevision(
      id: request.nextRevisionId,
      planId: previous.planId,
      number: previous.number + 1,
      createdAt: clock(),
      reason: request.reason,
      snapshot: next,
      previous: previous,
    );
    return PausePracticePlanResult(
      revision: revision,
      pauseDate: request.pauseDate,
    );
  }

  void _validatePausable(PlanRevision previous) {
    final status = previous.snapshot.status;
    if (status == PlanStatus.paused) {
      throw StateError('Cannot pause a plan whose status is already paused');
    }
    if (status != PlanStatus.active) {
      throw StateError(
        'Cannot pause a plan whose status is ${status.code}, expected active',
      );
    }
  }
}
