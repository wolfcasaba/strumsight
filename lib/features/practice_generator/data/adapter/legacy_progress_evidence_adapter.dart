/// Adapts Progress practice-log entries into [SkillEvidence] (ADR 0293, SDD
/// Ch8 Kör 7). Reads only the public `PracticeEntry` contract
/// (`progress/public.dart`) — never an internal Progress provider. A
/// `PracticeEntry` alone is not an outcome (ADR 0293 §3): it carries no
/// stable id, no skill link, and its `seconds` is an activity quantity, not a
/// normalised performance value (ADR 0293 §5). This adapter therefore only
/// ever derives evidence from a caller-supplied [LegacyProgressOutcome]
/// wrapper that carries that identity explicitly.
library;

import 'package:strumsight/features/progress/public.dart' show PracticeEntry;

import '../../application/port/skill_snapshot_reader.dart';
import '../../domain/id/planner_ids.dart';
import '../../domain/model/skill_evidence.dart';
import 'legacy_mapping_table.dart';

/// A caller-attested legacy practice outcome. [skillId], [sourceOutcomeId],
/// and [normalizedPerformance] are nullable on purpose: a wrapper the caller
/// could not fully populate must still be representable, so the adapter can
/// skip it with a warning instead of the caller having to filter it out
/// first (ADR 0293 §3, SDD Ch8 §5.4).
final class LegacyProgressOutcome {
  const LegacyProgressOutcome({
    required this.entry,
    required this.measuredAt,
    required this.capturedAt,
    this.skillId,
    this.sourceOutcomeId,
    this.normalizedPerformance,
  });

  final PracticeEntry entry;
  final DateTime measuredAt;
  final DateTime capturedAt;

  /// The target skill, attested by the caller — never inferred from
  /// [entry.source] or any other field (SDD Ch8 §5.1).
  final String? skillId;

  /// The stable dedup key (ADR 0260 §3) — never synthesised from
  /// [entry.day], iteration order, or a content hash (ADR 0293 §3).
  final OutcomeId? sourceOutcomeId;

  /// A caller-verified performance value already normalised to `[0, 1]`
  /// (ADR 0293 §5). [entry.seconds] is never used to calibrate this.
  final double? normalizedPerformance;
}

/// Reads [LegacyProgressOutcome]s (SDD Ch8 Kör 7 §5.1, §5.2, §5.4, §5.5).
final class LegacyProgressEvidenceAdapter
    implements SkillSnapshotReader<LegacyProgressOutcome> {
  const LegacyProgressEvidenceAdapter({
    this.mappingTable = LegacyMappingTable.builtIn,
    this.confidence = 1.0,
  });

  /// Only [LegacyMappingTable.version] is used here (as the produced
  /// evidence's `measurementVersion`, ADR 0293 §4) — the skill link itself
  /// always comes from [LegacyProgressOutcome.skillId], never a lookup.
  final LegacyMappingTable mappingTable;

  final double confidence;

  @override
  SkillSnapshotResult readEvidence(List<LegacyProgressOutcome> snapshot) {
    final evidence = <SkillEvidence>[];
    final warnings = <SkillSnapshotWarning>[];
    final seenOutcomeIds = <String>{};

    for (final outcome in snapshot) {
      final outcomeId = outcome.sourceOutcomeId;
      if (outcomeId == null) {
        warnings.add(
          const SkillSnapshotWarning(
            code: 'missingOutcomeId',
            detail: 'unidentified progress entry',
          ),
        );
        continue;
      }

      final skillId = outcome.skillId;
      if (skillId == null || skillId.trim().isEmpty) {
        warnings.add(
          SkillSnapshotWarning(
            code: 'missingSkillId',
            detail: outcomeId.value,
          ),
        );
        continue;
      }

      final performance = outcome.normalizedPerformance;
      if (performance == null ||
          !performance.isFinite ||
          performance < 0 ||
          performance > 1) {
        warnings.add(
          SkillSnapshotWarning(
            code: 'missingNormalizedPerformance',
            detail: outcomeId.value,
          ),
        );
        continue;
      }

      if (!seenOutcomeIds.add(outcomeId.value)) {
        continue;
      }

      evidence.add(
        SkillEvidence(
          skillId: skillId,
          source: EvidenceSource.progress,
          sourceOutcomeId: outcomeId,
          measurementVersion: mappingTable.version,
          measuredAt: outcome.measuredAt,
          capturedAt: outcome.capturedAt,
          confidence: confidence,
          performance: PerformanceEvidence(
            metricCode: 'legacyProgressPerformance',
            value: performance,
          ),
        ),
      );
    }

    return SkillSnapshotResult(evidence: evidence, warnings: warnings);
  }
}
