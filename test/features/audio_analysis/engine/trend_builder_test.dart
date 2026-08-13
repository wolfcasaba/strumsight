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
import 'package:strumsight/features/audio_analysis/domain/comparison/analysis_trend.dart';
import 'package:strumsight/features/audio_analysis/domain/signal_quality_report.dart';
import 'package:strumsight/features/audio_analysis/engine/comparison/trend_builder.dart';

void main() {
  group('TrendBuilder — minimum session count (2/3/4)', () {
    test('2 compatible sessions -> unavailable', () {
      final trend = TrendBuilder.build(
        metricId: AnalysisMetricId.timingTargetMeanAbsoluteError,
        sessions: _sessions(<double>[40, 38]),
      );
      expect(trend.versionGroups, hasLength(1));
      expect(trend.versionGroups.single.availability, TrendAvailability.unavailable);
    });

    test('exactly 3 compatible sessions -> available (inclusive)', () {
      final trend = TrendBuilder.build(
        metricId: AnalysisMetricId.timingTargetMeanAbsoluteError,
        sessions: _sessions(<double>[40, 38, 36]),
      );
      expect(trend.versionGroups.single.availability, TrendAvailability.available);
    });

    test('4 compatible sessions -> available', () {
      final trend = TrendBuilder.build(
        metricId: AnalysisMetricId.timingTargetMeanAbsoluteError,
        sessions: _sessions(<double>[40, 38, 36, 34]),
      );
      expect(trend.versionGroups.single.availability, TrendAvailability.available);
    });
  });

  group('TrendBuilder — outlier exclusion', () {
    test('an outlier stays visible but is excluded from the trend line', () {
      // Five sessions, one far outside the others.
      final trend = TrendBuilder.build(
        metricId: AnalysisMetricId.timingTargetMeanAbsoluteError,
        sessions: _sessions(<double>[40, 41, 39, 40, 400]),
      );
      final group = trend.versionGroups.single;
      expect(group.points, hasLength(5));
      expect(group.points.where((p) => p.excluded), hasLength(1));
      expect(group.points.last.excluded, isTrue);
      expect(group.includedPoints, hasLength(4));
    });

    test('MAD threshold triple — 2.99x / 3.0x / 3.01x are exclusive above 3.0x', () {
      // median=40, MAD computed from [40,40,40,40,x]; construct x so the
      // deviation is exactly at the 2.99/3.0/3.01 * MAD boundary using a
      // fixed base MAD of 2 (values 38,40,40,40,42 -> median 40, MAD 0... )
      // Use a base set with a clean, non-zero MAD instead.
      final base = <double>[36, 38, 40, 42, 44]; // median 40, MAD 2
      double atMultiple(double multiple) => 40 + (multiple * 2);

      final justUnder = TrendBuilder.build(
        metricId: AnalysisMetricId.timingTargetMeanAbsoluteError,
        sessions: _sessions(<double>[...base.take(4), atMultiple(2.99)]),
      ).versionGroups.single;
      final exactly = TrendBuilder.build(
        metricId: AnalysisMetricId.timingTargetMeanAbsoluteError,
        sessions: _sessions(<double>[...base.take(4), atMultiple(3.0)]),
      ).versionGroups.single;
      final justOver = TrendBuilder.build(
        metricId: AnalysisMetricId.timingTargetMeanAbsoluteError,
        sessions: _sessions(<double>[...base.take(4), atMultiple(3.01)]),
      ).versionGroups.single;

      expect(justUnder.points.last.excluded, isFalse);
      expect(exactly.points.last.excluded, isFalse, reason: '3.0x MAD is still in (inclusive)');
      expect(justOver.points.last.excluded, isTrue);
    });
  });

  group('TrendBuilder — version grouping', () {
    test('sessions publishing the same metric version share one trend group', () {
      final documentA = _session(id: 's1', createdAt: DateTime(2026, 1, 1), value: 40);
      final documentB = _session(id: 's2', createdAt: DateTime(2026, 1, 2), value: 30);
      final trend = TrendBuilder.build(
        metricId: AnalysisMetricId.timingTargetMeanAbsoluteError,
        sessions: <AnalysisDocument>[documentA, documentB],
      );
      expect(trend.versionGroups, hasLength(1));
      expect(trend.versionGroups.single.metricVersion, 1);
    });
  });

  group('TrendBuilder — no extrapolation (source + last-point checks)', () {
    test('source contains no predict/forecast/extrapolate symbol', () {
      final source = File(
        'lib/features/audio_analysis/engine/comparison/trend_builder.dart',
      ).readAsStringSync();
      expect(source.toLowerCase(), isNot(contains('predict')));
      expect(source.toLowerCase(), isNot(contains('forecast')));
      expect(source.toLowerCase(), isNot(contains('extrapolat')));
    });

    test('the last trend point is never later than the last session', () {
      final sessions = _sessions(<double>[40, 38, 36, 34]);
      final trend = TrendBuilder.build(
        metricId: AnalysisMetricId.timingTargetMeanAbsoluteError,
        sessions: sessions,
      );
      final lastSessionDate = sessions
          .map((s) => s.createdAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final lastPointDate = trend.versionGroups.single.points.last.timestamp;
      expect(lastPointDate.isAfter(lastSessionDate), isFalse);
    });
  });

  group('TrendBuilder — no network', () {
    test('source imports neither dio nor http', () {
      final source = File(
        'lib/features/audio_analysis/engine/comparison/trend_builder.dart',
      ).readAsStringSync();
      expect(source, isNot(contains("'dio'")));
      expect(source, isNot(contains('package:dio')));
      expect(source, isNot(contains('package:http')));
    });
  });
}

List<AnalysisDocument> _sessions(List<double> values) => <AnalysisDocument>[
  for (final (index, value) in values.indexed)
    _session(
      id: 'session-$index',
      createdAt: DateTime(2026, 1, index + 1),
      value: value,
    ),
];

AnalysisDocument _session({
  required String id,
  required DateTime createdAt,
  required double value,
  int version = 1,
}) => AnalysisDocument(
  id: id,
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: createdAt,
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
  metrics: <AnalysisMetricResult>[
    AnalysisMetricResult(
      id: AnalysisMetricId.timingTargetMeanAbsoluteError,
      version: version,
      status: CapabilityStatus.available,
      confidence: 0.9,
      unit: 'ms',
      sampleCount: 20,
      evidence: const <String>[],
      value: DurationMetricValue(
        Duration(microseconds: (value * 1000).round()),
      ),
    ),
  ],
  hotspots: const <AnalysisHotspot>[],
  insights: const <AnalysisInsight>[],
  warnings: const <AnalysisWarning>[],
  completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);
