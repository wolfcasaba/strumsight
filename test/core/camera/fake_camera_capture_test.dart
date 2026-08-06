import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_failure.dart';
import 'package:strumsight/core/camera/camera_frame.dart';
import 'package:strumsight/core/camera/fake_camera_capture.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';

Failure<void> _failure(AppResult<void> result) => result as Failure<void>;

void main() {
  group('FakeCameraCapture lifecycle matrix', () {
    test(
      'start → frame → close delivers a frame then releases the stream',
      () async {
        final capture = FakeCameraCapture(frameBytes: const <int>[9]);
        final delivered = <int>[];
        var streamClosed = false;
        final subscription = capture.frames.listen(
          (frame) => delivered.add(frame.byteAt(0)),
          onDone: () => streamClosed = true,
        );

        expect((await capture.start()).isSuccess, isTrue);
        expect(capture.emitFrame().isSuccess, isTrue);
        expect(delivered, <int>[9]);

        expect((await capture.close()).isSuccess, isTrue);
        expect(streamClosed, isTrue);
        expect(capture.isClosed, isTrue);
        await subscription.cancel();
      },
    );

    test('close → close is idempotent', () async {
      final capture = FakeCameraCapture();

      expect((await capture.close()).isSuccess, isTrue);
      expect((await capture.close()).isSuccess, isTrue);
      expect(capture.closeCalls, 2);
    });

    test('close cancels a start still waiting on its handshake', () async {
      final gate = Completer<void>();
      final capture = FakeCameraCapture(startGate: gate.future);
      final starting = capture.start();
      await Future<void>.delayed(Duration.zero);

      await capture.close();
      gate.complete();

      expect(_failure(await starting).error.code, FailureCode.cancelled);
      expect(capture.isRunning, isFalse);
    });

    test('a frame event after close is explicitly rejected', () async {
      final capture = FakeCameraCapture();
      await capture.close();

      final result = capture.emitFrame();

      expect(result.isFailure, isTrue);
      expect(_failure(result).error.code, FailureCode.cameraClosed);
    });

    test(
      'an interruption during close reports its failure and leaves no session',
      () async {
        final capture = FakeCameraCapture();
        final errors = <Object>[];
        final subscription = capture.frames.listen((_) {}, onError: errors.add);
        await capture.start();

        final interruption = capture.interrupt();
        final closed = await capture.close();

        expect(
          _failure(interruption).error.code,
          FailureCode.cameraInterrupted,
        );
        expect(errors.single, isA<CameraFailure>());
        expect(closed.isSuccess, isTrue);
        expect(capture.isRunning, isFalse);
        await subscription.cancel();
      },
    );
  });

  group('FakeCameraCapture failure matrix', () {
    test('busy maps to camera.session_busy', () async {
      final result = await FakeCameraCapture(
        startFailure: CameraFailureKind.busy,
      ).start();

      expect(_failure(result).error.code, FailureCode.cameraSessionBusy);
    });

    test(
      'unavailable maps to camera.unavailable, never a granted default',
      () async {
        final result = await FakeCameraCapture(
          startFailure: CameraFailureKind.unavailable,
        ).start();

        expect(_failure(result).error.code, FailureCode.cameraUnavailable);
        expect(
          _failure(result).error.code,
          isNot(FailureCode.cameraSessionBusy),
        );
      },
    );

    test(
      'initialization failure maps to camera.initialization_failed',
      () async {
        final result = await FakeCameraCapture(
          startFailure: CameraFailureKind.initialization,
        ).start();

        expect(
          _failure(result).error.code,
          FailureCode.cameraInitializationFailed,
        );
      },
    );

    test('frame failure maps to camera.frame_failed', () async {
      final capture = FakeCameraCapture(frameFailure: CameraFailureKind.frame);
      final subscription = capture.frames.listen((_) {}, onError: (_) {});
      await capture.start();

      final result = capture.emitFrame();

      expect(_failure(result).error.code, FailureCode.cameraFrameFailed);
      await subscription.cancel();
    });

    test('interruption maps to camera.interrupted', () async {
      final capture = FakeCameraCapture();
      final subscription = capture.frames.listen((_) {}, onError: (_) {});
      await capture.start();

      final result = capture.interrupt();

      expect(_failure(result).error.code, FailureCode.cameraInterrupted);
      await subscription.cancel();
    });
  });

  test(
    'scheduled frames have deterministic ids and monotonic timestamps',
    () async {
      final capture = FakeCameraCapture(
        timestampStep: const Duration(microseconds: 10),
      );
      final frames = <CameraFrame>[];
      final subscription = capture.frames.listen(frames.add);
      await capture.start();

      capture.emitFrame();
      capture.emitFrame();

      expect(frames.map((frame) => frame.frameId), <int>[0, 1]);
      expect(
        frames.map((frame) => frame.timestamp.microsecondsSinceSessionStart),
        <int>[0, 10],
      );
      await capture.close();
      await subscription.cancel();
    },
  );
}
