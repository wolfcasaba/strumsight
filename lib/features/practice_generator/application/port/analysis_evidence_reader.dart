/// Audio Analysis V2 → Practice Generator evidence reader (E07-R25, SDD
/// Ch8 Kör 25, brief §4).
///
/// Mirrors the R07/R08 legacy-snapshot reader pair
/// (`skill_snapshot_reader.dart` + `legacy_progress_evidence_adapter.dart`):
/// a caller hands the reader one or more [AnalysisEvidenceView]s, the reader
/// returns the [AnalysisEvidenceReaderResult], and the adapter
/// (`data/adapter/analysis_evidence_adapter.dart`) maps the result to
/// [SkillEvidence] (or to a setup-style advisory, never to a degraded
/// learner score).
///
/// Strict boundary: the reader itself never constructs [SkillEvidence] —
/// that is the adapter's job. The reader does not read a wall clock; all
/// `capturedAt` values are caller-supplied. The reader never infers a skill
/// id from a metric id, a document id, or any other content field (SDD Ch8
/// §5.1) — every fact carries a caller-attested `skillHint`.
///
/// Accepted types from `lib/features/audio_analysis/public.dart`:
/// [AnalysisCapability], [CapabilityUnavailableReason], [AnalysisMetricResult],
/// [SignalQualityReport]. The reader never references any other analysis-
/// internal type (A8).
library;

import 'package:strumsight/features/audio_analysis/public.dart'
    show
        AnalysisCapability,
        AnalysisMetricResult,
        AnalysisMetricValue,
        CapabilityUnavailableReason,
        CategoryMetricValue,
        DistributionMetricValue,
        DurationMetricValue,
        PercentageMetricValue,
        ScalarMetricValue,
        ScoreMetricValue,
        SignalQualityReport,
        TimeSeriesMetricValue;

/// One view a caller may hand to the reader — exactly one shape per
/// analysis-side publication type.
sealed class AnalysisEvidenceView {
  const AnalysisEvidenceView();
}

/// One published analysis metric result with its caller-attested target skill
/// and reference instant.
final class AnalysisEvidenceMetricView extends AnalysisEvidenceView {
  AnalysisEvidenceMetricView({
    required this.metric,
    required String skillHint,
    required DateTime capturedAt,
  }) : skillHint = _requireSkillHint(skillHint, 'skillHint'),
       capturedAt = capturedAt.toUtc(),
       metric = metric;

  final AnalysisMetricResult metric;
  final String skillHint;
  final DateTime capturedAt;
}

/// The recording/clip-level [SignalQualityReport]. NEVER used by the reader
/// to compute a performance value; the adapter uses it for the A4
/// setup-vs-skill split.
final class AnalysisEvidenceSignalQualityView extends AnalysisEvidenceView {
  const AnalysisEvidenceSignalQualityView(this.report);
  final SignalQualityReport report;
}

/// A capability the analysis pipeline explicitly could not compute. It must
/// surface as a [AnalysisEvidenceWarning], never as a degraded [SkillEvidence]
/// (A7, ADR 0262).
final class AnalysisEvidenceUnavailableView extends AnalysisEvidenceView {
  AnalysisEvidenceUnavailableView({
    required this.capability,
    required this.reason,
    required String skillHint,
  }) : capability = capability,
       reason = reason,
       skillHint = _requireSkillHint(skillHint, 'skillHint');

  final AnalysisCapability capability;
  final CapabilityUnavailableReason reason;
  final String skillHint;
}

/// One scalar-derefable analysis metric, prepared for the adapter.
///
/// [skillHint] is the caller-attested target skill id; it is the adapter's
/// job to turn it into [SkillEvidence.skillId] (SDD Ch8 §5.1). A non-scalar
/// metric value (`DistributionMetricValue`, `TimeSeriesMetricValue`) never
/// produces a fact: those are aggregated, count-shaped series, not the
/// single skill-decisive measurement the Practice Generator reasons over.
final class AnalysisMetricFact {
  const AnalysisMetricFact({
    required this.skillHint,
    required this.metricId,
    required this.value,
    required this.confidence,
    required this.sampleCount,
    required this.measurementVersion,
    required this.capturedAt,
  });

  final String skillHint;
  final String metricId;
  final double value;
  final double confidence;
  final int sampleCount;
  final int measurementVersion;
  final DateTime capturedAt;
}

/// An unavailable-capability fact: the adapter must surface this as a
/// non-skill warning, never as a 0/0.0 placeholder or as a `null`-valued
/// evidence record (A7).
final class AnalysisUnavailableFact {
  const AnalysisUnavailableFact({
    required this.capability,
    required this.reason,
    required this.skillHint,
  });

  final AnalysisCapability capability;
  final CapabilityUnavailableReason reason;
  final String skillHint;
}

/// Reader result: the adapter consumes this verbatim — no further analysis
/// imports beyond the typed `signalQuality` value.
final class AnalysisEvidenceReaderResult {
  const AnalysisEvidenceReaderResult({
    required this.metricFacts,
    required this.signalQuality,
    required this.unavailableFacts,
  });

  final List<AnalysisMetricFact> metricFacts;
  final SignalQualityReport? signalQuality;
  final List<AnalysisUnavailableFact> unavailableFacts;
}

/// A stable, log-safe reason the adapter could not turn a view into a
/// skill record (or an unavailable-capability fact). The adapter must use
/// [code] for log keys / structured fields and limit [detail] to a
/// non-sensitive identifier (e.g. a `skillHint` or a stable capability id).
final class AnalysisEvidenceReaderWarning {
  const AnalysisEvidenceReaderWarning({
    required this.code,
    required this.detail,
  });

  final String code;
  final String detail;

  @override
  String toString() => 'AnalysisEvidenceReaderWarning($code: $detail)';

  @override
  bool operator ==(Object other) =>
      other is AnalysisEvidenceReaderWarning &&
      code == other.code &&
      detail == other.detail;

  @override
  int get hashCode => Object.hash(code, detail);
}

/// What the adapter did with the reader's output (plus any diagnostics).
final class AnalysisEvidenceReaderOutcome {
  const AnalysisEvidenceReaderOutcome({
    required this.facts,
    required this.warnings,
  });

  final AnalysisEvidenceReaderResult facts;
  final List<AnalysisEvidenceReaderWarning> warnings;
}

/// Port boundary for the Analysis → Practice evidence pipeline. The
/// adapter owns the [SkillEvidence] mapping; the reader owns the
/// caller-attested view projection and the bounded dedup of repeated
/// `(metricId, capturedAt, skillHint)` triples.
abstract interface class AnalysisEvidenceReader {
  AnalysisEvidenceReaderOutcome read(List<AnalysisEvidenceView> views);
}

/// The default, dependency-free reader implementation — pure projection of
/// the views above into facts (A8). Duplicate `(metricId, capturedAt,
/// skillHint)` triples resolve to one fact and one duplicate warning; the
/// adapter sees a stable, idempotent input regardless of caller replay
/// order (SDD Ch8 §5.5).
final class DefaultAnalysisEvidenceReader implements AnalysisEvidenceReader {
  const DefaultAnalysisEvidenceReader();

  @override
  AnalysisEvidenceReaderOutcome read(List<AnalysisEvidenceView> views) {
    final metrics = <AnalysisMetricFact>[];
    SignalQualityReport? signalQuality;
    final unavailable = <AnalysisUnavailableFact>[];
    final warnings = <AnalysisEvidenceReaderWarning>[];
    final seenMetricKeys = <String>{};

    for (final view in views) {
      switch (view) {
        case AnalysisEvidenceMetricView(
          :final metric,
          :final skillHint,
          :final capturedAt,
        ):
          final value = _scalarValue(metric.value);
          if (value == null) {
            warnings.add(
              AnalysisEvidenceReaderWarning(
                code: 'nonScalarMetricValue',
                detail: metric.id,
              ),
            );
            continue;
          }
          final key = '${metric.id}|${capturedAt.toIso8601String()}|$skillHint';
          if (!seenMetricKeys.add(key)) {
            warnings.add(
              AnalysisEvidenceReaderWarning(
                code: 'duplicateMetricView',
                detail: metric.id,
              ),
            );
            continue;
          }
          metrics.add(
            AnalysisMetricFact(
              skillHint: skillHint,
              metricId: metric.id,
              value: value,
              confidence: metric.confidence,
              sampleCount: metric.sampleCount,
              measurementVersion: metric.version,
              capturedAt: capturedAt,
            ),
          );
        case AnalysisEvidenceSignalQualityView(:final report):
          // Last write wins — there is exactly one clip-level report per
          // session, and an adapter maps the FINAL snapshot to a setup
          // advisory.
          signalQuality = report;
        case AnalysisEvidenceUnavailableView(
          :final capability,
          :final reason,
          :final skillHint,
        ):
          unavailable.add(
            AnalysisUnavailableFact(
              capability: capability,
              reason: reason,
              skillHint: skillHint,
            ),
          );
      }
    }

    return AnalysisEvidenceReaderOutcome(
      facts: AnalysisEvidenceReaderResult(
        metricFacts: List<AnalysisMetricFact>.unmodifiable(metrics),
        signalQuality: signalQuality,
        unavailableFacts: List<AnalysisUnavailableFact>.unmodifiable(
          unavailable,
        ),
      ),
      warnings: List<AnalysisEvidenceReaderWarning>.unmodifiable(warnings),
    );
  }
}

double? _scalarValue(AnalysisMetricValue? value) => switch (value) {
  ScalarMetricValue(:final value) => value,
  PercentageMetricValue(:final value) => value,
  ScoreMetricValue(:final value) => value / 100,
  DurationMetricValue() => null,
  CategoryMetricValue() => null,
  DistributionMetricValue() => null,
  TimeSeriesMetricValue() => null,
  null => null,
};

String _requireSkillHint(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return value;
}
