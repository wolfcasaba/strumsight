import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/lifecycle/audio_lifecycle_guard.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_coordinator.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/data/capture/analysis_recorder.dart';
import 'package:strumsight/features/audio_analysis/data/capture/recording_run.dart';

import '../../../support/fake_audio.dart';

void main() {
  for (final state in const [
    AppLifecycleState.resumed,
    AppLifecycleState.inactive,
  ]) {
    test('$state keeps recording active', () async {
      final rig = _RecorderLifecycleRig();
      addTearDown(rig.dispose);
      await rig.start();

      rig.lifecycle.emit(state);
      await Future<void>.delayed(Duration.zero);

      expect(rig.recorder.isRecording, isTrue);
      expect(rig.coordinator.activeOwner, AudioOwner.analyzeRecorder);
    });
  }

  for (final state in const [
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.detached,
  ]) {
    test('$state cancels recording and releases the mic', () async {
      final rig = _RecorderLifecycleRig();
      addTearDown(rig.dispose);
      await rig.start();

      rig.lifecycle.emit(state);
      await Future<void>.delayed(Duration.zero);

      expect(rig.recorder.isRecording, isFalse);
      expect(rig.recorder.currentRun!.status, RecordingRunStatus.cancelled);
      expect(rig.coordinator.activeOwner, isNull);
      expect(rig.capture.stopCalls, 1);
    });
  }

  test('background revocation during mic warm-up stops the capture', () async {
    final startGate = Completer<void>();
    final rig = _RecorderLifecycleRig(startGate: startGate.future);
    addTearDown(rig.dispose);
    final replacementCapture = FakeAudioCapture();
    final replacementMic = fakeMicCapture(
      owner: AudioOwner.live,
      coordinator: rig.coordinator,
      capture: replacementCapture,
    );

    final starting = rig.recorder.start();
    await _waitForStart(rig.capture);
    expect(rig.coordinator.activeOwner, AudioOwner.analyzeRecorder);

    rig.lifecycle.emit(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    startGate.complete();
    final startResult = await starting;

    expect(rig.capture.stopCalls, greaterThan(0));
    expect(rig.capture.isRunning, isFalse);
    expect(rig.coordinator.activeOwner, isNull);
    expect(rig.recorder.isRecording, isFalse);
    expect(startResult, isA<Failure<RecordingRun>>());

    rig.capture.emit(const [0.25]);
    expect(rig.recorder.samples, isEmpty);

    expect(await replacementMic.start((_) {}), isA<Success<int>>());
    expect(replacementCapture.isRunning, isTrue);
    await replacementMic.stop();
  });
}

Future<void> _waitForStart(FakeAudioCapture capture) async {
  while (capture.startCalls == 0) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _RecorderLifecycleRig {
  _RecorderLifecycleRig({Future<void>? startGate})
    : coordinator = AudioSessionCoordinator(),
      lifecycle = FakeAppLifecycleEvents(),
      capture = FakeAudioCapture(startGate: startGate) {
    guard = AudioLifecycleGuard(coordinator: coordinator, events: lifecycle);
    recorder = AnalysisRecorder(
      mic: fakeMicCapture(
        owner: AudioOwner.analyzeRecorder,
        coordinator: coordinator,
        capture: capture,
      ),
    );
  }

  final AudioSessionCoordinator coordinator;
  final FakeAppLifecycleEvents lifecycle;
  final FakeAudioCapture capture;
  late final AudioLifecycleGuard guard;
  late final AnalysisRecorder recorder;

  Future<void> start() async {
    await recorder.start();
  }

  void dispose() {
    guard.dispose();
  }
}
