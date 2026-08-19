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
///
/// **Ownership as data (E07-R29 review F2).** The default implementation
/// never treats "no lookup" as "every record belongs to the caller".
/// Evidence saved through this port carries its owning [PlanId] as a
/// first-class data relation (`sourcePlanId` on `save`); [deleteForPlan]
/// only removes records whose recorded ownership equals the caller. The
/// legacy [outcomePlanLookup] callback is still supported for tests that
/// build arbitrary outcome-id spaces — but when neither data relation nor
/// lookup is supplied for a record, that record is kept (safe default;
/// ownership is refused, the record is not silently claimed).
library;

import '../id/planner_ids.dart';
import '../model/skill_evidence.dart';

abstract interface class PracticeEvidenceRepository {
  /// Persists [evidence] as belonging to [sourcePlanId], replacing any
  /// prior evidence sharing the same
  /// [SkillEvidence.sourceOutcomeId].
  ///
  /// [sourcePlanId] is the **data relation** that scopes the E07-R29
  /// §5.7 narrow exception: without it, [deleteForPlan] refuses to
  /// remove the record on the sole basis of an `outcomeId` string match.
  /// A record saved without [sourcePlanId] is recorded as
  /// `ownership-known: false`, which [deleteForPlan] treats as
  /// "never owned by the caller's plan-id".
  void save(SkillEvidence evidence, {PlanId? sourcePlanId});

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

  /// Removes every evidence record whose **recorded ownership** belongs
  /// to [planId].
  ///
  /// **Sole evidence-removal entry-point** (E07-R29 §5.7, ADR 0260 §5
  /// narrow exception). Callable ONLY by
  /// `DeletePracticePlanningData`; any other caller — the reducer, the
  /// `query` path, the migrator, the aggregator — keeps evidence
  /// immutable.
  ///
  /// Ownership is determined by the data relation recorded via [save]
  /// (`sourcePlanId`) first; if that field is missing for a record, an
  /// optional [outcomePlanLookup] callback provided at construction time
  /// is consulted. Records with neither known source-plan-id nor a
  /// successful lookup are **never** deleted by this method — the
  /// absence of ownership data is a refusal, not a wildcard.
  ///
  /// Returns the number of evidence records removed, primarily so tests
  /// can assert that the hook ran end-to-end.
  int deleteForPlan(PlanId planId);

  /// Removes exactly the evidence records whose `sourceOutcomeId` appears
  /// in [sourceOutcomeIds] and whose recorded ownership (data relation or
  /// per-record fallback lookup) belongs to [planId]. The
  /// precise-archive-outcome-id-set entry-point used by the
  /// `DeletePracticePlanningData` use case to avoid widening the scope
  /// beyond the outcomes the local planner actually recorded.
  ///
  /// Returns the number of evidence records removed.
  int deleteForOutcomes(PlanId planId, Set<OutcomeId> sourceOutcomeIds);
}

/// In-memory [PracticeEvidenceRepository] fake for tests and the mock-mode
/// data path. Keeps every evidence ever saved; `query` filters, it never
/// forgets.
///
/// The sole deletion paths [deleteForPlan] and [deleteForOutcomes] are
/// reserved for the planner's own "delete everything" use case (E07-R29
/// §5.7). They are not used by the reducer, the bounded query, the
/// migrator or the aggregator.
///
/// **F2 fix (default ownership must not be the caller).** Save records
/// carry a `_evidenceOwnership` side-table keyed by outcome-id. Records
/// saved without a `sourcePlanId` AND without a matching lookup fallback
/// have unknown ownership and are immune from [deleteForPlan] /
/// [deleteForOutcomes] — the absence of a known owner is treated as
/// "not the caller's record", not "the caller's record".
final class InMemoryPracticeEvidenceRepository
    implements PracticeEvidenceRepository {
  InMemoryPracticeEvidenceRepository({this.outcomePlanLookup});

  /// Optional fallback lookup table for records saved without a
  /// `sourcePlanId` (e.g. legacy tests that build evidence through a
  /// string-prefix pattern). The default returns `null` — such a record
  /// has unknown ownership and is never matched by
  /// [deleteForPlan] / [deleteForOutcomes].
  final PlanId? Function(String sourceOutcomeId)? outcomePlanLookup;

  final Map<String, SkillEvidence> _byOutcomeId = <String, SkillEvidence>{};

  /// Per-record ownership data relation. `null` means "ownership unknown
  /// for this record"; the [deleteForPlan] / [deleteForOutcomes] methods
  /// use null-ownership as a *refusal* signal, not a wildcard.
  final Map<String, PlanId> _evidenceOwnership = <String, PlanId>{};

  /// Theffective ownership resolved through the side-table first and
  /// the lookup fallback second. Returns `null` if no relation is known.
  PlanId? _resolveOwnership(String outcomeIdValue) {
    final own = _evidenceOwnership[outcomeIdValue];
    if (own != null) return own;
    final lookup = outcomePlanLookup;
    if (lookup == null) return null;
    return lookup(outcomeIdValue);
  }

  @override
  void save(SkillEvidence evidence, {PlanId? sourcePlanId}) {
    _byOutcomeId[evidence.sourceOutcomeId.value] = evidence;
    if (sourcePlanId != null) {
      _evidenceOwnership[evidence.sourceOutcomeId.value] = sourcePlanId;
    } else {
      // Explicitly clear any previous ownership so a re-save without a
      // `sourcePlanId` does not silently inherit an old relation.
      _evidenceOwnership.remove(evidence.sourceOutcomeId.value);
    }
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
    var removed = 0;
    final outcomeIds = _byOutcomeId.keys.toList(growable: false);
    for (final outcomeId in outcomeIds) {
      final owner = _resolveOwnership(outcomeId);
      // F2 fix: ownership must be a known, matching relation — never
      // the caller as a fallback when ownership is unknown.
      if (owner == planId) {
        _byOutcomeId.remove(outcomeId);
        _evidenceOwnership.remove(outcomeId);
        removed++;
      }
    }
    return removed;
  }

  @override
  int deleteForOutcomes(PlanId planId, Set<OutcomeId> sourceOutcomeIds) {
    var removed = 0;
    for (final outcomeId in sourceOutcomeIds) {
      final value = outcomeId.value;
      final owner = _resolveOwnership(value);
      // The precise-archive-outcome-id-set path: the caller passes the
      // exact outcome-ids they intend to wipe; we still gate by ownership
      // so a record whose owning plan disagrees is left intact.
      if (owner == planId && _byOutcomeId.containsKey(value)) {
        _byOutcomeId.remove(value);
        _evidenceOwnership.remove(value);
        removed++;
      }
    }
    return removed;
  }
}
