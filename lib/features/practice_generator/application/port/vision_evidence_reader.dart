/// Vision → Practice Generator evidence reader (E07-R25, brief §4, §5.7).
///
/// Same shape as [AnalysisEvidenceReader], but narrower: the only Vision
/// types this port references come from the deliberate, raw-media-free
/// `lib/features/vision/domain/evidence/public.dart` boundary (ADR 0319,
/// ADR 0193, brief §0.0.1 / §5.7). The reader never imports
/// `lib/features/vision/public.dart`, never a landmark, never a frame, never
/// a coordinate. The adapter consumes the typed result; a missing capability
/// surfaces as a warning and a `notObservable` observation produces no fact.
///
/// Vision is graceful when absent: if no [VisionEvidenceObservationView] is
/// supplied (vision flag OFF, capability missing, no observation fused yet),
/// the reader returns an empty result. The adapter's `SkillEvidence` list
/// is then empty by construction (A2, A7) — never an exception, never a
/// `null`, never a fabricated zero.
library;

import 'package:strumsight/features/vision/domain/evidence/public.dart'
    show ObservationState, VisionEvidence;

/// One already-fused Vision observation wrapped with the caller-attested
/// target skill and the reference instant the evidence entered the practice
/// pipeline. The reader never derives a skill from the observation's metric
/// or any other content field (SDD Ch8 §5.1).
final class VisionEvidenceObservationView {
  VisionEvidenceObservationView({
    required this.observation,
    required String skillHint,
    required DateTime capturedAt,
  }) : skillHint = _requireSkillHint(skillHint, 'skillHint'),
       capturedAt = capturedAt.toUtc();

  final VisionEvidence observation;
  final String skillHint;
  final DateTime capturedAt;
}

/// A derived, raw-free Vision fact — the adapter maps each to
/// [SkillEvidence] or skips it. Each fact carries the `metricKey` (the
/// stable EvidenceMetric.key string, e.g. `posture:shoulderAsymmetry`) and
/// the [ObservationState] the fusion window reported, so the adapter can
/// enforce the §5.5 / A5 allowlist without re-reading the metric catalog.
final class VisionEvidenceFact {
  const VisionEvidenceFact({
    required this.skillHint,
    required this.metricKey,
    required this.metricFamily,
    required this.value,
    required this.confidence,
    required this.state,
    required this.measurementId,
    required this.capturedAt,
  });

  final String skillHint;
  final String metricKey;
  final String metricFamily;
  final double value;
  final double confidence;
  final ObservationState state;
  final String measurementId;
  final DateTime capturedAt;
}

/// Stable, log-safe reason the adapter could not turn a view into a fact.
/// [code] is a stable identifier (e.g. `'notObservable'`, `'duplicate'`,
/// `'missingValue'`); [detail] is the observation's stable vision-evidence
/// id only — never raw content.
final class VisionEvidenceReaderWarning {
  const VisionEvidenceReaderWarning({required this.code, required this.detail});

  final String code;
  final String detail;

  @override
  String toString() => 'VisionEvidenceReaderWarning($code: $detail)';

  @override
  bool operator ==(Object other) =>
      other is VisionEvidenceReaderWarning &&
      code == other.code &&
      detail == other.detail;

  @override
  int get hashCode => Object.hash(code, detail);
}

final class VisionEvidenceReaderOutcome {
  const VisionEvidenceReaderOutcome({
    required this.facts,
    required this.warnings,
  });

  final List<VisionEvidenceFact> facts;
  final List<VisionEvidenceReaderWarning> warnings;
}

/// Port boundary for Vision → Practice evidence. The adapter owns the
/// [SkillEvidence] mapping and the §5.5 / A5 allowlist; the reader owns the
/// projection of `notObservable`/missing-value observations into warnings
/// and the dedup of repeated `measurementId`s.
abstract interface class VisionEvidenceReader {
  VisionEvidenceReaderOutcome read(List<VisionEvidenceObservationView> views);
}

/// The default, dependency-free reader implementation. A `notObservable`
/// observation (or one whose `value` is `null`, as the VisionEvidence
/// invariant requires) produces a `notObservable` warning and no fact; an
/// empty input list yields an empty outcome (A2, A7).
final class DefaultVisionEvidenceReader implements VisionEvidenceReader {
  const DefaultVisionEvidenceReader();

  @override
  VisionEvidenceReaderOutcome read(List<VisionEvidenceObservationView> views) {
    final facts = <VisionEvidenceFact>[];
    final warnings = <VisionEvidenceReaderWarning>[];
    final seenIds = <String>{};

    for (final view in views) {
      final obs = view.observation;
      if (obs.observationState == ObservationState.notObservable) {
        warnings.add(
          VisionEvidenceReaderWarning(code: 'notObservable', detail: obs.id),
        );
        continue;
      }
      final value = obs.value;
      if (value == null) {
        warnings.add(
          VisionEvidenceReaderWarning(code: 'missingValue', detail: obs.id),
        );
        continue;
      }
      if (!seenIds.add(obs.id)) {
        warnings.add(
          VisionEvidenceReaderWarning(code: 'duplicate', detail: obs.id),
        );
        continue;
      }
      facts.add(
        VisionEvidenceFact(
          skillHint: view.skillHint,
          metricKey: obs.metric.key,
          metricFamily: obs.metric.family.name,
          value: value,
          confidence: obs.confidence,
          state: obs.observationState,
          measurementId: obs.id,
          capturedAt: view.capturedAt,
        ),
      );
    }

    return VisionEvidenceReaderOutcome(
      facts: List<VisionEvidenceFact>.unmodifiable(facts),
      warnings: List<VisionEvidenceReaderWarning>.unmodifiable(warnings),
    );
  }
}

String _requireSkillHint(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return value;
}
