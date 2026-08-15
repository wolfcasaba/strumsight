/// Adapts Learn lesson outcomes into [SkillEvidence] (ADR 0293, SDD Ch8 Kör
/// 7). Reads only the public `Lesson` contract (`learn/public.dart`) — never
/// an internal Learn provider — and never infers a skill from a lesson's
/// name, chords, or difficulty (SDD Ch8 §5.1): the only source of a skill id
/// is [LegacyMappingTable].
library;

import 'package:strumsight/features/learn/public.dart' show Lesson;

import '../../application/port/skill_snapshot_reader.dart';
import '../../domain/id/planner_ids.dart';
import '../../domain/model/skill_evidence.dart';
import 'legacy_mapping_table.dart';

/// One completed lesson, with the caller-supplied identity ADR 0293 §3
/// requires: this adapter never fabricates [sourceOutcomeId], [measuredAt],
/// or [capturedAt] from the lesson itself.
final class LegacyLessonOutcome {
  const LegacyLessonOutcome({
    required this.lesson,
    required this.sourceOutcomeId,
    required this.measuredAt,
    required this.capturedAt,
    required this.performance,
  });

  final Lesson lesson;
  final OutcomeId sourceOutcomeId;
  final DateTime measuredAt;
  final DateTime capturedAt;

  /// The caller's best-accuracy measurement for this outcome. Never derived
  /// internally — Learn's public `Lesson` carries no such field.
  final PerformanceEvidence performance;
}

/// Reads [LegacyLessonOutcome]s against a [LegacyMappingTable] (SDD Ch8 Kör
/// 7 §5.1, §5.2, §5.5).
final class LegacyLessonCatalogAdapter
    implements SkillSnapshotReader<LegacyLessonOutcome> {
  const LegacyLessonCatalogAdapter({
    this.mappingTable = LegacyMappingTable.builtIn,
    this.confidence = 1.0,
  });

  final LegacyMappingTable mappingTable;

  /// Fixed measurement confidence for every evidence this adapter produces.
  /// Source-level trust (legacy vs. live) is expressed by
  /// `EvidenceSource.learn` through `EvidenceWeightPolicy.sourceReliability`
  /// (ADR 0293 §5.3), not by this field.
  final double confidence;

  @override
  SkillSnapshotResult readEvidence(List<LegacyLessonOutcome> snapshot) {
    final evidence = <SkillEvidence>[];
    final warnings = <SkillSnapshotWarning>[];
    final seenOutcomeIds = <String>{};

    for (final outcome in snapshot) {
      if (!seenOutcomeIds.add(outcome.sourceOutcomeId.value)) {
        continue;
      }

      final lessonId = outcome.lesson.id;
      final skillIds = mappingTable.skillIdsFor(lessonId);
      if (skillIds == null) {
        warnings.add(
          SkillSnapshotWarning(code: 'unmappedLesson', detail: lessonId),
        );
        continue;
      }
      if (skillIds.isEmpty) {
        warnings.add(
          SkillSnapshotWarning(code: 'emptySkillMapping', detail: lessonId),
        );
        continue;
      }

      for (final skillId in skillIds) {
        evidence.add(
          SkillEvidence(
            skillId: skillId,
            source: EvidenceSource.learn,
            sourceOutcomeId: outcome.sourceOutcomeId,
            measurementVersion: mappingTable.version,
            measuredAt: outcome.measuredAt,
            capturedAt: outcome.capturedAt,
            confidence: confidence,
            performance: outcome.performance,
          ),
        );
      }
    }

    return SkillSnapshotResult(evidence: evidence, warnings: warnings);
  }
}
