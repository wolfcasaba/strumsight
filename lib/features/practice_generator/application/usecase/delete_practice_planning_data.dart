/// User-initiated, one-shot delete of every practice-planning datum the
/// app holds on the learner's device (E07-R29 §5.5, §5.7, ADR 0260 §5
/// narrow exception).
///
/// Scope is **strict** and **enumerated**:
///
///   1. The active plan pointer + its immutable record (LocalPracticePlanRepository).
///   2. Every wizard draft key (LocalPracticePlanRepository).
///   3. Every archive revision / outcome record + their indexes
///      (LocalPracticePlanRepository), across every plan the planner has
///      ever recorded.
///   4. The wizard's resumable draft (GenerationDraftRepository).
///   5. Every [SkillEvidence] whose `sourceOutcomeId` belongs to a planner
///      outcome — exclusively via the
///      [PracticeEvidenceRepository.deleteForPlan] hook, the **only**
///      evidence-removal entry point exposed by ADR 0260 §5.
///
/// The use case never reads or writes any other feature's key prefix.
/// The repository's delete-all implementation is the structural
/// guarantee: it walks its own tracked key list and removes each one.
library;

import '../../../../core/foundation/app_result.dart';
import '../../data/local/generation_draft_repository.dart';
import '../../data/local/local_practice_plan_repository.dart';
import '../../domain/id/planner_ids.dart';
import '../../domain/repository/practice_evidence_repository.dart';

/// Result of a successful delete: the total number of planner
/// namespaces + evidence records removed, plus the set of `planId`s
/// whose evidence was purged. The UI uses this for the "done" toast.
final class DeletePracticePlanningDataResult {
  const DeletePracticePlanningDataResult({
    required this.plannerKeyCount,
    required this.evidenceRecordCount,
    required this.affectedPlanIds,
  });

  final int plannerKeyCount;
  final int evidenceRecordCount;
  final Set<PlanId> affectedPlanIds;
}

/// Pure use case: no logging, no telemetry. The platform logs that
/// already exist (if any) carry at most the stable `code` of the
/// failure, never the learner data.
///
/// Free-text "comfort notes" are NEVER carried through this use case —
/// the planner stores them in the wizard draft under a `comfort`
/// constraint (ADR 0265 §3), which is dropped along with every other
/// draft key in step 2.
class DeletePracticePlanningData {
  DeletePracticePlanningData({
    required this.planRepository,
    required this.draftRepository,
    required this.evidenceRepository,
  });

  final LocalPracticePlanRepository planRepository;
  final GenerationDraftRepository draftRepository;
  final PracticeEvidenceRepository evidenceRepository;

  Future<AppResult<DeletePracticePlanningDataResult>> call() async {
    // Step 1–3: planner-owned keys.
    final planDelete = await planRepository.deleteAllPlanningData();
    if (planDelete.isFailure) {
      return Failure<DeletePracticePlanningDataResult>(
        planDelete.failureOrNull!,
      );
    }
    final outcome = planDelete.valueOrNull!;

    // Step 4: the wizard's separate resumable draft.
    final draftClear = await draftRepository.clearDraft();
    if (draftClear.isFailure) {
      return Failure<DeletePracticePlanningDataResult>(
        draftClear.failureOrNull!,
      );
    }

    // Step 5: evidence, scope-restricted to the plans we just purged.
    var evidenceCount = 0;
    for (final planId in outcome.planIds) {
      evidenceCount += evidenceRepository.deleteForPlan(planId);
    }

    return Success<DeletePracticePlanningDataResult>(
      DeletePracticePlanningDataResult(
        plannerKeyCount: planRepository.trackedKeyCount,
        evidenceRecordCount: evidenceCount,
        affectedPlanIds: outcome.planIds,
      ),
    );
  }
}
