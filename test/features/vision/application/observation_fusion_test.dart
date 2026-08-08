import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/application/observation_fusion.dart';
import 'package:strumsight/features/vision/domain/evidence/evidence_provenance.dart';
import 'package:strumsight/features/vision/domain/evidence/vision_evidence.dart';
import 'package:strumsight/features/vision/domain/evidence/vision_observation.dart';
import 'package:strumsight/features/vision/domain/geometry/geometry_confidence.dart';
import 'package:strumsight/features/vision/domain/metrics/metric_definition.dart';
import 'package:strumsight/features/vision/domain/metrics/metric_observation.dart';
import 'package:strumsight/features/vision/domain/quality/vision_frame_quality.dart';
import 'package:strumsight/features/vision/domain/sync/sync_quality.dart';

final EvidenceMetric _metric = EvidenceMetric.fretting(
  FrettingMetricId.wristDeviationProxy,
);
const FusionThresholds _thresholds = FusionThresholds(
  version: 'fusion-test-v1',
  minimumObservationCount: 2,
  minimumVisibleDuration: Duration(milliseconds: 100),
  maximumGap: Duration(milliseconds: 100),
  inferredConfidencePenalty: 0.8,
);

void main() {
  test('produces a deterministic, JSON-stable evidence snapshot', () {
    final first = _fusion()..addAll(_continuousObservations());
    final second = _fusion()..addAll(_continuousObservations());

    final firstEvidence = first.fuse(metric: _metric, windowEndUs: 500000);
    final secondEvidence = second.fuse(metric: _metric, windowEndUs: 500000);

    final expected = File(
      'test/fixtures/vision/evidence/observed_wrist_deviation.json',
    ).readAsStringSync().trim();
    expect(jsonEncode(firstEvidence.toJson()), expected);
    expect(jsonEncode(secondEvidence.toJson()), expected);
    expect(firstEvidence.id, secondEvidence.id);
    expect(firstEvidence.observationState, ObservationState.observed);
  });

  test('rejects a window below the minimum observation count', () {
    final fusion = _fusion()..add(_observation(timestampUs: 100000));

    final evidence = fusion.fuse(metric: _metric, windowEndUs: 500000);

    expect(evidence.observationState, ObservationState.notObservable);
    expect(evidence.value, isNull);
  });

  test('accepts the observation-count boundary and the value above it', () {
    for (final timestamps in <List<int>>[
      <int>[100000, 200000],
      <int>[100000, 200000, 300000],
    ]) {
      final fusion = _fusion()
        ..addAll(
          timestamps.map(
            (timestampUs) => _observation(timestampUs: timestampUs),
          ),
        );
      expect(
        fusion.fuse(metric: _metric, windowEndUs: 500000).observationState,
        ObservationState.observed,
      );
    }
  });

  test(
    'rejects sufficient observations below the minimum visible duration',
    () {
      final fusion = _fusion()
        ..addAll(<VisionObservation>[
          _observation(timestampUs: 400000),
          _observation(timestampUs: 400010),
          _observation(timestampUs: 400020),
        ]);

      final evidence = fusion.fuse(metric: _metric, windowEndUs: 500000);

      expect(evidence.observationState, ObservationState.notObservable);
      expect(evidence.value, isNull);
    },
  );

  test('short bridgeable gaps are inferred and reduce confidence', () {
    final continuous = _fusion()..addAll(_continuousObservations());
    final gapped = _fusion()
      ..addAll(<VisionObservation>[
        _observation(timestampUs: 100000),
        _observation(timestampUs: 200000),
        _observation(timestampUs: 280000, wasInterpolated: true),
        _observation(timestampUs: 380000),
      ]);

    final observed = continuous.fuse(metric: _metric, windowEndUs: 500000);
    final inferred = gapped.fuse(metric: _metric, windowEndUs: 500000);

    expect(inferred.observationState, ObservationState.inferred);
    expect(inferred.confidence, lessThan(observed.confidence));
  });

  test('unbridgeable gaps are not observable', () {
    final fusion = _fusion()
      ..addAll(<VisionObservation>[
        _observation(timestampUs: 100000),
        _observation(timestampUs: 200000),
        _observation(timestampUs: 400000),
      ]);

    expect(
      fusion.fuse(metric: _metric, windowEndUs: 500000).observationState,
      ObservationState.notObservable,
    );
  });

  test('is idempotent for an identical metric window', () {
    final fusion = _fusion()..addAll(_continuousObservations());

    final first = fusion.fuse(metric: _metric, windowEndUs: 500000);
    final second = fusion.fuse(metric: _metric, windowEndUs: 500000);

    expect(second, same(first));
    expect(fusion.emittedEvidence, hasLength(1));
  });

  test(
    'bounds raw observations and cached evidence through a ten-minute session',
    () {
      final fusion = _fusion();
      var largestRawObservationCount = 0;
      for (
        var timestampUs = 0;
        timestampUs <= const Duration(minutes: 10).inMicroseconds;
        timestampUs += const Duration(milliseconds: 50).inMicroseconds
      ) {
        fusion.add(_observation(timestampUs: timestampUs));
        if (timestampUs > 0 &&
            timestampUs % _metric.window.inMicroseconds == 0) {
          fusion.fuse(metric: _metric, windowEndUs: timestampUs);
          largestRawObservationCount =
              largestRawObservationCount < fusion.retainedObservationCount
              ? fusion.retainedObservationCount
              : largestRawObservationCount;
        }
      }

      expect(fusion.retainedObservationCount, lessThanOrEqualTo(11));
      expect(largestRawObservationCount, lessThanOrEqualTo(11));
      expect(
        fusion.emittedEvidence,
        hasLength(_thresholds.maximumRetainedEvidence),
      );
    },
  );

  test('bounds raw observations when a metric is never fused', () {
    final fusion = _fusion();
    for (
      var timestampUs = 0;
      timestampUs <= const Duration(minutes: 10).inMicroseconds;
      timestampUs += const Duration(milliseconds: 50).inMicroseconds
    ) {
      fusion.add(_observation(timestampUs: timestampUs));
    }

    expect(fusion.retainedObservationCount, lessThanOrEqualTo(13));
  });

  test('current metric catalog never produces experimental evidence', () {
    for (final catalogMetric in EvidenceMetric.currentCatalog) {
      final fusion = _fusion()
        ..addAll(_continuousObservations(metric: catalogMetric));
      final evidence = fusion.fuse(
        metric: catalogMetric,
        windowEndUs: catalogMetric.window.inMicroseconds,
      );
      expect(evidence.observationState, isNot(ObservationState.experimental));
    }
  });
}

ObservationFusion _fusion() => ObservationFusion(thresholds: _thresholds);

List<VisionObservation> _continuousObservations({EvidenceMetric? metric}) =>
    <VisionObservation>[
      _observation(timestampUs: 100000, metric: metric ?? _metric),
      _observation(timestampUs: 200000, metric: metric ?? _metric),
      _observation(timestampUs: 300000, metric: metric ?? _metric),
      _observation(timestampUs: 400000, metric: metric ?? _metric),
    ];

VisionObservation _observation({
  required int timestampUs,
  EvidenceMetric? metric,
  bool wasInterpolated = false,
}) => VisionObservation(
  timestampUs: timestampUs,
  metric: metric ?? _metric,
  modelVersion: 'model-test-v1',
  metricObservation: MetricObservation.observable(value: 0.25, confidence: 0.9),
  frameQuality: _quality(),
  geometrySource: GeometrySource.manual,
  geometryConfidence: GeometryConfidence(confidence: 1, drift: 0),
  syncQuality: SyncQuality.excellent,
  wasInterpolated: wasInterpolated,
);

VisionFrameQuality _quality() => VisionFrameQuality(
  thresholdsVersion: 'quality-test-v1',
  framing: VisionMetricState.good,
  lighting: VisionLighting.good,
  blur: VisionMetricState.good,
  stability: VisionMetricState.good,
  roiCoverage: VisionMetricState.good,
  overall: VisionMetricState.good,
  meanLuminance: 100,
  highlightClippingRatio: 0,
  shadowClippingRatio: 0,
  sharpness: 20,
  cameraMotion: 0,
  roiCoverageRatio: 1,
);
