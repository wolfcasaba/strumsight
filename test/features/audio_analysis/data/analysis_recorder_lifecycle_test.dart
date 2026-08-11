import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/lifecycle/audio_lifecycle_guard.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_coordinator.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart';
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
}

final class _RecorderLifecycleRig {
  _RecorderLifecycleRig()
    : coordinator = AudioSessionCoordinator(),
      lifecycle = FakeAppLifecycleEvents(),
      capture = FakeAudioCapture() {
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
