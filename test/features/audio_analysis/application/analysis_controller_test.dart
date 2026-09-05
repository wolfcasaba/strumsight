// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/features/audio_analysis/public.dart';
import 'package:test/test.dart';

void main() {
  group('AnalysisController', () {
    test(
      'publishes a completed document and credits an eventful run once',
      () async {
        final run = _FakeRun('run-1');
        final credit = _FakeCreditRecorder();
        final controller = _controller(run, credit: credit);

        final future = controller.analyze(_document(), audio: _audio());
        run.complete(_result(runId: 'run-1', value: _document()));
        await future;

        expect(controller.state, isA<AnalysisCompleted>());
        expect(credit.calls, 1);
      },
    );

    test('publishes a degraded document without practice credit', () async {
      final run = _FakeRun('run-1');
      final credit = _FakeCreditRecorder();
      final controller = _controller(run, credit: credit);

      final future = controller.analyze(_document(), audio: _audio());
      run.complete(
        _result(
          runId: 'run-1',
          value: _document(),
          completion: AnalysisCompletionStatus.degraded,
        ),
      );
      await future;

      expect(controller.state, isA<AnalysisDegradedCompleted>());
      expect(credit.calls, 0);
    });

    test(
      'maps a fatal stage failure to analysis error without credit',
      () async {
        final run = _FakeRun('run-1');
        final credit = _FakeCreditRecorder();
        final controller = _controller(run, credit: credit);

        final future = controller.analyze(_document(), audio: _audio());
        run.complete(
          _result(
            runId: 'run-1',
            failure: const MlFailure(),
            completion: AnalysisCompletionStatus.failed,
          ),
        );
        await future;

        expect(controller.state, isA<AnalysisError>());
        expect(credit.calls, 0);
      },
    );

    test(
      'does not credit a completed document without a chord or strum',
      () async {
        final run = _FakeRun('run-1');
        final credit = _FakeCreditRecorder();
        final controller = _controller(run, credit: credit);

        final future = controller.analyze(_document(eventful: false), audio: _audio());
        run.complete(
          _result(runId: 'run-1', value: _document(eventful: false)),
        );
        await future;

        expect(controller.state, isA<AnalysisCompleted>());
        expect(credit.calls, 0);
      },
    );

    test(
      'rejects late progress and result from a cancelled previous run',
      () async {
        final first = _FakeRun('run-1');
        final second = _FakeRun('run-2');
        final runner = _QueueRunner(<_FakeRun>[first, second]);
        final controller = _controllerWithRunner(runner);

        final firstFuture = controller.analyze(_document(), audio: _audio());
        await _flush();
        await controller.cancel();
        final secondFuture = controller.analyze(_document(), audio: _audio());
        await _flush();
        first.progressController.add(
          AnalysisPhaseProgressEvent(
            runId: 'run-1',
            phase: AnalysisProgressPhase.preprocessing,
          ),
        );
        first.complete(_result(runId: 'run-1', value: _document()));
        second.complete(_result(runId: 'run-2', value: _document()));
        await Future.wait(<Future<void>>[firstFuture, secondFuture]);

        expect(controller.rejectedLateResults, 2);
        expect(controller.state, isA<AnalysisCompleted>());
      },
    );

    test('starting a new analysis cancels the previously active run', () async {
      final first = _FakeRun('run-1');
      final second = _FakeRun('run-2');
      final controller = _controllerWithRunner(
        _QueueRunner(<_FakeRun>[first, second]),
      );

      final firstFuture = controller.analyze(_document(), audio: _audio());
      await _flush();
      final secondFuture = controller.analyze(_document(), audio: _audio());

      expect(first.disposed, isTrue);
      first.complete(
        _result(runId: 'run-1', completion: AnalysisCompletionStatus.cancelled),
      );
      second.complete(_result(runId: 'run-2', value: _document()));
      await Future.wait(<Future<void>>[firstFuture, secondFuture]);
    });

    test(
      'emits progress inclusively at five events and resets the counter',
      () async {
        final run = _FakeRun('run-1');
        final controller = _controller(run);
        final future = controller.analyze(_document(), audio: _audio());
        await _flush();

        for (var index = 0; index < 4; index++) {
          run.progressController.add(
            AnalysisPhaseProgressEvent(
              runId: 'run-1',
              phase: AnalysisProgressPhase.preprocessing,
            ),
          );
        }
        await _flush();
        expect(
          (controller.state as AnalysisAnalyzing).emittedProgressEvents,
          0,
        );

        run.progressController.add(
          AnalysisPhaseProgressEvent(
            runId: 'run-1',
            phase: AnalysisProgressPhase.preprocessing,
          ),
        );
        await _flush();
        expect(
          (controller.state as AnalysisAnalyzing).emittedProgressEvents,
          1,
        );

        run.progressController.add(
          AnalysisPhaseProgressEvent(
            runId: 'run-1',
            phase: AnalysisProgressPhase.finalizing,
          ),
        );
        await _flush();
        expect(
          (controller.state as AnalysisAnalyzing).emittedProgressEvents,
          1,
        );

        run.complete(_result(runId: 'run-1', value: _document()));
        await future;
      },
    );

    test('reports permission and input errors without starting a run', () {
      final run = _FakeRun('run-1');
      final controller = _controller(run);

      controller.permissionDenied();
      expect(controller.state, isA<AnalysisPermissionDenied>());
      controller.inputError(const ValidationFailure());
      expect(controller.state, isA<AnalysisInputError>());
    });

    for (final lifecycle
        in <({String name, void Function(AnalysisController) leave})>[
          (
            name: 'tab switch',
            leave: (controller) => controller.screenDetached(),
          ),
          (
            name: 'app background',
            leave: (controller) => controller.appBackgrounded(),
          ),
        ]) {
      test('${lifecycle.name} cancels the active run', () async {
        final run = _FakeRun('run-1', completeOnCancel: true);
        final controller = _controller(run);
        final future = controller.analyze(_document(), audio: _audio());
        await _flush();

        lifecycle.leave(controller);
        await future;

        expect(run.disposed, isTrue);
        expect(controller.state, isA<AnalysisCancelled>());
      });
    }

    test(
      'does not import engine code or JSON serialization in the controller',
      () {
        final source = File(
          'lib/features/audio_analysis/application/analysis_controller.dart',
        ).readAsStringSync();

        expect(source, isNot(contains("engine/")));
        expect(source, isNot(contains('jsonEncode')));
        expect(source, isNot(contains('jsonDecode')));
      },
    );
  });
}

AnalysisController _controller(
  _FakeRun run, {
  AnalysisPracticeCreditRecorder? credit,
}) => _controllerWithRunner(_QueueRunner(<_FakeRun>[run]), credit: credit);

AnalysisController _controllerWithRunner(
  AnalysisRunner runner, {
  AnalysisPracticeCreditRecorder? credit,
}) {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final controller = AnalysisController(
    analyzeAudio: AnalyzeAudioUseCase(runner),
    cancelAnalysis: CancelAnalysisUseCase(),
    practiceCredit: credit ?? _FakeCreditRecorder(),
  );
  final provider = NotifierProvider<AnalysisController, AnalysisState>(
    () => controller,
  );
  container.read(provider);
  return controller;
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _QueueRunner implements AnalysisRunner {
  _QueueRunner(this._runs);

  final List<_FakeRun> _runs;

  @override
  AnalysisRunHandle start(AnalysisRunRequest input) => _runs.removeAt(0);
}

final class _FakeRun implements AnalysisRunHandle {
  _FakeRun(this.runId, {this.completeOnCancel = false});

  @override
  final String runId;
  final progressController =
      StreamController<AnalysisProgressEvent>.broadcast();
  final _result = Completer<AnalysisRunResult>();
  final bool completeOnCancel;
  var disposed = false;

  @override
  Stream<AnalysisProgressEvent> get progress => progressController.stream;

  @override
  Future<AnalysisRunResult> get result => _result.future;

  @override
  Future<void> cancel() async {
    disposed = true;
    if (completeOnCancel && !_result.isCompleted) {
      await progressController.close();
      _result.complete(
        const AnalysisRunResult(completion: AnalysisCompletionStatus.cancelled),
      );
    }
  }

  void complete(AnalysisRunResult result) {
    _result.complete(result);
    unawaited(progressController.close());
  }
}

final class _FakeCreditRecorder implements AnalysisPracticeCreditRecorder {
  int calls = 0;

  @override
  void record(AnalysisDocument document) {
    calls++;
  }
}

AnalysisRunResult _result({
  required String runId,
  AnalysisDocument? value,
  AnalysisCompletionStatus completion = AnalysisCompletionStatus.complete,
  AppFailure? failure,
}) => AnalysisRunResult(
  completion: completion,
  document: value,
  failure: failure,
);

AnalysisDocument _document({bool eventful = true}) => AnalysisDocument(
  id: 'test-document',
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime.utc(2026),
  mode: AnalysisMode.practiceTarget,
  input: AnalysisInputSummary(
    source: AnalysisInputSource.microphone,
    duration: const Duration(seconds: 1),
    sampleRate: 48000,
    channelCount: 1,
    fingerprint: 'test',
  ),
  provenance: AnalysisProvenance(
    appVersion: 'test',
    analyzerVersion: 'test',
    pipelineVersion: 'test',
    stageVersions: const <String, String>{},
    dspConfigHash: 'test',
    modelManifestIds: const <String>[],
    inputFingerprint: 'test',
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
  timeline: AnalysisTimeline(
    duration: const Duration(seconds: 1),
    chordSegments: eventful
        ? <ChordSegment>[
            ChordSegment(
              id: 'chord',
              start: Duration.zero,
              end: const Duration(seconds: 1),
              confidence: .9,
              label: 'C',
            ),
          ]
        : const <ChordSegment>[],
  ),
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
