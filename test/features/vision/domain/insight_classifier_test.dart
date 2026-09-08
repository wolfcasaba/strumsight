// E09-R28a: the evidence-to-candidate seam. R28b plugs a landmark-driven
// classifier into this interface; until then the default must be provably
// unable to invent a technique verdict.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/domain/evidence/evidence_provenance.dart';
import 'package:strumsight/features/vision/domain/evidence/vision_evidence.dart';
import 'package:strumsight/features/vision/domain/evidence/vision_observation.dart';
import 'package:strumsight/features/vision/domain/feedback/insight_classifier.dart';
import 'package:strumsight/features/vision/domain/feedback/insight_code.dart';
import 'package:strumsight/features/vision/domain/metrics/metric_definition.dart';
import 'package:strumsight/features/vision/domain/sync/sync_quality.dart';

VisionEvidence _evidence({
  required ObservationState state,
  double confidence = 1,
  String id = 'evidence-1',
}) {
  final metric = EvidenceMetric.fretting(FrettingMetricId.handToNeckDistance);
  return VisionEvidence(
    id: id,
    metric: metric,
    value: state == ObservationState.notObservable ? null : 0.4,
    confidence: confidence,
    observationState: state,
    provenance: EvidenceProvenance(
      metricId: metric.id,
      window: EvidenceWindow(startUs: 0, endUs: 500000),
      modelVersion: 'deferred',
      geometrySource: GeometrySource.manual,
      syncQuality: SyncQuality.poor,
      thresholdsVersion: 'classifier-test-v1',
      qualityThresholdsVersion: 'quality-test-v1',
    ),
  );
}

VisionInsightInput _input(List<VisionEvidence> evidence) => VisionInsightInput(
  evidence: evidence,
  practiceId: 'vision-session',
  capabilityLevel: 'leftHandFocus',
);

void main() {
  group('SetupOnlyInsightClassifier', () {
    const classifier = SetupOnlyInsightClassifier();

    test('proposes the setup code for not-observable evidence', () {
      final candidates = classifier.classify(
        _input(<VisionEvidence>[
          _evidence(state: ObservationState.notObservable),
        ]),
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.code, InsightCode.setupNotObservable);
      expect(candidates.single.practiceId, 'vision-session');
      expect(candidates.single.capabilityLevel, 'leftHandFocus');
    });

    test('proposes nothing for observed evidence', () {
      final candidates = classifier.classify(
        _input(<VisionEvidence>[_evidence(state: ObservationState.observed)]),
      );

      // Fail-closed: without a landmark model no technique judgement can be
      // earned, so a measurable-looking number must not become one.
      expect(candidates, isEmpty);
    });

    test('proposes nothing for inferred or experimental evidence', () {
      expect(
        classifier.classify(
          _input(<VisionEvidence>[
            _evidence(state: ObservationState.inferred),
            _evidence(state: ObservationState.experimental, id: 'evidence-2'),
          ]),
        ),
        isEmpty,
      );
    });

    test('never proposes a technique code for any observation state', () {
      for (final state in ObservationState.values) {
        final candidates = classifier.classify(
          _input(<VisionEvidence>[_evidence(state: state)]),
        );
        for (final candidate in candidates) {
          expect(candidate.code, InsightCode.setupNotObservable);
        }
      }
    });

    test('keeps the input evidence list immutable', () {
      final input = _input(<VisionEvidence>[
        _evidence(state: ObservationState.notObservable),
      ]);

      expect(
        () => input.evidence.add(_evidence(state: ObservationState.observed)),
        throwsUnsupportedError,
      );
    });
  });
}
