import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_session_coordinator.dart';
import 'package:strumsight/core/camera/camera_session_lease.dart';
import 'package:strumsight/core/camera/fake_camera_capture.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';

CameraSessionLease _leaseOf(AppResult<CameraSessionLease> result) =>
    (result as Success<CameraSessionLease>).value;

void main() {
  group('CameraSessionCoordinator race matrix', () {
    test(
      'two overlapping acquires produce one lease and one busy failure',
      () async {
        final coordinator = CameraSessionCoordinator();

        final results = await Future.wait([
          coordinator.acquire(CameraOwner.visionSetup),
          coordinator.acquire(CameraOwner.visionPractice),
        ]);

        expect(results.where((result) => result.isSuccess), hasLength(1));
        expect(results.where((result) => result.isFailure), hasLength(1));
        expect(
          results.singleWhere((result) => result.isFailure).failureOrNull!.code,
          FailureCode.cameraSessionBusy,
        );
      },
    );

    test(
      'a revoke during capture start cancels start and frees the lease',
      () async {
        final coordinator = CameraSessionCoordinator();
        final startGate = Completer<void>();
        final capture = FakeCameraCapture(startGate: startGate.future);
        final lease = _leaseOf(
          await coordinator.acquire(
            CameraOwner.visionSetup,
            onRevoke: () async {
              await capture.close();
            },
          ),
        );
        final starting = capture.start();
        await Future<void>.delayed(Duration.zero);

        final revoking = coordinator.revokeActive();
        startGate.complete();
        final result = await starting;
        await revoking;

        expect(result.failureOrNull!.code, FailureCode.cancelled);
        expect(capture.isClosed, isTrue);
        expect(lease.isActive, isFalse);
        expect(coordinator.activeOwner, isNull);
      },
    );

    test('release followed by release is idempotent', () async {
      final coordinator = CameraSessionCoordinator();
      final lease = _leaseOf(
        await coordinator.acquire(CameraOwner.visionPractice),
      );

      await lease.release();
      await lease.release();

      expect(lease.isActive, isFalse);
      expect(coordinator.activeOwner, isNull);
    });

    test(
      'acquire during close receives busy until teardown releases the lease',
      () async {
        final coordinator = CameraSessionCoordinator();
        final closeGate = Completer<void>();
        final closing = _leaseOf(
          await coordinator.acquire(
            CameraOwner.visionSetup,
            onRevoke: () => closeGate.future,
          ),
        );

        final revoking = coordinator.revokeActive();
        await closing.release();
        final competing = await coordinator.acquire(CameraOwner.songVision);

        expect(competing.failureOrNull!.code, FailureCode.cameraSessionBusy);
        expect(closing.isActive, isTrue);

        closeGate.complete();
        await revoking;

        expect(coordinator.activeOwner, isNull);
      },
    );

    test(
      'interruption during close tears down the capture exactly once',
      () async {
        final coordinator = CameraSessionCoordinator();
        final capture = FakeCameraCapture();
        final errors = <Object>[];
        final subscription = capture.frames.listen((_) {}, onError: errors.add);
        var teardownCalls = 0;
        final lease = _leaseOf(
          await coordinator.acquire(
            CameraOwner.songVision,
            onRevoke: () async {
              teardownCalls += 1;
              await capture.close();
            },
          ),
        );
        await capture.start();

        final interruption = capture.interrupt();
        await Future.wait([coordinator.revokeActive(), lease.release()]);

        expect(teardownCalls, 1);
        expect(interruption.failureOrNull!.code, FailureCode.cameraInterrupted);
        expect(errors.single, isA<CameraFailure>());
        expect(capture.isClosed, isTrue);
        expect(lease.isActive, isFalse);
        expect(coordinator.activeOwner, isNull);
        await subscription.cancel();
      },
    );

    test(
      'route leave closes the fake capture before releasing its lease',
      () async {
        final coordinator = CameraSessionCoordinator();
        final capture = FakeCameraCapture();
        var streamClosed = false;
        var deliveredFrames = 0;
        final subscription = capture.frames.listen(
          (_) => deliveredFrames += 1,
          onDone: () => streamClosed = true,
        );
        final lease = _leaseOf(
          await coordinator.acquire(
            CameraOwner.visionPractice,
            onRevoke: () async {
              await capture.close();
            },
          ),
        );
        await capture.start();
        expect(capture.emitFrame().isSuccess, isTrue);

        await coordinator.revokeActive();

        expect(capture.isClosed, isTrue);
        expect(streamClosed, isTrue);
        expect(deliveredFrames, 1);
        expect(
          capture.emitFrame().failureOrNull!.code,
          FailureCode.cameraClosed,
        );
        expect(lease.isActive, isFalse);
        expect(coordinator.activeOwner, isNull);
        await subscription.cancel();
      },
    );

    test('a late release cannot clear the next owner', () async {
      final coordinator = CameraSessionCoordinator();
      final first = _leaseOf(
        await coordinator.acquire(CameraOwner.visionSetup),
      );
      await first.release();
      final next = _leaseOf(await coordinator.acquire(CameraOwner.labCapture));

      await first.release();

      expect(next.isActive, isTrue);
      expect(coordinator.activeOwner, CameraOwner.labCapture);
    });

    test(
      'lifecycle log events contain only the required safe fields',
      () async {
        final logger = _RecordingLogger();
        final coordinator = CameraSessionCoordinator(
          logger: logger,
          now: () => DateTime.utc(2026, 8, 6),
        );
        final lease = _leaseOf(
          await coordinator.acquire(CameraOwner.labCapture),
        );
        await coordinator.revokeActive(
          reason: CameraSessionRevocationReason.routeLeave,
        );

        expect(lease.isActive, isFalse);
        expect(logger.events.map((event) => event.name), <String>[
          'camera.session.acquired',
          'camera.session.revoked',
          'camera.session.released',
        ]);
        for (final event in logger.events) {
          expect(
            event.fields.keys,
            unorderedEquals(<String>[
              'owner',
              'reason',
              'timestamp',
              'leaseId',
            ]),
          );
          expect(event.fields['owner'], CameraOwner.labCapture.name);
          expect(event.fields['timestamp'], '2026-08-06T00:00:00.000Z');
        }
      },
    );
  });
}

final class _RecordingLogger implements AppLogger {
  final events = <({String name, Map<String, Object?> fields})>[];

  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) {
    events.add((name: event, fields: fields));
  }

  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    events.add((name: event, fields: fields));
  }

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) {
    events.add((name: event, fields: fields));
  }

  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    events.add((name: event, fields: fields));
  }
}
