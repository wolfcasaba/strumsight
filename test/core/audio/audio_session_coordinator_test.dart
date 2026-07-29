import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_coordinator.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';

/// E01-R09 §9.2 — exactly one microphone owner, ever.
void main() {
  AudioSessionLease leaseOf(AppResult<AudioSessionLease> result) =>
      (result as Success<AudioSessionLease>).value;

  test('a second owner gets a controlled busy failure, not the mic', () async {
    final coordinator = AudioSessionCoordinator();
    final live = await coordinator.acquire(AudioOwner.live);
    expect(live.isSuccess, isTrue);

    final tuner = await coordinator.acquire(AudioOwner.tuner);

    expect(tuner.isFailure, isTrue);
    expect(tuner.failureOrNull!.code, FailureCode.audioSessionBusy);
    expect(
      tuner.failureOrNull!.retryable,
      isTrue,
      reason: 'the mic frees up when the other screen closes — retry is valid',
    );
    expect(
      coordinator.activeOwner,
      AudioOwner.live,
      reason: 'the refused owner must NOT have taken the session',
    );
  });

  test('releasing hands the microphone to the next owner', () async {
    final coordinator = AudioSessionCoordinator();
    final live = leaseOf(await coordinator.acquire(AudioOwner.live));
    await live.release();

    expect(live.isActive, isFalse);
    expect(coordinator.activeOwner, isNull);

    final tuner = await coordinator.acquire(AudioOwner.tuner);
    expect(tuner.isSuccess, isTrue);
    expect(coordinator.activeOwner, AudioOwner.tuner);
  });

  test(
    'release is idempotent and never steals the NEXT owner\'s session',
    () async {
      final coordinator = AudioSessionCoordinator();
      final live = leaseOf(await coordinator.acquire(AudioOwner.live));
      await live.release();
      final tuner = leaseOf(await coordinator.acquire(AudioOwner.tuner));

      // A late/duplicate release from the previous owner (round-114 class).
      await live.release();

      expect(coordinator.activeOwner, AudioOwner.tuner);
      expect(tuner.isActive, isTrue);
    },
  );

  test('two overlapping acquires cannot both win', () async {
    final coordinator = AudioSessionCoordinator();
    final results = await Future.wait([
      coordinator.acquire(AudioOwner.live),
      coordinator.acquire(AudioOwner.tuner),
    ]);

    expect(results.where((r) => r.isSuccess), hasLength(1));
    expect(results.where((r) => r.isFailure), hasLength(1));
  });

  test(
    'backgrounding revokes the active owner and runs its teardown',
    () async {
      final coordinator = AudioSessionCoordinator();
      var teardowns = 0;
      final lease = leaseOf(
        await coordinator.acquire(
          AudioOwner.live,
          onRevoke: () async => teardowns++,
        ),
      );

      await coordinator.revokeActive();

      expect(teardowns, 1);
      expect(lease.isActive, isFalse);
      expect(coordinator.activeOwner, isNull);
    },
  );

  test('a teardown that throws still frees the microphone', () async {
    final coordinator = AudioSessionCoordinator();
    await coordinator.acquire(
      AudioOwner.live,
      onRevoke: () async => throw StateError('engine already dead'),
    );

    await coordinator.revokeActive();

    expect(
      coordinator.activeOwner,
      isNull,
      reason: 'a crashed owner must not lock the mic forever',
    );
  });

  test('revoking a free session is a no-op', () async {
    final coordinator = AudioSessionCoordinator();
    await coordinator.revokeActive();
    expect(coordinator.activeOwner, isNull);

    // And it does not re-run a previous owner's teardown.
    var teardowns = 0;
    final lease = leaseOf(
      await coordinator.acquire(
        AudioOwner.tuner,
        onRevoke: () async => teardowns++,
      ),
    );
    await lease.release();
    await coordinator.revokeActive();
    expect(teardowns, 0);
  });
}
