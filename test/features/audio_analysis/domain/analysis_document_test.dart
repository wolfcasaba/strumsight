import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  group('AnalysisDocument validation matrix', () {
    test(
      'rejects a negative timeline duration and accepts zero and one microsecond',
      () {
        expect(
          () => AnalysisTimeline(duration: const Duration(microseconds: -1)),
          throwsArgumentError,
        );
        expect(
          _document(timeline: AnalysisTimeline(duration: Duration.zero)),
          isA<AnalysisDocument>(),
        );
        expect(
          _document(
            timeline: AnalysisTimeline(
              duration: const Duration(microseconds: 1),
            ),
          ),
          isA<AnalysisDocument>(),
        );
      },
    );

    test(
      'accepts inclusive confidence boundaries and rejects computed values outside them',
      () {
        expect(_capability(0.0), isA<CapabilityReport>());
        expect(_capability(0.5), isA<CapabilityReport>());
        expect(_capability(1.0), isA<CapabilityReport>());
        // Generated with `python3 -c 'print(repr(-1e-9), repr(1.0 + 1e-9))'`.
        expect(() => _capability(-1e-9), throwsArgumentError);
        expect(() => _capability(1.000000001), throwsArgumentError);
      },
    );

    test('allows zero or one metric but rejects duplicate metric IDs', () {
      expect(
        _document(metrics: const <AnalysisMetricResult>[]),
        isA<AnalysisDocument>(),
      );
      final metric = _metric();
      expect(
        _document(metrics: <AnalysisMetricResult>[metric]),
        isA<AnalysisDocument>(),
      );
      expect(
        () => _document(metrics: <AnalysisMetricResult>[metric, metric]),
        throwsArgumentError,
      );
    });

    test(
      'rejects end before start and accepts zero-length and forward segments',
      () {
        expect(
          () => ChordSegment(
            start: const Duration(microseconds: 2),
            end: const Duration(microseconds: 1),
            confidence: 0.5,
            label: 'C',
          ),
          throwsArgumentError,
        );
        expect(
          ChordSegment(
            start: Duration.zero,
            end: Duration.zero,
            confidence: 0.5,
            label: 'C',
          ),
          isA<ChordSegment>(),
        );
        expect(
          ChordSegment(
            start: Duration.zero,
            end: const Duration(microseconds: 1),
            confidence: 0.5,
            label: 'C',
          ),
          isA<ChordSegment>(),
        );
      },
    );

    test('takes immutable snapshots of document lists', () {
      final metrics = <AnalysisMetricResult>[_metric()];
      final document = _document(metrics: metrics);
      metrics.add(_otherMetric());
      expect(document.metrics, hasLength(1));
      expect(
        () => document.metrics.add(_otherMetric()),
        throwsUnsupportedError,
      );
    });

    test(
      'keeps direct domain fields privacy-safe and cancellation persistable',
      () {
        final input = _input();
        expect(input.originalAudioRetained, isFalse);
        expect(
          _document(
            completion: AnalysisCompletion(
              status: AnalysisCompletionStatus.cancelled,
            ),
          ),
          isA<AnalysisDocument>(),
        );
        expect(
          _document(
            completion: AnalysisCompletion(
              status: AnalysisCompletionStatus.failed,
              failureCode: 'pipeline.internal',
            ),
          ),
          isA<AnalysisDocument>(),
        );
      },
    );
  });
}

CapabilityReport _capability(double confidence) => CapabilityReport(
  capability: AnalysisCapability.onsetTimeline,
  status: CapabilityStatus.available,
  confidence: confidence,
);

AnalysisMetricResult _metric() => AnalysisMetricResult(
  id: AnalysisMetricId.timingMeanAbsoluteError,
  version: 1,
  status: CapabilityStatus.available,
  confidence: 0.5,
  value: DurationMetricValue(const Duration(microseconds: 1)),
  unit: 'microseconds',
  sampleCount: 1,
  evidence: const <String>['onset-1'],
);

AnalysisMetricResult _otherMetric() => AnalysisMetricResult(
  id: AnalysisMetricId.rhythmRushDragBias,
  version: 1,
  status: CapabilityStatus.available,
  confidence: 0.5,
  value: ScalarMetricValue(0.1),
  unit: 'ratio',
  sampleCount: 1,
  evidence: const <String>['onset-1'],
);

AnalysisInputSummary _input() => AnalysisInputSummary(
  source: AnalysisInputSource.microphone,
  duration: const Duration(seconds: 1),
  sampleRate: 44100,
  channelCount: 1,
  fingerprint: 'fingerprint',
);

AnalysisDocument _document({
  AnalysisTimeline? timeline,
  List<AnalysisMetricResult>? metrics,
  AnalysisCompletion? completion,
}) => AnalysisDocument(
  id: 'analysis-1',
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime.utc(2026),
  mode: AnalysisMode.freePlay,
  input: _input(),
  provenance: AnalysisProvenance(
    appVersion: '1.0.0',
    analyzerVersion: '1',
    pipelineVersion: '1',
    stageVersions: const <String, String>{'signal': '1'},
    dspConfigHash: 'hash',
    modelManifestIds: const <String>[],
    inputFingerprint: 'fingerprint',
    platform: 'android',
    featureFlagSnapshot: const <String, bool>{},
  ),
  signalQuality: SignalQualityReport(
    overall: 0.5,
    peakDbfs: -1,
    rmsDbfs: -12,
    noiseFloorDbfs: -48,
    clippedSampleRatio: 0,
    silentRatio: 0,
    tonalness: 0.5,
  ),
  capabilities: <CapabilityReport>[_capability(0.5)],
  timeline: timeline ?? AnalysisTimeline(duration: const Duration(seconds: 1)),
  metrics: metrics ?? <AnalysisMetricResult>[_metric()],
  hotspots: const <AnalysisHotspot>[],
  insights: const <AnalysisInsight>[],
  warnings: const <AnalysisWarning>[],
  completion:
      completion ??
      AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);
