import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_coordinator.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/data/capture/analysis_recorder.dart';
import 'package:strumsight/features/audio_analysis/data/capture/recording_run.dart';

import '../../../support/fake_audio.dart';

void main() {
  test('dispose during an in-flight start releases the mic', () async {
    final startGate = Completer<void>();
    final coordinator = AudioSessionCoordinator();
    final capture = FakeAudioCapture(startGate: startGate.future);
    final recorder = AnalysisRecorder(
      mic: fakeMicCapture(
        owner: AudioOwner.analyzeRecorder,
        coordinator: coordinator,
        capture: capture,
      ),
    );

    final starting = recorder.start();
    await _waitForStart(capture);

    // The screen is torn down while the platform still owes us the stream:
    // stop() has no active run to complete, so only dispose() can close the
    // window.
    await recorder.dispose();
    startGate.complete();
    final startResult = await starting;

    expect(startResult, isA<Failure<RecordingRun>>());
    expect(
      (startResult as Failure<RecordingRun>).error.code,
      FailureCode.cancelled,
    );
    expect(recorder.isRecording, isFalse);
    expect(capture.isRunning, isFalse);
    expect(coordinator.activeOwner, isNull);

    // A chunk that was already in flight must not hit the closed level stream.
    capture.emit(const [0.25]);
    expect(recorder.samples, isEmpty);
    expect(recorder.droppedStaleChunks, 1);
  });

  test('dispose stays idempotent after a completed run', () async {
    final coordinator = AudioSessionCoordinator();
    final capture = FakeAudioCapture();
    final recorder = AnalysisRecorder(
      mic: fakeMicCapture(
        owner: AudioOwner.analyzeRecorder,
        coordinator: coordinator,
        capture: capture,
      ),
    );

    expect(await recorder.start(), isA<Success<RecordingRun>>());
    await recorder.dispose();
    await recorder.dispose();

    expect(capture.isRunning, isFalse);
    expect(capture.stopCalls, 1);
    expect(coordinator.activeOwner, isNull);
    expect(recorder.currentRun!.status, RecordingRunStatus.completed);
  });
}

Future<void> _waitForStart(FakeAudioCapture capture) async {
  while (capture.startCalls == 0) {
    await Future<void>.delayed(Duration.zero);
  }
}
