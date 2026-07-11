import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/engine/clip_recorder.dart';
import 'package:music_theory/features/analyze/providers/analyze_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 114 — the round-102 dispose-time cancel only covered a take whose
/// phase was already `recording`. A tab switch DURING the mic-start handshake
/// (Record tapped, `_recorder.start()` still awaiting) slipped past both the
/// dispose gate and `cancelRecording`'s phase guard: the start then landed on
/// the still-alive controller and the mic recorded invisibly behind another
/// tab. The controller now tracks screen attachment and aborts a landing
/// start when the screen has gone.
class _GatedRecorder extends ClipRecorder {
  _GatedRecorder() : super(ensurePermission: () async => true);

  Completer<MicStart> startGate = Completer<MicStart>();
  Completer<List<double>>? stopGate;
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<MicStart> start() {
    startCalls++;
    return startGate.future;
  }

  @override
  Future<List<double>> stop() {
    stopCalls++;
    return stopGate?.future ?? Future.value(const []);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  (ProviderContainer, AnalyzeController, _GatedRecorder) rig() {
    final recorder = _GatedRecorder();
    final container = ProviderContainer(overrides: [
      analyzeControllerProvider
          .overrideWith(() => AnalyzeController(recorder: recorder)),
    ]);
    final controller = container.read(analyzeControllerProvider.notifier);
    return (container, controller, recorder);
  }

  test('screen leaving during the mic handshake aborts the landed take', () async {
    final (container, controller, recorder) = rig();
    addTearDown(container.dispose);
    controller.screenAttached();

    final pending = controller.startRecording();
    controller.screenDetached(); // tab switch while start() is awaiting
    recorder.startGate.complete(MicStart.ok);
    await pending;

    expect(recorder.stopCalls, 1,
        reason: 'the take must be released — a hot mic behind another tab');
    expect(container.read(analyzeControllerProvider).phase, AnalyzePhase.idle);
  });

  test('a denied start landing after the screen left stays quiet', () async {
    final (container, controller, recorder) = rig();
    addTearDown(container.dispose);
    controller.screenAttached();

    final pending = controller.startRecording();
    controller.screenDetached();
    recorder.startGate.complete(MicStart.denied);
    await pending;

    expect(recorder.stopCalls, 0, reason: 'nothing went live — nothing to stop');
    expect(container.read(analyzeControllerProvider).phase, AnalyzePhase.idle,
        reason: 'no error banner may flash for a screen the user already left');
  });

  test('start landing while attached records normally', () async {
    final (container, controller, recorder) = rig();
    addTearDown(container.dispose);
    controller.screenAttached();

    final pending = controller.startRecording();
    recorder.startGate.complete(MicStart.ok);
    await pending;

    expect(container.read(analyzeControllerProvider).phase,
        AnalyzePhase.recording);
    expect(recorder.stopCalls, 0);
  });

  test('returning to the screen re-arms recording after an aborted start',
      () async {
    final (container, controller, recorder) = rig();
    addTearDown(container.dispose);
    controller.screenAttached();

    final first = controller.startRecording();
    controller.screenDetached();
    recorder.startGate.complete(MicStart.ok);
    await first;
    expect(container.read(analyzeControllerProvider).phase, AnalyzePhase.idle);

    // The user comes back and records again — the controller must not have
    // latched itself into a dead state.
    controller.screenAttached();
    recorder.startGate = Completer<MicStart>();
    final second = controller.startRecording();
    recorder.startGate.complete(MicStart.ok);
    await second;
    expect(container.read(analyzeControllerProvider).phase,
        AnalyzePhase.recording);
    expect(recorder.stopCalls, 1, reason: 'only the aborted take was stopped');
  });

  test('cancelRecording leaves a genuinely FINISHED analysis alone', () async {
    // Round 115: the r102 "leaves a finished result alone" test was partly
    // vacuous — it cancelled a fresh idle controller, never a real
    // done-with-result state (r114 devil-advocate NOTE). Build the real one.
    final (container, controller, recorder) = rig();
    addTearDown(container.dispose);
    controller.screenAttached();

    final pending = controller.startRecording();
    recorder.startGate.complete(MicStart.ok);
    await pending;
    await controller.stopAndAnalyze(); // silence in → empty-but-real result

    final done = container.read(analyzeControllerProvider);
    expect(done.phase, AnalyzePhase.done);
    expect(done.result, isNotNull);

    controller.cancelRecording();
    final after = container.read(analyzeControllerProvider);
    expect(after.phase, AnalyzePhase.done,
        reason: 'a finished analysis must survive a late deferred cancel');
    expect(identical(after.result, done.result), isTrue);
  });

  test('cancelRecording firing during the stop-flush of stopAndAnalyze '
      'is a no-op (no double stop, no state clobber)', () async {
    final (container, controller, recorder) = rig();
    addTearDown(container.dispose);
    controller.screenAttached();

    final pending = controller.startRecording();
    recorder.startGate.complete(MicStart.ok);
    await pending;
    expect(container.read(analyzeControllerProvider).phase,
        AnalyzePhase.recording);

    recorder.stopGate = Completer<List<double>>();
    final stopping = controller.stopAndAnalyze();
    // The deferred round-102 cancel could fire exactly here, while stop()'s
    // await is still flushing. It must see a non-recording phase and no-op.
    controller.cancelRecording();
    expect(container.read(analyzeControllerProvider).phase,
        AnalyzePhase.analyzing,
        reason: 'the take is being analyzed — cancel must not reset it');
    expect(recorder.stopCalls, 1, reason: 'no second stop on the mic');

    recorder.stopGate!.complete(List<double>.filled(4096, 0));
    await stopping;
    expect(container.read(analyzeControllerProvider).phase, AnalyzePhase.done);
  });
}
