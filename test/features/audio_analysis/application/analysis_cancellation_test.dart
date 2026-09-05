// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

      final analysis = controller.analyze(_document(), audio: _audio());
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
      final result = await runner.start(_request()).result;

      expect(result.completion, AnalysisCompletionStatus.complete);
      expect(result.document?.id, 'isolate-document');
    },
  );

  test('a completed run releases the raw-PCM request (F4: no reachable audio '
      'after the run finishes)', () async {
    final runner = AnalysisIsolateRunner(operation: _echoDocumentJson);
    final handle = runner.start(_request());

    await handle.result;

    expect(debugAnalysisRunHandleHoldsRequest(handle), isFalse);
  });

  test('a cancelled run releases the raw-PCM request (F4: no reachable audio '
      'after cancel)', () async {
    final isolateSpawned = Completer<void>();
    final allowAssignment = Completer<void>();
    final runner = AnalysisIsolateRunner(
      operation: _echoDocumentJson,
      isolateSpawner: (replyTo, documentJson, audio, target, operation) async {
        final isolate = await spawnAnalysisIsolate(
          replyTo,
          documentJson,
          audio,
          target,
          operation,
        );
        isolateSpawned.complete();
        await allowAssignment.future;
        return isolate;
      },
    );

    final handle = runner.start(_request());
    await isolateSpawned.future;
    await handle.cancel();
    allowAssignment.complete();
    await handle.result;

    expect(debugAnalysisRunHandleHoldsRequest(handle), isFalse);
  });

  test(
    'cancellation during spawn kills the later-assigned isolate before it finishes work',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'analysis-isolate-cancellation-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final marker = File('${directory.path}/completed');
      final isolateSpawned = Completer<void>();
      final allowAssignment = Completer<void>();
      final runner = AnalysisIsolateRunner(
        operation: _writeCompletionMarkerAfterDelay,
        isolateSpawner:
            (replyTo, documentJson, audio, target, operation) async {
              final isolate = await spawnAnalysisIsolate(
                replyTo,
                documentJson,
                audio,
                target,
                operation,
              );
              isolateSpawned.complete();
              await allowAssignment.future;
              return isolate;
            },
      );

      final run = runner.start(_request(document: _document(id: marker.path)));
      await isolateSpawned.future;
      await run.cancel();
      allowAssignment.complete();
      await run.result;
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(marker.existsSync(), isFalse);
    },
  );
}

String _echoDocumentJson(
  String documentJson,
  ValidatedPcmAnalysisInput audio,
  AnalysisTarget? target,
  void Function(AnalysisProgressEvent event) reportProgress,
) => documentJson;

Future<String> _writeCompletionMarkerAfterDelay(
  String documentJson,
  ValidatedPcmAnalysisInput audio,
  AnalysisTarget? target,
  void Function(AnalysisProgressEvent event) reportProgress,
) async {
  final json = jsonDecode(documentJson) as Map<String, Object?>;
  await Future<void>.delayed(const Duration(milliseconds: 150));
  await File(json['id']! as String).writeAsString('completed');
  return documentJson;
}

final class _SingleRunRunner implements AnalysisRunner {
  _SingleRunRunner(this._run);
  final _CleanupRun _run;

  @override
  AnalysisRunHandle start(AnalysisRunRequest input) => _run;
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

AnalysisRunRequest _request({AnalysisDocument? document}) => AnalysisRunRequest(
  seed: document ?? _document(),
  audio: ValidatedPcmAnalysisInput(
    input: PcmAnalysisInput(
      samples: const <double>[0, 0, 0],
      sampleRate: 48000,
      channelCount: 1,
      source: AnalysisInputSource.microphone,
    ),
  ),
);

AnalysisDocument _document({String id = 'isolate-document'}) =>
    AnalysisDocument(
      id: id,
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

/// A VALÓDI hangbemenet a hívótól jön (2026-09-05): az `AnalyzeAudioUseCase`
/// korábban maga gyártott egy üres minta-listát, és így a felvételi folyamat
/// csendet elemzett volna. A paraméter azért kötelező, hogy ez fordítási
/// hibaként jöjjön elő, ne néma viselkedésként.
ValidatedPcmAnalysisInput _audio() => ValidatedPcmAnalysisInput(
  input: PcmAnalysisInput(
    samples: List<double>.filled(4800, 0.1),
    sampleRate: 48000,
    channelCount: 1,
    source: AnalysisInputSource.microphone,
  ),
);
