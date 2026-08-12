// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strumsight/features/audio_analysis/public.dart';
import 'package:test/test.dart';

void main() {
  test(
    'cancel releases the active run, closes progress, and preserves saved state',
    () async {
      final run = _CleanupRun();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = AnalysisController(
        analyzeAudio: AnalyzeAudioUseCase(_SingleRunRunner(run)),
        cancelAnalysis: const CancelAnalysisUseCase(),
        practiceCredit: const _NoopCredit(),
      );
      final provider = NotifierProvider<AnalysisController, AnalysisState>(
        () => controller,
      );
      container.read(provider);
      var streamClosed = false;
      run.progress.listen((_) {}, onDone: () => streamClosed = true);

      final analysis = controller.analyze(_document());
      await Future<void>.delayed(Duration.zero);
      await controller.cancel();
      await analysis;
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, isA<AnalysisCancelled>());
      expect(run.disposed, isTrue);
      expect(streamClosed, isTrue);
      expect(run.tempFiles, isEmpty);
    },
  );

  test(
    'a real isolate round-trips the document codec without serialization failure',
    () async {
      final runner = AnalysisIsolateRunner(operation: _echoDocumentJson);
      final result = await runner.start(_document()).result;

      expect(result.completion, AnalysisCompletionStatus.complete);
      expect(result.document?.id, 'isolate-document');
    },
  );
}

String _echoDocumentJson(String documentJson) => documentJson;

final class _SingleRunRunner implements AnalysisRunner {
  _SingleRunRunner(this._run);
  final _CleanupRun _run;

  @override
  AnalysisRunHandle start(AnalysisDocument input) => _run;
}

final class _CleanupRun implements AnalysisRunHandle {
  final progressController =
      StreamController<AnalysisProgressEvent>.broadcast();
  final resultCompleter = Completer<AnalysisRunResult>();
  final tempFiles = <String>['temporary-input.pcm'];
  var disposed = false;

  @override
  String get runId => 'cleanup-run';

  @override
  Stream<AnalysisProgressEvent> get progress => progressController.stream;

  @override
  Future<AnalysisRunResult> get result => resultCompleter.future;

  @override
  Future<void> cancel() async {
    disposed = true;
    tempFiles.clear();
    await progressController.close();
    resultCompleter.complete(
      const AnalysisRunResult(completion: AnalysisCompletionStatus.cancelled),
    );
  }
}

final class _NoopCredit implements AnalysisPracticeCreditRecorder {
  const _NoopCredit();

  @override
  void record(AnalysisDocument document) {}
}

AnalysisDocument _document() => AnalysisDocument(
  id: 'isolate-document',
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime.utc(2026),
  mode: AnalysisMode.practiceTarget,
  input: AnalysisInputSummary(
    source: AnalysisInputSource.microphone,
    duration: const Duration(seconds: 1),
    sampleRate: 48000,
    channelCount: 1,
    fingerprint: 'isolate',
  ),
  provenance: AnalysisProvenance(
    appVersion: 'test',
    analyzerVersion: 'test',
    pipelineVersion: 'test',
    stageVersions: const <String, String>{},
    dspConfigHash: 'test',
    modelManifestIds: const <String>[],
    inputFingerprint: 'isolate',
    platform: 'test',
    featureFlagSnapshot: const <String, bool>{},
  ),
  signalQuality: SignalQualityReport(
    overall: .9,
    peakDbfs: -3,
    rmsDbfs: -20,
    noiseFloorDbfs: -60,
    clippedSampleRatio: 0,
    silentRatio: 0,
    tonalness: .9,
  ),
  capabilities: const <CapabilityReport>[],
  timeline: AnalysisTimeline(duration: const Duration(seconds: 1)),
  metrics: const <AnalysisMetricResult>[],
  hotspots: const <AnalysisHotspot>[],
  insights: const <AnalysisInsight>[],
  warnings: const <AnalysisWarning>[],
  completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);
