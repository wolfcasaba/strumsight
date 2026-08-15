/// Ingests raw [SkillEvidence] into a [PracticeEvidenceRepository] with
/// source-outcome deduplication and redaction-safe structured logging
/// (ADR 0260 §3, §4).
library;

import '../../../../core/logging/app_logger.dart';
import '../../domain/model/skill_evidence.dart';
import '../../domain/repository/practice_evidence_repository.dart';

/// Stable event names emitted by [EvidenceAggregator].
abstract final class EvidenceAggregatorEvent {
  static const String ingested = 'evidence.ingested';
  static const String duplicateIgnored = 'evidence.duplicate.ignored';
}

/// Aggregates evidence from any source into one deduplicated store.
///
/// The pre-flight measurement of `main @ c4497773` (round brief §0.0) found
/// call sites are not trusted to remember redaction, so this aggregator only
/// ever logs a stable outcome identifier and a discomfort *category*.
/// [SkillEvidence] itself has no field capable of holding a discomfort
/// free-text note (ADR 0260 §1, §4) — [ingest]'s [discomfortNote] parameter
/// exists only so a future self-report call site (Kör 7-8) can hand off the
/// learner's raw text without having to remember to strip it first. It is
/// discarded immediately at this boundary: never attached to [evidence],
/// never passed to [_repository], never passed to [logger] (not in an event
/// name, a field, or an exception), and never returned.
final class EvidenceAggregator {
  const EvidenceAggregator({
    required PracticeEvidenceRepository repository,
    AppLogger logger = const NoopAppLogger(),
  }) : _repository = repository, // ignore: prefer_initializing_formals
       _logger = logger; // ignore: prefer_initializing_formals

  final PracticeEvidenceRepository _repository;
  final AppLogger _logger;

  /// Ingests [evidence]. If a prior evidence with the same
  /// [SkillEvidence.sourceOutcomeId] already exists (ADR 0260 §3: the same
  /// practice seen by two adapters), the existing evidence wins and
  /// [evidence] is dropped — this keeps ingestion idempotent regardless of
  /// replay order. Returns the evidence now held by the repository for this
  /// outcome id.
  ///
  /// [discomfortNote] is accepted and immediately discarded — see the class
  /// doc. It is never read by this method.
  SkillEvidence ingest(SkillEvidence evidence, {String? discomfortNote}) {
    final existing = _repository.findByOutcomeId(evidence.sourceOutcomeId);
    if (existing != null) {
      _logger.info(
        EvidenceAggregatorEvent.duplicateIgnored,
        fields: <String, Object?>{
          'skillId': evidence.skillId,
          'source': evidence.source.code,
          'sourceOutcomeId': evidence.sourceOutcomeId.value,
        },
      );
      return existing;
    }

    _repository.save(evidence);
    _logger.info(
      EvidenceAggregatorEvent.ingested,
      fields: <String, Object?>{
        'skillId': evidence.skillId,
        'source': evidence.source.code,
        'sourceOutcomeId': evidence.sourceOutcomeId.value,
        if (evidence.discomfort != null)
          'discomfortCategory': evidence.discomfort!.category.code,
      },
    );
    return evidence;
  }
}
