import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_coordinator.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';
import 'package:strumsight/features/audio_analysis/data/capture/analysis_recorder.dart';
import 'package:strumsight/features/audio_analysis/data/capture/recording_run.dart';
import 'package:strumsight/features/audio_analysis/domain/recording_level.dart';

import '../../../support/fake_audio.dart';

void main() {
  group('AnalysisRecorder lease integration', () {
    test('starts when the shared session is free', () async {
      final coordinator = AudioSessionCoordinator();
      final recorder = AnalysisRecorder(
        mic: fakeMicCapture(
          owner: AudioOwner.analyzeRecorder,
          coordinator: coordinator,
        ),
      );

      final run = await _started(recorder);

      expect(run.status, RecordingRunStatus.recording);
      expect(coordinator.activeOwner, AudioOwner.analyzeRecorder);
    });

    test('reports a controlled busy failure without recording', () async {
      final coordinator = AudioSessionCoordinator();
      final holder = fakeMicCapture(
        owner: AudioOwner.live,
        coordinator: coordinator,
      );
      await holder.start((_) {});
      final recorder = AnalysisRecorder(
        mic: fakeMicCapture(
          owner: AudioOwner.analyzeRecorder,
          coordinator: coordinator,
        ),
      );

      final result = await recorder.start();

      expect(result, isA<Failure<RecordingRun>>());
      expect(
        (result as Failure<RecordingRun>).error,
        isA<AudioFailure>().having(
          (failure) => failure.code,
          'failure code',
          FailureCode.audioSessionBusy,
        ),
      );
      expect(recorder.isRecording, isFalse);
      await holder.stop();
    });

    test('keeps denied permission distinct from a capture failure', () async {
      final recorder = AnalysisRecorder(
        mic: fakeMicCapture(
          owner: AudioOwner.analyzeRecorder,
          permissions: FakeMicrophonePermissionGateway(
            state: MicrophonePermissionState.denied,
          ),
        ),
      );

      final result = await recorder.start();

      expect(result, isA<Failure<RecordingRun>>());
      expect((result as Failure<RecordingRun>).error, isA<PermissionFailure>());
      expect(recorder.isRecording, isFalse);
    });

    test('releases the lease after stop', () async {
      final coordinator = AudioSessionCoordinator();
      final recorder = AnalysisRecorder(
        mic: fakeMicCapture(
          owner: AudioOwner.analyzeRecorder,
          coordinator: coordinator,
        ),
      );
      await _started(recorder);

      await recorder.stop();

      expect(coordinator.activeOwner, isNull);
    });

    test('joins overlapping starts without opening a second capture', () async {
      final capture = FakeAudioCapture();
      final recorder = AnalysisRecorder(
        mic: fakeMicCapture(
          owner: AudioOwner.analyzeRecorder,
          capture: capture,
        ),
      );

      final first = recorder.start();
      final second = recorder.start();
      await Future.wait([first, second]);

      expect(capture.startCalls, 1);
      await recorder.stop();
    });
  });

  group('AnalysisRecorder recording integrity', () {
    test('drops chunks from a stopped run after the next run starts', () async {
      final capture = FakeAudioCapture();
      final recorder = AnalysisRecorder(
        mic: fakeMicCapture(
          owner: AudioOwner.analyzeRecorder,
          capture: capture,
        ),
      );
      await _started(recorder);
      capture.emit(const [0.25]);
      await recorder.stop();
      await _started(recorder);

      capture.emitToStart(0, const [0.5]);
      capture.emitToStart(0, const [0.75]);

      expect(recorder.currentRun!.sampleCount, 0);
      expect(recorder.droppedStaleChunks, 2);
      await recorder.stop();
    });

    test('keeps the documented 48 kHz maximum-duration boundary exact', () {
      const sampleRate = 48000;
      final limit = AnalysisRecorder.maximumSampleCount(sampleRate: sampleRate);

      expect(limit - 1, 28799999);
      expect(limit, 28800000);
      expect(limit + 1, 28800001);
    });

    test(
      'stays active below the limit, completes at it, and drops excess',
      () async {
        final capture = FakeAudioCapture(sampleRate: 1);
        final recorder = AnalysisRecorder(
          mic: fakeMicCapture(
            owner: AudioOwner.analyzeRecorder,
            capture: capture,
          ),
          maximumDuration: const Duration(seconds: 2),
        );
        await _started(recorder);

        capture.emit(const [0.1]);
        expect(recorder.currentRun!.status, RecordingRunStatus.recording);
        capture.emit(const [0.2]);

        expect(
          recorder.currentRun!.status,
          RecordingRunStatus.maxDurationReached,
        );
        expect(recorder.currentRun!.sampleCount, 2);
        expect(recorder.samples, const [0.1, 0.2]);
        capture.emit(const [0.3]);
        expect(recorder.samples, const [0.1, 0.2]);
      },
    );

    test('truncates an oversized chunk at the maximum duration', () async {
      final capture = FakeAudioCapture(sampleRate: 1);
      final recorder = AnalysisRecorder(
        mic: fakeMicCapture(
          owner: AudioOwner.analyzeRecorder,
          capture: capture,
        ),
        maximumDuration: const Duration(seconds: 2),
      );
      await _started(recorder);

      capture.emit(const [0.1, 0.2, 0.3]);

      expect(recorder.samples, const [0.1, 0.2]);
      expect(
        recorder.currentRun!.status,
        RecordingRunStatus.maxDurationReached,
      );
    });

    test(
      'emits linear peak and RMS preview work without pipeline stages',
      () async {
        final capture = FakeAudioCapture(sampleRate: 10);
        final recorder = AnalysisRecorder(
          mic: fakeMicCapture(
            owner: AudioOwner.analyzeRecorder,
            capture: capture,
          ),
        );
        final levels = <RecordingLevel>[];
        final subscription = recorder.levels.listen(levels.add);
        addTearDown(subscription.cancel);
        await _started(recorder);
        final samples = CountingSampleBuffer(const [0.5, -0.5, 0.25]);

        capture.emit(samples);
        await Future<void>.delayed(Duration.zero);

        expect(levels, hasLength(1));
        expect(levels.single.peakDbfs, closeTo(-6.0206, 0.0001));
        expect(levels.single.rmsDbfs, closeTo(-7.2699, 0.0001));
        expect(samples.readCount, lessThanOrEqualTo(samples.length * 2));
        await recorder.stop();
      },
    );

    test('uses separate clipping on and off thresholds', () async {
      final capture = FakeAudioCapture(sampleRate: 10);
      final recorder = AnalysisRecorder(
        mic: fakeMicCapture(
          owner: AudioOwner.analyzeRecorder,
          capture: capture,
        ),
      );
      final levels = <RecordingLevel>[];
      final subscription = recorder.levels.listen(levels.add);
      addTearDown(subscription.cancel);
      await _started(recorder);

      for (final dbfs in const [
        -3.5,
        -3.0,
        -2.0,
        -1.0,
        -0.5,
        -1.0,
        -2.0,
        -3.0,
        -3.5,
      ]) {
        capture.emit([_amplitudeForDbfs(dbfs)]);
      }
      await Future<void>.delayed(Duration.zero);

      expect(levels.map((level) => level.isClipping), [
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        false,
        false,
      ]);
      await recorder.stop();
    });
  });
}

Future<RecordingRun> _started(AnalysisRecorder recorder) async {
  final result = await recorder.start();
  expect(result, isA<Success<RecordingRun>>());
  return (result as Success<RecordingRun>).value;
}

double _amplitudeForDbfs(double dbfs) => math.pow(10, dbfs / 20).toDouble();
