import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/domain/evidence/evidence_provenance.dart';
import 'package:strumsight/features/vision/domain/evidence/vision_evidence.dart';
import 'package:strumsight/features/vision/domain/evidence/vision_observation.dart';
import 'package:strumsight/features/vision/domain/feedback/insight_code.dart';
import 'package:strumsight/features/vision/domain/integration/vision_claim_guard.dart';
import 'package:strumsight/features/vision/domain/metrics/metric_definition.dart';
import 'package:strumsight/features/vision/domain/sync/sync_quality.dart';

void main() {
  const guard = VisionClaimGuard();
  const claim = InsightCode.frettingStable;

  group('evidence and confidence matrix', () {
    for (final row
        in <
          ({
            String name,
            VisionEvidence? evidence,
            double confidence,
            bool allowed,
          })
        >[
          (
            name: 'blocks missing evidence below threshold',
            evidence: null,
            confidence: 0.69,
            allowed: false,
          ),
          (
            name: 'blocks missing evidence at threshold',
            evidence: null,
            confidence: 0.70,
            allowed: false,
          ),
          (
            name: 'blocks missing evidence above threshold',
            evidence: null,
            confidence: 0.71,
            allowed: false,
          ),
          (
            name: 'blocks evidence below threshold',
            evidence: _evidence(),
            confidence: 0.69,
            allowed: false,
          ),
          (
            name: 'allows evidence at threshold',
            evidence: _evidence(),
            confidence: 0.70,
            allowed: true,
          ),
          (
            name: 'allows evidence above threshold',
            evidence: _evidence(),
            confidence: 0.71,
            allowed: true,
          ),
        ]) {
      test(row.name, () {
        final result = guard.evaluate(
          claim: claim,
          evidence: row.evidence,
          confidence: row.confidence,
        );

        expect(result.isAllowed, row.allowed);
        expect(
          result.code,
          row.allowed ? claim : InsightCode.setupNotObservable,
        );
      });
    }
  });

  group('negative-direction confidence threshold', () {
    const negativeClaim = InsightCode.postureFocus;

    for (final row in <({String name, double confidence, bool allowed})>[
      (
        name: 'blocks evidence below the negative threshold',
        confidence: 0.84,
        allowed: false,
      ),
      (
        name: 'allows evidence at the negative threshold',
        confidence: 0.85,
        allowed: true,
      ),
      (
        name: 'allows evidence above the negative threshold',
        confidence: 0.86,
        allowed: true,
      ),
    ]) {
      test(row.name, () {
        final result = guard.evaluate(
          claim: negativeClaim,
          evidence: _evidence(confidence: row.confidence),
          confidence: row.confidence,
        );

        expect(result.isAllowed, row.allowed);
        expect(
          result.code,
          row.allowed ? negativeClaim : InsightCode.setupNotObservable,
        );
      });
    }
  });

  test('returns the same not-observable fallback for repeated denials', () {
    final first = guard.evaluate(claim: claim, evidence: null, confidence: 0.9);
    final second = guard.evaluate(
      claim: claim,
      evidence: null,
      confidence: 0.9,
    );

    expect(first.code, InsightCode.setupNotObservable);
    expect(second.code, first.code);
  });

  test(
    'blocks not-observable or low-confidence evidence despite a stated confidence',
    () {
      for (final evidence in <VisionEvidence>[
        _evidence(state: ObservationState.notObservable),
        _evidence(confidence: 0.69),
      ]) {
        final result = guard.evaluate(
          claim: claim,
          evidence: evidence,
          confidence: 0.9,
        );

        expect(result.code, InsightCode.setupNotObservable);
      }
    },
  );
}

VisionEvidence _evidence({
  double confidence = 0.9,
  ObservationState state = ObservationState.observed,
}) {
  final metric = EvidenceMetric.fretting(FrettingMetricId.wristDeviationProxy);
  return VisionEvidence(
    id: 'evidence-1',
    metric: metric,
    value: state == ObservationState.notObservable ? null : 0.5,
    confidence: confidence,
    observationState: state,
    provenance: EvidenceProvenance(
      metricId: metric.id,
      window: EvidenceWindow(startUs: 0, endUs: 1),
      modelVersion: 'test-model',
      geometrySource: GeometrySource.tracked,
      syncQuality: SyncQuality.excellent,
      thresholdsVersion: 'test-thresholds',
      qualityThresholdsVersion: 'test-quality-thresholds',
    ),
  );
}
