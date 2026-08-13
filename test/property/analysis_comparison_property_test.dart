import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric_catalog.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_provenance.dart';
import 'package:strumsight/features/audio_analysis/domain/comparison/analysis_comparison.dart';
import 'package:strumsight/features/audio_analysis/domain/comparison/metric_metadata.dart';
import 'package:strumsight/features/audio_analysis/domain/signal_quality_report.dart';
import 'package:strumsight/features/audio_analysis/engine/comparison/compatibility_evaluator.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  final metricIds = AnalysisMetricId.known.toList(growable: false);

  test('descriptive metrics never resolve to improved or regressed, for any '
      'randomized before/after pair', () {
    final rng = math.Random(seed);
    for (var trial = 0; trial < 500; trial++) {
      final id = metricIds[rng.nextInt(metricIds.length)];
      final metadata = MetricMetadataCatalog.forId(id)!;
      if (metadata.direction != MetricDirection.descriptive) continue;

      final before = (rng.nextDouble() - 0.5) * 200;
      final after = (rng.nextDouble() - 0.5) * 200;
      final direction = CompatibilityEvaluator.resolveDirection(
        metadata,
        before: before,
        after: after,
      );

      expect(
        direction,
        isNot(MetricComparisonDirection.improved),
        reason: 'seed=$seed trial=$trial id=$id before=$before after=$after',
      );
      expect(
        direction,
        isNot(MetricComparisonDirection.regressed),
        reason: 'seed=$seed trial=$trial id=$id before=$before after=$after',
      );
    }
  });

  test('below the meaningful-delta threshold, direction is always unchanged '
      '(lowerIsBetter/higherIsBetter metrics)', () {
    final rng = math.Random(seed + 1);
    for (var trial = 0; trial < 500; trial++) {
      final id = metricIds[rng.nextInt(metricIds.length)];
      final metadata = MetricMetadataCatalog.forId(id)!;
      if (metadata.direction == MetricDirection.descriptive ||
          metadata.direction == MetricDirection.targetRange) {
        continue;
      }

      final before = rng.nextDouble() * 100;
      final threshold = metadata.minimumMeaningfulDelta;
      final noise = threshold <= 0
          ? 0.0
          : (rng.nextDouble() * threshold * 0.99);
      final after = before + (rng.nextBool() ? noise : -noise);

      final direction = CompatibilityEvaluator.resolveDirection(
        metadata,
        before: before,
        after: after,
      );

      expect(
        direction,
        MetricComparisonDirection.unchanged,
        reason:
            'seed=$seed trial=$trial id=$id before=$before after=$after '
            'threshold=$threshold',
      );
    }
  });

  test(
    'at or beyond the meaningful-delta threshold, lowerIsBetter/higherIsBetter '
    'metrics always resolve to improved or regressed, never unchanged',
    () {
      final rng = math.Random(seed + 2);
      for (var trial = 0; trial < 500; trial++) {
        final id = metricIds[rng.nextInt(metricIds.length)];
        final metadata = MetricMetadataCatalog.forId(id)!;
        if (metadata.direction == MetricDirection.descriptive ||
            metadata.direction == MetricDirection.targetRange) {
          continue;
        }

        final before = rng.nextDouble() * 100;
        final threshold = metadata.minimumMeaningfulDelta;
        final excess = threshold + 1 + rng.nextDouble() * 50;
        final after = before + (rng.nextBool() ? excess : -excess);

        final direction = CompatibilityEvaluator.resolveDirection(
          metadata,
          before: before,
          after: after,
        );

        expect(
          direction == MetricComparisonDirection.improved ||
              direction == MetricComparisonDirection.regressed,
          isTrue,
          reason:
              'seed=$seed trial=$trial id=$id before=$before after=$after '
              'threshold=$threshold direction=$direction',
        );
      }
    },
  );

  test('noise-floor compatibility is exactly the 10 dB inclusive boundary, for '
      'any randomized quality pair with everything else held constant', () {
    final rng = math.Random(seed + 3);
    final provenance = AnalysisProvenance(
      appVersion: '1.0',
      analyzerVersion: '1.0',
      pipelineVersion: '1.0',
      stageVersions: <String, String>{},
      dspConfigHash: 'hash',
      modelManifestIds: <String>[],
      inputFingerprint: 'fp',
      platform: 'test',
      featureFlagSnapshot: <String, bool>{},
    );
    for (var trial = 0; trial < 500; trial++) {
      final beforeNoiseFloor = -60 + rng.nextDouble() * 40;
      final deltaDbfs = rng.nextDouble() * 30;
      final afterNoiseFloor = beforeNoiseFloor - deltaDbfs;

      final reason = CompatibilityEvaluator.evaluateCompatibility(
        before: _metric(AnalysisMetricId.timingTargetMeanAbsoluteError, 40),
        after: _metric(AnalysisMetricId.timingTargetMeanAbsoluteError, 30),
        beforeQuality: _quality(noiseFloorDbfs: beforeNoiseFloor),
        afterQuality: _quality(noiseFloorDbfs: afterNoiseFloor),
        beforeProvenance: provenance,
        afterProvenance: provenance,
      );

      final expectIncompatible =
          deltaDbfs > noiseFloorCompatibilityThresholdDbfs;
      expect(
        reason == ComparisonInconclusiveReason.inputQualityDiverged,
        expectIncompatible,
        reason: 'seed=$seed trial=$trial deltaDbfs=$deltaDbfs',
      );
    }
  });

  test(
    'compare() confidence and sampleCount never exceed either input session',
    () {
      final rng = math.Random(seed + 4);
      final provenance = AnalysisProvenance(
        appVersion: '1.0',
        analyzerVersion: '1.0',
        pipelineVersion: '1.0',
        stageVersions: <String, String>{},
        dspConfigHash: 'hash',
        modelManifestIds: <String>[],
        inputFingerprint: 'fp',
        platform: 'test',
        featureFlagSnapshot: <String, bool>{},
      );
      for (var trial = 0; trial < 300; trial++) {
        final id = metricIds[rng.nextInt(metricIds.length)];
        final beforeConfidence = rng.nextDouble();
        final afterConfidence = rng.nextDouble();
        final beforeSampleCount = rng.nextInt(200);
        final afterSampleCount = rng.nextInt(200);

        final comparison = CompatibilityEvaluator.compare(
          before: _metricWith(
            id,
            10 + rng.nextDouble() * 10,
            confidence: beforeConfidence,
            sampleCount: beforeSampleCount,
          ),
          after: _metricWith(
            id,
            10 + rng.nextDouble() * 10,
            confidence: afterConfidence,
            sampleCount: afterSampleCount,
          ),
          beforeQuality: _quality(),
          afterQuality: _quality(),
          beforeProvenance: provenance,
          afterProvenance: provenance,
        );

        expect(
          comparison.confidence,
          lessThanOrEqualTo(math.min(beforeConfidence, afterConfidence)),
          reason: 'seed=$seed trial=$trial id=$id',
        );
        expect(
          comparison.sampleCount,
          lessThanOrEqualTo(math.min(beforeSampleCount, afterSampleCount)),
          reason: 'seed=$seed trial=$trial id=$id',
        );
      }
    },
  );
}

AnalysisMetricResult _metric(String id, double valueMilliseconds) =>
    _metricWith(id, valueMilliseconds);

AnalysisMetricResult _metricWith(
  String id,
  double valueMilliseconds, {
  double confidence = 0.9,
  int sampleCount = 20,
}) => AnalysisMetricResult(
  id: id,
  version: 1,
  status: CapabilityStatus.available,
  confidence: confidence,
  unit: 'ms',
  sampleCount: sampleCount,
  evidence: const <String>[],
  value: DurationMetricValue(
    Duration(microseconds: (valueMilliseconds * 1000).round()),
  ),
);

SignalQualityReport _quality({
  double overall = 0.9,
  double noiseFloorDbfs = -50,
  double clippedSampleRatio = 0,
}) => SignalQualityReport(
  overall: overall,
  peakDbfs: -3,
  rmsDbfs: -18,
  noiseFloorDbfs: noiseFloorDbfs,
  clippedSampleRatio: clippedSampleRatio,
  silentRatio: 0,
  tonalness: 0.5,
);
