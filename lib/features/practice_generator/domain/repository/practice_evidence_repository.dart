/// Storage port for [SkillEvidence] (ADR 0260 §5): evidence is written once
/// per [SkillEvidence.sourceOutcomeId] and never deleted by expiry — the
/// store is the "immutable past" (ADR 0256) the Kör 6 reducer needs to tell
/// "no data" apart from "old data".
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
}

/// In-memory [PracticeEvidenceRepository] fake for tests and the mock-mode
/// data path. Keeps every evidence ever saved; `query` filters, it never
/// forgets.
final class InMemoryPracticeEvidenceRepository
    implements PracticeEvidenceRepository {
  final Map<String, SkillEvidence> _byOutcomeId = <String, SkillEvidence>{};

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
}
