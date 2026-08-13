import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  test('issues one versioned skill evidence per document id', () {
    final adapter = ProgressEvidenceAdapter();
    final document = _document();
    final first = adapter.credit(document);
    final second = adapter.credit(document);
    expect(first, isNotNull);
    expect(first!.sourceVersion, 'analysis-document.v1');
    expect(second, isNull);
  });
}

AnalysisDocument _document() => AnalysisDocument(
  id: 'document',
  schemaVersion: 1,
  createdAt: DateTime.utc(2026),
  mode: AnalysisMode.practiceTarget,
  input: AnalysisInputSummary(
    source: AnalysisInputSource.microphone,
    duration: const Duration(seconds: 1),
    sampleRate: 44100,
    channelCount: 1,
    fingerprint: 'fp',
  ),
  provenance: AnalysisProvenance(
    appVersion: '1',
    analyzerVersion: '1',
    pipelineVersion: '1',
    stageVersions: const <String, String>{},
    dspConfigHash: 'hash',
    modelManifestIds: const <String>[],
    inputFingerprint: 'fp',
    platform: 'test',
    featureFlagSnapshot: const <String, bool>{},
  ),
  signalQuality: SignalQualityReport(
    overall: .9,
    peakDbfs: -2,
    rmsDbfs: -12,
    noiseFloorDbfs: -50,
    clippedSampleRatio: 0,
    silentRatio: 0,
    tonalness: .5,
  ),
  capabilities: const <CapabilityReport>[],
  timeline: AnalysisTimeline(duration: const Duration(seconds: 1)),
  metrics: <AnalysisMetricResult>[
    AnalysisMetricResult(
      id: AnalysisMetricId.timingMeanAbsoluteError,
      version: 1,
      status: CapabilityStatus.available,
      confidence: .8,
      value: ScalarMetricValue(1),
      unit: 'ms',
      sampleCount: 1,
      evidence: const <String>[],
    ),
  ],
  hotspots: const <AnalysisHotspot>[],
  insights: const <AnalysisInsight>[],
  warnings: const <AnalysisWarning>[],
  completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);
