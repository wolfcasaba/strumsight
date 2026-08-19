/// Audio Analysis V2 → Practice Generator evidence adapter (E07-R25,
/// brief §4, §5.4, §5.6, §6/A3/A4/A6).
///
/// Reads caller-supplied [AnalysisEvidenceView]s through the
/// [AnalysisEvidenceReader] port, then turns the reader result into
/// [SkillEvidence] (`EvidenceSource.analyzeV2`) plus structural advisories
/// — never modifies raw analysis-side data, never reads a wall clock, and
/// uses only types from `lib/features/audio_analysis/public.dart` (A8).
///
/// This adapter enforces, in order:
///   * A4 — a recording-level [SignalQualityReport] below
///     [signalQualityThreshold] is exposed as a [SignalQualityAdvisory]
///     (a setup/assessment suggestion, never a degraded performance
///     value). It is NEVER injected into a [SkillEvidence.performance].
///   * A6 — when multiple within-source metric facts targeting the same
///     [skillHint] disagree by more than [conflictThreshold] on the
///     normalised scale, every fact in the group keeps its source
///     identity but its confidence is multiplied by
///     `(1 - conflictUncertaintyPenalty)` (more uncertainty, no
///     arbitrary preference, ADR 0261 §3).
///   * A7 — an `unavailable` capability is recorded as an
///     [AnalysisEvidenceAdapterWarning] only; it never becomes a 0/0.0
///     placeholder or a `null` performance value.
///   * A3 — low-confidence records ARE admitted (the
///     `singleEvidenceInfluenceCap` in `EvidenceWeightPolicy.weightFor`
///     bounds their aggregate influence, so they cannot drive aggressive
///     focus), but their passage is visible via a `lowConfidence`
///     warning so downstream code does not re-introduce an ad-hoc
///     multiplier on top.
library;

import '../../application/port/analysis_evidence_reader.dart';
import '../../domain/id/planner_ids.dart';
import '../../domain/model/skill_evidence.dart';

/// Stable, log-safe reason the adapter could not turn a view (or a fact,
/// or a within-batch grouping) into a [SkillEvidence]. [code] is the log
/// key; [detail] is a non-sensitive identifier (a metric id, a skillHint,
/// or a stable capability name).
final class AnalysisEvidenceAdapterWarning {
  const AnalysisEvidenceAdapterWarning({
    required this.code,
    required this.detail,
  });

  final String code;
  final String detail;

  @override
  String toString() => 'AnalysisEvidenceAdapterWarning($code: $detail)';

  @override
  bool operator ==(Object other) =>
      other is AnalysisEvidenceAdapterWarning &&
      code == other.code &&
      detail == other.detail;

  @override
  int get hashCode => Object.hash(code, detail);
}

/// Setup-style advisory surfaced by the adapter when the recording-level
/// signal-quality report indicates bad input. The reducer treats this as
/// a separate channel: it is NEVER combined with any
/// `SkillEvidence.performance` value.
final class SignalQualityAdvisory {
  const SignalQualityAdvisory({
    required this.code,
    required this.observedOverall,
    required this.threshold,
  });

  final String code;
  final double observedOverall;
  final double threshold;

  @override
  bool operator ==(Object other) =>
      other is SignalQualityAdvisory &&
      code == other.code &&
      observedOverall == other.observedOverall &&
      threshold == other.threshold;

  @override
  int get hashCode => Object.hash(code, observedOverall, threshold);
}

/// What the adapter emits for one call to [AnalysisEvidenceAdapter.adapt].
final class AnalysisEvidenceAdapterResult {
  const AnalysisEvidenceAdapterResult({
    required this.evidence,
    required this.warnings,
    this.signalQualityAdvisory,
  });

  final List<SkillEvidence> evidence;
  final List<AnalysisEvidenceAdapterWarning> warnings;
  final SignalQualityAdvisory? signalQualityAdvisory;

  @override
  bool operator ==(Object other) =>
      other is AnalysisEvidenceAdapterResult &&
      _listEq(evidence, other.evidence) &&
      _listEq(warnings, other.warnings) &&
      signalQualityAdvisory == other.signalQualityAdvisory;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(evidence),
    Object.hashAll(warnings),
    signalQualityAdvisory,
  );
}

bool _listEq<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

/// Maps analysis-side views into [SkillEvidence] (with the appropriate
/// conflict-aware confidence) plus structural [SignalQualityAdvisory] /
/// warning channels. The adapter is pure: same input + same [asOf] →
/// same output; no clock is read internally.
final class AnalysisEvidenceAdapter {
  const AnalysisEvidenceAdapter({
    required this.reader,
    required this.measurementVersion,
    required this.signalQualityThreshold,
    required this.conflictThreshold,
    required this.conflictUncertaintyPenalty,
  }) : assert(measurementVersion >= 1, 'measurementVersion must be >= 1'),
       assert(
         signalQualityThreshold > 0 && signalQualityThreshold <= 1,
         'signalQualityThreshold must be in (0, 1]',
       ),
       assert(conflictThreshold > 0, 'conflictThreshold must be > 0'),
       assert(
         conflictUncertaintyPenalty >= 0 && conflictUncertaintyPenalty < 1,
         'conflictUncertaintyPenalty must be in [0, 1)',
       );

  /// The reader port. The default reader is dependency-free and only
  /// touches the public Analysis API (A8).
  final AnalysisEvidenceReader reader;

  /// `SkillEvidence.measurementVersion` for every record produced.
  final int measurementVersion;

  /// Below this signal-quality score the recording/clip level report
  /// triggers a separate [SignalQualityAdvisory] (A4). It is never
  /// injected into [SkillEvidence.performance].
  final double signalQualityThreshold;

  /// Maximum allowed normalised value-spread within a single [skillHint]
  /// group before the adapter applies the conflict penalty (A6).
  final double conflictThreshold;

  /// Multiplier removed from every fact's confidence in a conflicting
  /// group (A6). 0.45 matches the `EvidenceWeightPolicy` default; tests
  /// may override.
  final double conflictUncertaintyPenalty;

  /// Adapts the views into [AnalysisEvidenceAdapterResult].
  AnalysisEvidenceAdapterResult adapt(
    List<AnalysisEvidenceView> views, {
    required DateTime asOf,
  }) {
    final outcome = reader.read(views);
    final facts = outcome.facts;
    final warnings = <AnalysisEvidenceAdapterWarning>[];

    // (A4) Setup-vs-skill split. The advisory is a SEPARATE channel —
    // metric facts still emit, the signal-quality number never enters
    // a [SkillEvidence.performance].
    SignalQualityAdvisory? advisory;
    final sq = facts.signalQuality;
    if (sq != null && sq.overall < signalQualityThreshold) {
      advisory = SignalQualityAdvisory(
        code: 'recordingQualityLow',
        observedOverall: sq.overall,
        threshold: signalQualityThreshold,
      );
    }

    // (A6) Within-batch conflict detection per skillHint.
    final bySkillHint = <String, List<AnalysisMetricFact>>{};
    for (final fact in facts.metricFacts) {
      bySkillHint
          .putIfAbsent(fact.skillHint, () => <AnalysisMetricFact>[])
          .add(fact);
    }

    final conflictGroups = <String>{};
    for (final entry in bySkillHint.entries) {
      if (entry.value.length < 2) continue;
      final values = entry.value.map((f) => f.value).toList()..sort();
      final spread = values.last - values.first;
      if (spread > conflictThreshold) {
        conflictGroups.add(entry.key);
        warnings.add(
          AnalysisEvidenceAdapterWarning(
            code: 'withinSourceConflict',
            detail: entry.key,
          ),
        );
      }
    }

    // Build SkillEvidence records.
    final evidence = <SkillEvidence>[];
    for (final entry in bySkillHint.entries) {
      final factList = entry.value;
      final conflictPenalty = conflictGroups.contains(entry.key)
          ? conflictUncertaintyPenalty
          : 0.0;
      for (final fact in factList) {
        final effectiveConfidence = conflictPenalty == 0.0
            ? fact.confidence
            : fact.confidence * (1 - conflictPenalty);

        if (effectiveConfidence < effectiveLowConfidence()) {
          warnings.add(
            AnalysisEvidenceAdapterWarning(
              code: 'lowConfidence',
              detail: fact.metricId,
            ),
          );
        }

        evidence.add(
          SkillEvidence(
            skillId: fact.skillHint,
            source: EvidenceSource.analyzeV2,
            sourceOutcomeId: OutcomeId(_outcomeIdFor(fact)),
            measurementVersion: measurementVersion,
            measuredAt: fact.capturedAt,
            capturedAt: asOf.toUtc(),
            confidence: effectiveConfidence,
            performance: PerformanceEvidence(
              metricCode: _practiceMetricCodeFor(fact.metricId),
              value: fact.value,
              sampleCount: fact.sampleCount,
            ),
          ),
        );
      }
    }

    // Reader-level warnings (dedup, non-scalar values, etc.).
    for (final w in outcome.warnings) {
      warnings.add(
        AnalysisEvidenceAdapterWarning(code: w.code, detail: w.detail),
      );
    }

    // Unavailable capabilities (A7).
    for (final fact in facts.unavailableFacts) {
      warnings.add(
        AnalysisEvidenceAdapterWarning(
          code: 'capabilityUnavailable:${fact.capability.name}',
          detail: fact.skillHint,
        ),
      );
    }

    return AnalysisEvidenceAdapterResult(
      evidence: List<SkillEvidence>.unmodifiable(evidence),
      warnings: List<AnalysisEvidenceAdapterWarning>.unmodifiable(warnings),
      signalQualityAdvisory: advisory,
    );
  }

  /// The threshold under which a [SkillEvidence] confidence still counts
  /// as "low" for warning purposes. The actual safety net is the
  /// `singleEvidenceInfluenceCap` (default `0.25`); this constant is only
  /// the visibility hint the adapter surfaces in its warning stream.
  static double effectiveLowConfidence() => 0.4;
}

String _outcomeIdFor(AnalysisMetricFact fact) =>
    'analysis:${fact.metricId}:${fact.skillHint}';

String _practiceMetricCodeFor(String analysisMetricId) =>
    'analysis.${_stripVersion(analysisMetricId)}';

String _stripVersion(String id) {
  final dot = id.lastIndexOf('.v');
  if (dot > 0 && int.tryParse(id.substring(dot + 2)) != null) {
    return id.substring(0, dot);
  }
  return id;
}
