/// Vision → Practice Generator evidence adapter (E07-R25, brief §4, §5.5,
/// §5.7, §6/A2/A5).
///
/// Reads caller-supplied [VisionEvidenceObservationView]s through the
/// [VisionEvidenceReader] port, then turns the reader result into
/// [SkillEvidence] (`EvidenceSource.vision`). The adapter owns the
/// §5.5 / A5 allowlist of metric keys; metrics outside the allowlist are
/// recorded as warnings and never become [SkillEvidence]. The adapter also
/// enforces the [ObservationState] policy: only `observed` and `inferred`
/// states are allowed to contribute a [SkillEvidence.performance] value;
/// `experimental` is held to a stricter confidence ceiling so it cannot
/// drive a focus on its own.
///
/// The adapter never imports `lib/features/vision/public.dart`. The only
/// Vision types it can see are the narrow
/// `lib/features/vision/domain/evidence/public.dart` surface (A8, ADR 0319,
/// brief §5.7).
///
/// A2 (vision OFF / capability missing) is enforced structurally: when the
/// input list is empty, the result's [SkillEvidence] list is empty and no
/// exception, `null`, or fabricated zero is produced.
library;

import '../../application/port/vision_evidence_reader.dart';
import '../../domain/id/planner_ids.dart';
import '../../domain/model/skill_evidence.dart';

/// Stable, log-safe reason the adapter could not turn a vision fact into a
/// `SkillEvidence`. [code] is the log key; [detail] is a non-sensitive
/// identifier (an observation's stable vision-evidence id or a metric key).
final class VisionEvidenceAdapterWarning {
  const VisionEvidenceAdapterWarning({
    required this.code,
    required this.detail,
  });

  final String code;
  final String detail;

  @override
  String toString() => 'VisionEvidenceAdapterWarning($code: $detail)';

  @override
  bool operator ==(Object other) =>
      other is VisionEvidenceAdapterWarning &&
      code == other.code &&
      detail == other.detail;

  @override
  int get hashCode => Object.hash(code, detail);
}

/// What the adapter emits for one call to [VisionEvidenceAdapter.adapt].
/// A graceful empty result is the documented shape of A2 — never an
/// exception, never a `null` evidence list, never a fabricated zero.
final class VisionEvidenceAdapterResult {
  const VisionEvidenceAdapterResult({
    required this.evidence,
    required this.warnings,
  });

  final List<SkillEvidence> evidence;
  final List<VisionEvidenceAdapterWarning> warnings;

  @override
  bool operator ==(Object other) =>
      other is VisionEvidenceAdapterResult &&
      _listEq(evidence, other.evidence) &&
      _listEq(warnings, other.warnings);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(evidence), Object.hashAll(warnings));
}

bool _listEq<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

/// Maps Vision-side observations into [SkillEvidence] gated by the §5.5
/// allowlist. Pure: same input → same output, no wall clock.
final class VisionEvidenceAdapter {
  VisionEvidenceAdapter({
    required this.reader,
    required this.measurementVersion,
    required this.allowedMetricKeys,
    required this.experimentalConfidenceCeiling,
  }) : assert(measurementVersion >= 1, 'measurementVersion must be >= 1'),
       assert(
         allowedMetricKeys.isNotEmpty,
         'allowedMetricKeys must name at least one proxy; an empty list '
         'collapses Vision to A5 non-contributor',
       ),
       assert(
         experimentalConfidenceCeiling >= 0 &&
             experimentalConfidenceCeiling <= 1,
         'experimentalConfidenceCeiling must be in [0, 1]',
       );

  /// The Vision reader port. The default reader is dependency-free and
  /// only touches the narrow public contract (A8).
  final VisionEvidenceReader reader;

  /// `SkillEvidence.measurementVersion` for every record produced.
  final int measurementVersion;

  /// The §5.5 / A5 allowlist. Only facts whose `metricKey` is in this set
  /// become [SkillEvidence]; everything else is recorded as a warning.
  final Set<String> allowedMetricKeys;

  /// The maximum confidence the adapter may emit for an
  /// `experimental` observation. `experimental` is never given a focus-
  /// driving vote; it is admitted only as a hint, never as a skill
  /// judgement.
  final double experimentalConfidenceCeiling;

  VisionEvidenceAdapterResult adapt(
    List<VisionEvidenceObservationView> views, {
    required DateTime asOf,
  }) {
    final outcome = reader.read(views);
    final facts = outcome.facts;
    final warnings = <VisionEvidenceAdapterWarning>[];

    if (facts.isEmpty) {
      // A2 graceful empty: emit zero evidence and report the reader-level
      // warnings (if any) for diagnostics, but never an exception.
      for (final w in outcome.warnings) {
        warnings.add(
          VisionEvidenceAdapterWarning(code: w.code, detail: w.detail),
        );
      }
      return VisionEvidenceAdapterResult(
        evidence: const <SkillEvidence>[],
        warnings: List<VisionEvidenceAdapterWarning>.unmodifiable(warnings),
      );
    }

    final evidence = <SkillEvidence>[];
    for (final fact in facts) {
      if (!allowedMetricKeys.contains(fact.metricKey)) {
        warnings.add(
          VisionEvidenceAdapterWarning(
            code: 'metricNotAllowed',
            detail: fact.metricKey,
          ),
        );
        continue;
      }

      double effectiveConfidence = fact.confidence;
      if (fact.state == ObservationState.experimental) {
        if (effectiveConfidence > experimentalConfidenceCeiling) {
          effectiveConfidence = experimentalConfidenceCeiling;
        }
      }

      evidence.add(
        SkillEvidence(
          skillId: fact.skillHint,
          source: EvidenceSource.vision,
          sourceOutcomeId: OutcomeId('vision:${fact.measurementId}'),
          measurementVersion: measurementVersion,
          measuredAt: fact.capturedAt,
          capturedAt: asOf.toUtc(),
          confidence: effectiveConfidence,
          performance: PerformanceEvidence(
            metricCode: 'vision.${fact.metricKey}',
            value: fact.value,
            sampleCount: 1,
          ),
        ),
      );
    }

    for (final w in outcome.warnings) {
      warnings.add(
        VisionEvidenceAdapterWarning(code: w.code, detail: w.detail),
      );
    }

    return VisionEvidenceAdapterResult(
      evidence: List<SkillEvidence>.unmodifiable(evidence),
      warnings: List<VisionEvidenceAdapterWarning>.unmodifiable(warnings),
    );
  }
}
