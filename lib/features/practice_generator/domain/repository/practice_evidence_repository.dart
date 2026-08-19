/// Storage port for [SkillEvidence] (ADR 0260 §5): evidence is written once
/// per [SkillEvidence.sourceOutcomeId] and never deleted by expiry — the
/// store is the "immutable past" (ADR 0256) the Kör 6 reducer needs to tell
/// "no data" apart from "old data".
///
/// **Sole deletion entry-point.** The only mutation that physically removes
/// evidence is [deleteForPlan], a user-initiated, plan-scoped hook reserved
/// for the `DeletePracticePlanningData` use case (E07-R29 §5.7). Every
/// other call site — the skill estimator reducer, the bounded `query`,
/// the schema migrator, the practice-evidence aggregator — sees an
/// evidence store that is **immutable**: expiry is query-time, never
/// storage-time. Implementations MUST throw [UnsupportedError] from any
/// other delete path.
library;

import '../id/planner_ids.dart';
import '../model/skill_evidence.dart';

abstract interface class PracticeEvidenceRepository {
  /// Persists [evidence], replacing any prior evidence sharing the same
  /// [SkillEvidence.sourceOutcomeId]. This is the only mutation the store
  /// exposes — there is deliberately no delete/expire operation.
  void save(SkillEvidence evidence);

  /// The stored evidence for [sourceOutcomeId], if any. The dedup lookup a
  /// caller uses before deciding whether to [save].
  SkillEvidence? findByOutcomeId(OutcomeId sourceOutcomeId);

  /// Every stored evidence for [skillId], expired or not (ADR 0260 §5:
  /// expiry is a query-time concern, not a storage-time one).
  List<SkillEvidence> allForSkill(String skillId);

  /// Bounded query: only [skillId], only evidence valid at [asOf] (the
  /// `validUntil` boundary is inclusive), optionally windowed to
  /// `[measuredFrom, measuredTo]` inclusive on `measuredAt`.
  List<SkillEvidence> query({
    required String skillId,
    required DateTime asOf,
    DateTime? measuredFrom,
    DateTime? measuredTo,
  });

  /// Removes every evidence record whose `sourceOutcomeId` belongs to
  /// [planId].
  ///
  /// **Sole evidence-removal entry-point** (E07-R29 §5.7, ADR 0260 §5
  /// narrow exception). Callable ONLY by
  /// `DeletePracticePlanningData`; any other caller — the reducer, the
  /// `query` path, the migrator, the aggregator — keeps evidence
  /// immutable.
  ///
  /// The `planId` parameter scopes the delete: evidence written by another
  /// feature with a `sourceOutcomeId` that happens to share a string value
  /// is never reached, because no other feature persists evidence through
  /// this port (it is the planner's exclusive evidence store).
  ///
  /// Returns the number of evidence records removed, primarily so tests
  /// can assert that the hook ran end-to-end.
  int deleteForPlan(PlanId planId);
}

/// In-memory [PracticeEvidenceRepository] fake for tests and the mock-mode
/// data path. Keeps every evidence ever saved; `query` filters, it never
/// forgets.
///
/// The sole deletion path [deleteForPlan] is reserved for the planner's
/// own "delete everything" use case (E07-R29 §5.7). It is not used by the
/// reducer, the bounded query, the migrator or the aggregator.
final class InMemoryPracticeEvidenceRepository
    implements PracticeEvidenceRepository {
  /// Optional lookup table to scope the plan-scoped delete. Tests that
  /// build evidence with `sourceOutcomeId` outside the planner's own
  /// outcome-id space inject a custom resolver so the delete can prove it
  /// never reaches across the feature boundary. The default returns
  /// `null` — evidence was written by the planner and therefore belongs
  /// to the planner's own plan-id space, which the caller knows.
  InMemoryPracticeEvidenceRepository({
    PlanId? Function(String sourceOutcomeId)? outcomePlanLookup,
  }) : _outcomePlanLookup = outcomePlanLookup;

  final Map<String, SkillEvidence> _byOutcomeId = <String, SkillEvidence>{};
  final PlanId? Function(String sourceOutcomeId)? _outcomePlanLookup;

  @override
  void save(SkillEvidence evidence) {
    _byOutcomeId[evidence.sourceOutcomeId.value] = evidence;
  }

  @override
  SkillEvidence? findByOutcomeId(OutcomeId sourceOutcomeId) =>
      _byOutcomeId[sourceOutcomeId.value];

  @override
  List<SkillEvidence> allForSkill(String skillId) => _byOutcomeId.values
      .where((evidence) => evidence.skillId == skillId)
      .toList(growable: false);

  @override
  List<SkillEvidence> query({
    required String skillId,
    required DateTime asOf,
    DateTime? measuredFrom,
    DateTime? measuredTo,
  }) {
    final asOfUtc = asOf.toUtc();
    final fromUtc = measuredFrom?.toUtc();
    final toUtc = measuredTo?.toUtc();
    if (fromUtc != null && toUtc != null && toUtc.isBefore(fromUtc)) {
      throw ArgumentError.value(
        measuredTo,
        'measuredTo',
        'must not be before measuredFrom',
      );
    }
    return _byOutcomeId.values
        .where((evidence) {
          if (evidence.skillId != skillId) return false;
          if (!evidence.isValidAt(asOfUtc)) return false;
          if (fromUtc != null && evidence.measuredAt.isBefore(fromUtc)) {
            return false;
          }
          if (toUtc != null && evidence.measuredAt.isAfter(toUtc)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  @override
  int deleteForPlan(PlanId planId) {
    final owned = _outcomePlanLookup;
    var removed = 0;
    _byOutcomeId.removeWhere((outcomeId, evidence) {
      final owner = owned == null ? planId : owned(outcomeId);
      if (owner == planId) {
        removed++;
        return true;
      }
      return false;
    });
    return removed;
  }
}
