import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_hotspot.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input_summary.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_insight.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric_catalog.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_provenance.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_timeline.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_warning.dart';
import 'package:strumsight/features/audio_analysis/domain/comparison/analysis_comparison.dart';
import 'package:strumsight/features/audio_analysis/domain/signal_quality_report.dart';
import 'package:strumsight/features/audio_analysis/application/compare_analyses_use_case.dart';

void main() {
  const useCase = CompareAnalysesUseCase();

  test('compares metrics published under the same ID in both sessions', () {
    final before = _document(
      id: 'before',
      metrics: <AnalysisMetricResult>[
        _metric(AnalysisMetricId.timingTargetMeanAbsoluteError, 40),
        _metric(AnalysisMetricId.dynamicsDrift, 0.1),
      ],
    );
    final after = _document(
      id: 'after',
      metrics: <AnalysisMetricResult>[
        _metric(AnalysisMetricId.timingTargetMeanAbsoluteError, 30),
      ],
    );

    final comparison = useCase(before: before, after: after);

    expect(comparison.beforeAnalysisId, 'before');
    expect(comparison.afterAnalysisId, 'after');
    expect(comparison.metrics, hasLength(1));
    expect(
      comparison.metrics.single.metricId,
      AnalysisMetricId.timingTargetMeanAbsoluteError,
    );
    expect(
      comparison.metrics.single.direction,
      MetricComparisonDirection.improved,
    );
  });

  test('a metric present in only one session produces no comparison row', () {
    final before = _document(
      id: 'before',
      metrics: const <AnalysisMetricResult>[],
    );
    final after = _document(
      id: 'after',
      metrics: <AnalysisMetricResult>[
        _metric(AnalysisMetricId.timingTargetMeanAbsoluteError, 30),
      ],
    );

    final comparison = useCase(before: before, after: after);

    expect(comparison.metrics, isEmpty);
  });

  test('source imports neither dio nor http', () {
    final source = File(
      'lib/features/audio_analysis/application/compare_analyses_use_case.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('package:dio')));
    expect(source, isNot(contains('package:http')));
  });
}

AnalysisMetricResult _metric(String id, double valueMilliseconds) =>
    AnalysisMetricResult(
      id: id,
      version: 1,
      status: CapabilityStatus.available,
      confidence: 0.9,
      unit: 'ms',
      sampleCount: 20,
      evidence: const <String>[],
      value: DurationMetricValue(
        Duration(microseconds: (valueMilliseconds * 1000).round()),
      ),
    );

AnalysisDocument _document({
  required String id,
  required List<AnalysisMetricResult> metrics,
}) => AnalysisDocument(
  id: id,
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime(2026, 1, 1),
  mode: AnalysisMode.freePlay,
  input: AnalysisInputSummary(
    source: AnalysisInputSource.microphone,
    duration: const Duration(seconds: 30),
    sampleRate: 44100,
    channelCount: 1,
    fingerprint: 'fp-$id',
  ),
  provenance: AnalysisProvenance(
    appVersion: '1.0',
    analyzerVersion: '1.0',
    pipelineVersion: '1.0',
    stageVersions: const <String, String>{},
    dspConfigHash: 'hash',
    modelManifestIds: const <String>[],
    inputFingerprint: 'fp-$id',
    platform: 'test',
    featureFlagSnapshot: const <String, bool>{},
  ),
  signalQuality: SignalQualityReport(
    overall: 0.9,
    peakDbfs: -3,
    rmsDbfs: -18,
    noiseFloorDbfs: -50,
    clippedSampleRatio: 0,
    silentRatio: 0,
    tonalness: 0.5,
  ),
  capabilities: const <CapabilityReport>[],
  timeline: AnalysisTimeline(duration: const Duration(seconds: 30)),
  metrics: metrics,
  hotspots: const <AnalysisHotspot>[],
  insights: const <AnalysisInsight>[],
  warnings: const <AnalysisWarning>[],
  completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);
