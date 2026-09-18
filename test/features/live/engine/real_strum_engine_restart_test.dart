// Engine restart: stop() → start() on the SAME RealStrumEngine instance.
//
// The Live screen's Resume path calls `ref.invalidate(liveFrameProvider)`,
// whose `onDispose` fires `engine.stop()` WITHOUT awaiting it before the
// rebuilt provider calls `engine.start()` on the very same engine — the stop
// is still in flight, so the microphone lease is not back yet and the previous
// continuation has not torn its ports down. Parity with the Tuner engine.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_coordinator.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/live/engine/real_strum_engine.dart';
import 'package:strumsight/features/live/model/live_frame.dart';

import '../../../support/fake_audio.dart';
import '../../../support/gated_permission_gateway.dart';
import '../../../support/slow_stopping_capture.dart';
import '../../../support/throwing_stop_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an un-awaited stop() followed immediately by start() keeps the NEW '
      'session alive (Resume / ref.invalidate on the same engine)', () async {
    final coordinator = AudioSessionCoordinator();
    final capture = SlowStoppingAudioCapture();
    final engine = RealStrumEngine(
      mic: fakeMicCapture(
        owner: AudioOwner.live,
        coordinator: coordinator,
        capture: capture,
      ),
    );
    addTearDown(engine.dispose);

    final errors = <Object>[];
    final frames = <LiveFrame>[];
    final sub = engine.frames.listen(frames.add, onError: errors.add);
    addTearDown(sub.cancel);

    await engine.start();
    expect(coordinator.activeOwner, AudioOwner.live);

    unawaited(engine.stop());
    await engine.start();
    await Future<void>.delayed(Duration.zero);

    expect(
      errors,
      isEmpty,
      reason:
          'the restart must wait for the previous stop to hand the session '
          'back instead of failing with audioSessionBusy',
    );
    expect(
      coordinator.activeOwner,
      AudioOwner.live,
      reason: 'the NEW session must hold the microphone lease',
    );
    expect(
      capture.isRunning,
      isTrue,
      reason: 'the stale stop must not close the NEW capture',
    );

    // …and the new DSP isolate must still be the one the engine talks to.
    capture.emit(List<double>.filled(8192, 0));
    for (var i = 0; i < 100 && frames.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      frames,
      isNotEmpty,
      reason: 'the NEW DSP isolate must survive the stale stop',
    );
  });

  // The OTHER order, and the round-2 regression: the start is still QUEUED
  // when the stop arrives — `_onAppLifecycle`'s un-awaited `stop()` landing on
  // a Resume/Retry `ref.invalidate` that has not run yet. The stop has to stop
  // the microphone THAT start opens. An engine that fires `_mic.stop()`
  // eagerly and only queues the teardown consumes the stop SIGNAL before the
  // start runs (`MicCapture.start` resets `_stopRequested`), so the queued
  // start opens the microphone and the queued teardown then awaits an
  // already-finished stop: the app sits in the BACKGROUND recording, with the
  // exclusive lease held forever (§5, E01-R09 §9.4).
  test('a start that is still queued when stop() arrives is stopped BY it '
      '(backgrounding leaves nothing recording)', () async {
    final coordinator = AudioSessionCoordinator();
    final capture = SlowStoppingAudioCapture();
    final engine = RealStrumEngine(
      mic: fakeMicCapture(
        owner: AudioOwner.live,
        coordinator: coordinator,
        capture: capture,
      ),
    );
    addTearDown(engine.dispose);

    final errors = <Object>[];
    final sub = engine.frames.listen((_) {}, onError: errors.add);
    addTearDown(sub.cancel);

    // `ref.invalidate(liveFrameProvider)` has queued a start; the user
    // switches apps in the same turn and `_onAppLifecycle` fires stop().
    unawaited(engine.start());
    await engine.stop();

    expect(
      capture.isRunning,
      isFalse,
      reason: 'the queued start opened the mic — the stop must close THAT one',
    );
    expect(
      capture.stopCalls,
      greaterThan(0),
      reason: 'the platform capture must actually have been told to stop',
    );
    expect(
      coordinator.activeOwner,
      isNull,
      reason: 'the exclusive lease must be back once stop() completes',
    );
    expect(errors, isEmpty);
  });

  test('two restarts landing back to back still end with the microphone '
      'closed and the lease back (Resume tapped twice)', () async {
    final coordinator = AudioSessionCoordinator();
    final capture = SlowStoppingAudioCapture();
    final engine = RealStrumEngine(
      mic: fakeMicCapture(
        owner: AudioOwner.live,
        coordinator: coordinator,
        capture: capture,
      ),
    );
    addTearDown(engine.dispose);

    final errors = <Object>[];
    final sub = engine.frames.listen((_) {}, onError: errors.add);
    addTearDown(sub.cancel);

    await engine.start();
    unawaited(engine.stop());
    unawaited(engine.start());
    await engine.stop();

    expect(capture.isRunning, isFalse);
    expect(coordinator.activeOwner, isNull);
    expect(errors, isEmpty);
  });

  // §9.3 proper: the user leaves Live while the permission dialog is up. The
  // microphone must never be OPENED for a screen that is already gone — on
  // Android the runtime dialog pauses the activity, so this is the ordinary
  // first-run path, not an edge case, and "opened, then closed a step later"
  // means recording with the app in the background. That is what `stop()`'s
  // cancel signal (`MicCapture._stopRequested`, raised synchronously) is for.
  // The same path carries a background revoke
  // (`AudioSessionCoordinator.revokeActive()` → the engine's `onRevoke`).
  test('stop() while the permission dialog is up never opens the microphone '
      'at all', () async {
    final coordinator = AudioSessionCoordinator();
    final capture = FakeAudioCapture();
    final permissions = GatedPermissionGateway();
    final engine = RealStrumEngine(
      mic: fakeMicCapture(
        owner: AudioOwner.live,
        coordinator: coordinator,
        permissions: permissions,
        capture: capture,
      ),
    );
    addTearDown(engine.dispose);

    final errors = <Object>[];
    final sub = engine.frames.listen((_) {}, onError: errors.add);
    addTearDown(sub.cancel);

    final starting = engine.start();
    await permissions.asked; // the system dialog is up

    // The user leaves Live. NOT awaited: the caller (ref.onDispose, the
    // background hook) drops this future, which must not turn a throwing
    // teardown into an unhandled async error either.
    final stopping = engine.stop();
    permissions.grant();
    await starting;
    await stopping;

    expect(
      capture.startCalls,
      isZero,
      reason:
          'the platform capture must never be OPENED for a screen that is '
          'already gone — the stop signal has to cancel the handshake, not '
          'merely close what it opened (§9.3)',
    );
    expect(
      capture.isRunning,
      isFalse,
      reason: 'the screen is gone — nothing may still be recording',
    );
    expect(coordinator.activeOwner, isNull, reason: 'no lease may be left');
    expect(errors, isEmpty, reason: 'a cancelled start is not an error (§9.3)');
  });

  // ---------------------------------------------------------------------
  // The throwing platform teardown. `MicCapture.stop()` has no try/catch
  // around `await capture?.stop()`, and on the device that call is a
  // `StreamSubscription.cancel()` on the audio_streamer EventChannel — it
  // throws when the channel is already gone. Everything after that await is
  // skipped, so this is the path on which the engine either frees its
  // lifecycle resources or leaks them for the rest of the process (§7): the
  // ReceivePort, the DSP isolate, and the Lab-mode ring buffer that is still
  // holding up to ~30 s of recorded audio (§5).
  // ---------------------------------------------------------------------

  test('a platform stop that throws still hands the exclusive lease back, '
      'drops the buffered PCM, logs the failure, and restarts', () async {
    final coordinator = AudioSessionCoordinator();
    final capture = ThrowingStopAudioCapture();
    final logger = _RecordingLogger();
    final engine = RealStrumEngine(
      mic: fakeMicCapture(
        owner: AudioOwner.live,
        coordinator: coordinator,
        capture: capture,
      ),
      logger: logger,
    );
    addTearDown(() {
      capture.throwOnStop = false;
      return engine.dispose();
    });

    final errors = <Object>[];
    final frames = <LiveFrame>[];
    final sub = engine.frames.listen(frames.add, onError: errors.add);
    addTearDown(sub.cancel);

    // Lab mode on: the engine now retains recent microphone PCM, which is the
    // one piece of the teardown a test can read back (`recentPcm`).
    engine.setDiagnosticsCapture(true);
    await engine.start();
    expect(coordinator.activeOwner, AudioOwner.live);
    capture.emit(List<double>.filled(2048, 0.25));
    expect(
      engine.recentPcm().$1,
      isNotEmpty,
      reason: 'precondition: there IS retained audio to be dropped',
    );

    await engine.stop();

    expect(
      coordinator.activeOwner,
      isNull,
      reason:
          'the platform threw on the way out, but the EXCLUSIVE lease must '
          'still come back — a lease that stays held means nothing in the app '
          'can ever open the microphone again (§5)',
    );
    expect(
      engine.recentPcm().$1,
      isEmpty,
      reason:
          'the teardown must run even when the platform stop throws: retained '
          'microphone PCM may not outlive the microphone (§5, §7)',
    );
    expect(
      logger.errorEvents,
      contains('live.engine.lifecycle_failed'),
      reason:
          'a platform failure dropped without a trace is an empty catch (§10)',
    );
    expect(
      errors,
      isEmpty,
      reason: 'a failed teardown is not a frame-stream error',
    );

    // …and the lifecycle chain is not poisoned: the next start still runs, on
    // a NEW isolate that actually delivers frames.
    capture.throwOnStop = false;
    await engine.start();
    expect(coordinator.activeOwner, AudioOwner.live);
    capture.emit(List<double>.filled(8192, 0));
    for (var i = 0; i < 100 && frames.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      frames,
      isNotEmpty,
      reason: 'a failed stop must not poison the lifecycle queue',
    );
  });

  // The other half: the throw lands inside the QUEUED step (the cancel signal
  // found nothing open, the queued start opened the microphone, and the
  // queued `_mic.stop()` is what throws). Without a `finally` the snapshotted
  // ReceivePort and DSP isolate are already unreachable from the engine's
  // fields, so no later stop() could ever free them.
  test('a throwing platform stop in the QUEUED step is reported and leaves '
      'the engine restartable', () async {
    final coordinator = AudioSessionCoordinator();
    final capture = ThrowingStopAudioCapture();
    final logger = _RecordingLogger();
    final engine = RealStrumEngine(
      mic: fakeMicCapture(
        owner: AudioOwner.live,
        coordinator: coordinator,
        capture: capture,
      ),
      logger: logger,
    );
    addTearDown(() {
      capture.throwOnStop = false;
      return engine.dispose();
    });

    final errors = <Object>[];
    final frames = <LiveFrame>[];
    final sub = engine.frames.listen(frames.add, onError: errors.add);
    addTearDown(sub.cancel);

    unawaited(engine.start());
    await engine.stop();

    expect(
      capture.isRunning,
      isFalse,
      reason: 'the queued start opened the mic — the stop must close THAT one',
    );
    expect(
      coordinator.activeOwner,
      isNull,
      reason:
          'ONE stop() must hand the exclusive lease back even when the '
          'platform throws INSIDE the queued step. `MicCapture.stop()` '
          'releases the session only after `capture.stop()` returns, so the '
          'engine has to ask a second time from its own `finally`. There is '
          'no later stop() to rely on: `dispose()` calls stop() exactly once, '
          'and a lease left held there is held for the rest of the process — '
          'every later microphone owner gets audioSessionBusy (§5)',
    );
    expect(
      logger.errorFields.where((fields) => fields['op'] == 'stop'),
      isNotEmpty,
      reason:
          'the queued step must RE-THROW after its finally so `_enqueue` logs '
          'it — swallowing it inside `_stop` would hide the platform failure',
    );

    // …and the session really is free: the next start acquires it again with
    // no second stop() to help it.
    capture.throwOnStop = false;
    await engine.start();
    expect(coordinator.activeOwner, AudioOwner.live);
    capture.emit(List<double>.filled(8192, 0));
    for (var i = 0; i < 100 && frames.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(frames, isNotEmpty);
    expect(errors, isEmpty);
  });
}

/// Captures what the engine logged, which is the only way to assert that a
/// throwing platform teardown was HANDLED rather than swallowed (§10).
class _RecordingLogger implements AppLogger {
  final List<String> errorEvents = [];
  final List<Map<String, Object?>> errorFields = [];

  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) {}

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) {}

  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {}

  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    errorEvents.add(event);
    errorFields.add(fields);
  }
}
