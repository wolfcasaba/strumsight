import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  test('redacts document inputs and caps immutable events at fifty', () {
    final snapshot = const TutorAnalysisSnapshotAdapter().fromDocument(
      _document(eventCount: 51),
    );
    final json = jsonEncode(snapshot.toJson());
    expect(snapshot.events, hasLength(50));
    expect(
      () => snapshot.events.add(snapshot.events.first),
      throwsUnsupportedError,
    );
    for (final key in TutorSnapshotRedaction.forbiddenKeys) {
      expect(json, isNot(contains('"$key"')));
    }
    expect(json, isNot(contains('secret.wav')));
  });
}

AnalysisDocument _document({required int eventCount}) => AnalysisDocument(
  id: 'document',
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime.utc(2026),
  mode: AnalysisMode.practiceTarget,
  input: AnalysisInputSummary(
    source: AnalysisInputSource.importedFile,
    duration: const Duration(seconds: 1),
    sampleRate: 44100,
    channelCount: 1,
    fingerprint: 'fingerprint',
    sourceName: 'secret.wav',
  ),
  provenance: AnalysisProvenance(
    appVersion: '1',
    analyzerVersion: '1',
    pipelineVersion: '1',
    stageVersions: const <String, String>{},
    dspConfigHash: 'hash',
    modelManifestIds: const <String>[],
    inputFingerprint: 'fingerprint',
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
  timeline: AnalysisTimeline(
    duration: const Duration(seconds: 1),
    events: <AnalysisEvent>[
      for (var i = 0; i < eventCount; i++)
        OnsetEvent(
          id: 'event-$i',
          time: Duration(microseconds: i),
          confidence: .5,
        ),
    ],
  ),
  metrics: const <AnalysisMetricResult>[],
  hotspots: const <AnalysisHotspot>[],
  insights: const <AnalysisInsight>[],
  warnings: const <AnalysisWarning>[],
  completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);
