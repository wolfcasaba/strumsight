import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_coordinator.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';

import '../../support/fake_audio.dart';

/// E01-R09 §9.1/§9.3 — the microphone opens only with a KNOWN grant, and no
/// failure path leaves a stream or a lease behind.
void main() {
  test('a denied permission never opens the microphone', () async {
    final capture = FakeAudioCapture();
    final coordinator = AudioSessionCoordinator();
    final mic = fakeMicCapture(
      coordinator: coordinator,
      permissions: FakeMicrophonePermissionGateway(
        state: MicrophonePermissionState.denied,
      ),
      capture: capture,
    );

    final result = await mic.start((_) {});

    expect(result.failureOrNull, isA<PermissionFailure>());
    expect(result.failureOrNull!.code, FailureCode.permissionMicrophoneDenied);
    expect(result.failureOrNull!.retryable, isTrue);
    expect(capture.startCalls, 0);
    expect(coordinator.activeOwner, isNull);
    expect(mic.isActive, isFalse);
  });

  test('a permanently denied permission is not retryable', () async {
    final mic = fakeMicCapture(
      permissions: FakeMicrophonePermissionGateway(
        state: MicrophonePermissionState.permanentlyDenied,
      ),
    );

    final result = await mic.start((_) {});

    expect(result.failureOrNull!.retryable, isFalse);
  });

  test('a missing permission channel is NOT a silent grant', () async {
    final capture = FakeAudioCapture();
    final mic = fakeMicCapture(
      permissions: FakeMicrophonePermissionGateway(
        state: MicrophonePermissionState.unavailable,
      ),
      capture: capture,
    );

    final result = await mic.start((_) {});

    expect(result.failureOrNull!.code, FailureCode.permissionUnavailable);
    expect(
      capture.startCalls,
      0,
      reason: 'an unknown permission state must never open the mic (§9.1)',
    );
  });

  test('a denied-then-granted request opens the mic exactly once', () async {
    final permissions = FakeMicrophonePermissionGateway(
      state: MicrophonePermissionState.denied,
      afterRequest: MicrophonePermissionState.granted,
    );
    final capture = FakeAudioCapture(sampleRate: 48000);
    final mic = fakeMicCapture(permissions: permissions, capture: capture);

    final result = await mic.start((_) {});

    expect(result.valueOrNull, 48000);
    expect(permissions.requestCalls, 1);
    expect(capture.startCalls, 1);
    expect(mic.isActive, isTrue);
  });

  test('a granted permission is not re-requested', () async {
    final permissions = FakeMicrophonePermissionGateway();
    final mic = fakeMicCapture(permissions: permissions);

    await mic.start((_) {});

    expect(permissions.requestCalls, 0);
  });

  test(
    'a busy session fails the second owner without touching the mic',
    () async {
      final coordinator = AudioSessionCoordinator();
      final liveCapture = FakeAudioCapture();
      final tunerCapture = FakeAudioCapture();
      final live = fakeMicCapture(
        coordinator: coordinator,
        capture: liveCapture,
      );
      final tuner = fakeMicCapture(
        owner: AudioOwner.tuner,
        coordinator: coordinator,
        capture: tunerCapture,
      );

      await live.start((_) {});
      final second = await tuner.start((_) {});

      expect(second.failureOrNull!.code, FailureCode.audioSessionBusy);
      expect(tunerCapture.startCalls, 0);
      expect(
        liveCapture.isRunning,
        isTrue,
        reason: 'the holder keeps recording',
      );
    },
  );

  test('overlapping start() calls share ONE capture (single-flight)', () async {
    final gate = Completer<void>();
    final capture = FakeAudioCapture(startGate: gate.future);
    final mic = fakeMicCapture(capture: capture);

    final first = mic.start((_) {});
    final second = mic.start((_) {});
    gate.complete();
    await Future.wait([first, second]);

    expect(capture.startCalls, 1);
  });

  test('stop() during the permission dialog never opens the mic', () async {
    final capture = FakeAudioCapture();
    final coordinator = AudioSessionCoordinator();
    final mic = fakeMicCapture(coordinator: coordinator, capture: capture);

    final starting = mic.start((_) {});
    await mic.stop(); // route left while the dialog was up (§9.3)
    final result = await starting;

    expect(result.failureOrNull, isA<CancelledFailure>());
    expect(capture.startCalls, 0);
    expect(coordinator.activeOwner, isNull);
    expect(mic.isActive, isFalse);
  });

  test('stop() during the capture handshake leaves no orphan stream', () async {
    final gate = Completer<void>();
    final capture = FakeAudioCapture(startGate: gate.future);
    final coordinator = AudioSessionCoordinator();
    final mic = fakeMicCapture(coordinator: coordinator, capture: capture);

    final starting = mic.start((_) {});
    // Let the permission + lease steps land: the capture is now mid-start.
    await Future<void>.delayed(Duration.zero);
    expect(capture.startCalls, 1);

    await mic.stop(); // the user left while the platform was handing over
    gate.complete();
    final result = await starting;

    expect(result.failureOrNull, isA<CancelledFailure>());
    expect(
      capture.stopCalls,
      greaterThanOrEqualTo(1),
      reason: 'the stream that arrived after the stop must be cancelled',
    );
    expect(capture.isRunning, isFalse);
    expect(mic.isActive, isFalse);
    expect(coordinator.activeOwner, isNull, reason: 'the lease must be back');
  });

  test('a capture that throws frees the session for a retry', () async {
    final coordinator = AudioSessionCoordinator();
    final failing = FakeAudioCapture(failWith: StateError('mic busy'));
    final mic = fakeMicCapture(coordinator: coordinator, capture: failing);

    final result = await mic.start((_) {});

    expect(result.failureOrNull!.code, FailureCode.audioCaptureFailed);
    expect(failing.stopCalls, 1);
    expect(coordinator.activeOwner, isNull);
    expect(mic.isActive, isFalse);
  });

  test('start → stop releases both the capture and the lease', () async {
    final coordinator = AudioSessionCoordinator();
    final capture = FakeAudioCapture();
    final mic = fakeMicCapture(coordinator: coordinator, capture: capture);

    await mic.start((_) {});
    expect(coordinator.activeOwner, AudioOwner.live);

    await mic.stop();

    expect(capture.isRunning, isFalse);
    expect(coordinator.activeOwner, isNull);
    expect(mic.isActive, isFalse);
  });

  test('stop() without start(), and a double stop, are no-ops', () async {
    final coordinator = AudioSessionCoordinator();
    final mic = fakeMicCapture(coordinator: coordinator);

    await mic.stop();
    await mic.start((_) {});
    await mic.stop();
    await mic.stop();

    expect(coordinator.activeOwner, isNull);
  });

  test('a revoked owner is torn down through its own onRevoke', () async {
    final coordinator = AudioSessionCoordinator();
    final capture = FakeAudioCapture();
    final mic = fakeMicCapture(coordinator: coordinator, capture: capture);
    var teardowns = 0;

    await mic.start(
      (_) {},
      onRevoke: () async {
        teardowns++;
        await mic.stop();
      },
    );
    await coordinator.revokeActive();

    expect(teardowns, 1);
    expect(capture.isRunning, isFalse);
    expect(coordinator.activeOwner, isNull);
  });

  test('chunks reach the listener while running', () async {
    final capture = FakeAudioCapture();
    final mic = fakeMicCapture(capture: capture);
    final chunks = <List<double>>[];

    await mic.start(chunks.add);
    capture.emit(const [0.1, 0.2]);

    expect(chunks, hasLength(1));
  });
}
