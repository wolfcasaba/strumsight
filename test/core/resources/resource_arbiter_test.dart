// E12-R15 — resource_arbiter_test.dart (ADR 0476).
//
// A1, A2, A4, A5 per docs/rounds/e12-r15-resource-coexistence-policy.md §6,
// plus one extra cell for the D1 equal-priority tie (no preemption).
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_coordinator.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/resources/public.dart';

void main() {
  group('A1 — a higher-priority request suspends (not cancels) an active '
      'lower-priority consumer', () {
    test('backgroundAi is paused when liveAudio requests', () async {
      final arbiter = ResourceArbiter();
      final background = _FakeConsumer(ResourcePriority.backgroundAi)
        ..state = 'partial-inference-buffer';
      arbiter.register(background);
      final granted = await arbiter.request(background);
      expect(granted, isA<ResourceGranted>());
      expect(background.isActive, isTrue);

      final live = _FakeConsumer(ResourcePriority.liveAudio);
      arbiter.register(live);
      final decision = await arbiter.request(live);

      expect(decision, isA<ResourceGranted>());
      expect((decision as ResourceGranted).suspended, contains(background));
      expect(background.pauseCalls, 1);
      expect(background.releaseCalls, 0, reason: 'pause must not release');
      expect(background.isSuspended, isTrue);
      expect(
        background.isActive,
        isTrue,
        reason: 'a suspended consumer is not cancelled — it stays active',
      );
      expect(live.acquireCalls, 1);
    });
  });

  group('A2 — the arbiter never takes a granted audio lease away', () {
    test('suspending backgroundAi leaves the REAL AudioSessionCoordinator '
        "lease untouched; a second direct acquire still gets busy", () async {
      final coordinator = AudioSessionCoordinator();
      final arbiter = ResourceArbiter();
      final background = _AudioBackedConsumer(
        coordinator,
        ResourcePriority.backgroundAi,
        AudioOwner.analyzeRecorder,
      );
      arbiter.register(background);
      await arbiter.request(background);
      expect(coordinator.activeOwner, AudioOwner.analyzeRecorder);

      final live = _FakeConsumer(ResourcePriority.liveAudio);
      arbiter.register(live);
      final decision = await arbiter.request(live);

      expect(decision, isA<ResourceGranted>());
      expect(background.isSuspended, isTrue);
      expect(
        coordinator.activeOwner,
        AudioOwner.analyzeRecorder,
        reason: 'the arbiter must not revoke the real lease to suspend it',
      );
      expect(background.lease!.isActive, isTrue);

      final second = await coordinator.acquire(AudioOwner.live);
      expect(second.isFailure, isTrue);
      expect(
        second.failureOrNull!.code,
        FailureCode.audioSessionBusy,
        reason:
            'the coordinator, not the arbiter, is still the sole '
            'authority over the exclusive microphone session',
      );
    });
  });

  group(
    'A4 — memory pressure sheds the lowest-priority active consumer first',
    () {
      test('the highest-priority active consumer keeps running', () async {
        final arbiter = ResourceArbiter();
        final live = _FakeConsumer(ResourcePriority.liveAudio);
        final camera = _FakeConsumer(ResourcePriority.cameraFeedback);
        final background = _FakeConsumer(ResourcePriority.backgroundAi);
        for (final consumer in [live, camera, background]) {
          arbiter.register(consumer);
          final decision = await arbiter.request(consumer);
          expect(
            decision,
            isA<ResourceGranted>(),
            reason: 'different tiers coexist — none of these deny',
          );
        }
        expect([live, camera, background], everyElement(_isActiveNotSuspended));

        await arbiter.onMemoryPressure();

        expect(
          background.isSuspended,
          isTrue,
          reason: 'lowest priority active consumer sheds first',
        );
        expect(camera.isSuspended, isFalse);
        expect(
          live.isSuspended,
          isFalse,
          reason: 'highest priority active consumer must keep running',
        );
        expect(
          [camera, live],
          everyElement(_isActiveNotSuspended),
          reason: 'memory pressure must not stop everyone at once',
        );
      });

      test(
        'repeated pressure eventually reaches the highest tier last',
        () async {
          final arbiter = ResourceArbiter();
          final live = _FakeConsumer(ResourcePriority.liveAudio);
          final camera = _FakeConsumer(ResourcePriority.cameraFeedback);
          for (final consumer in [live, camera]) {
            arbiter.register(consumer);
            await arbiter.request(consumer);
          }

          await arbiter.onMemoryPressure();
          expect(camera.isSuspended, isTrue);
          expect(live.isSuspended, isFalse);

          await arbiter.onMemoryPressure();
          expect(
            live.isSuspended,
            isTrue,
            reason: 'once nothing lower remains, the highest is touched last',
          );
        },
      );
    },
  );

  group('A5 — a suspended consumer resumes with its state preserved', () {
    test('pause -> resume keeps the in-progress work intact', () async {
      final arbiter = ResourceArbiter();
      final background = _FakeConsumer(ResourcePriority.backgroundAi)
        ..state = 'chord-window-17';
      arbiter.register(background);
      await arbiter.request(background);

      final live = _FakeConsumer(ResourcePriority.liveAudio);
      arbiter.register(live);
      await arbiter.request(live);

      expect(background.isSuspended, isTrue);
      expect(background.state, 'chord-window-17');

      await background.resume();

      expect(background.resumeCalls, 1);
      expect(background.isSuspended, isFalse);
      expect(background.isActive, isTrue);
      expect(
        background.state,
        'chord-window-17',
        reason: 'resume must continue from the preserved state, not restart',
      );
    });
  });

  group('D1 — equal priority never preempts', () {
    test(
      'a second same-tier request is denied, the first stays active',
      () async {
        final arbiter = ResourceArbiter();
        final first = _FakeConsumer(ResourcePriority.cameraFeedback);
        arbiter.register(first);
        await arbiter.request(first);

        final second = _FakeConsumer(ResourcePriority.cameraFeedback);
        arbiter.register(second);
        final decision = await arbiter.request(second);

        expect(decision, isA<ResourceDenied>());
        expect(
          (decision as ResourceDenied).reason,
          ResourceDenialReason.equalPriorityActive,
        );
        expect(second.acquireCalls, 0);
        expect(first.isSuspended, isFalse);
        expect(first.isActive, isTrue);
      },
    );
  });
}

Matcher get _isActiveNotSuspended => predicate<_FakeConsumer>(
  (consumer) => consumer.isActive && !consumer.isSuspended,
  'active and not suspended',
);

final class _FakeConsumer implements ResourceConsumer {
  _FakeConsumer(this.priority);

  @override
  final ResourcePriority priority;

  String state = '';
  bool _active = false;
  bool _suspended = false;
  int acquireCalls = 0;
  int releaseCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;

  @override
  bool get isActive => _active;

  @override
  bool get isSuspended => _suspended;

  @override
  Future<void> acquire() async {
    acquireCalls += 1;
    _active = true;
  }

  @override
  Future<void> release() async {
    releaseCalls += 1;
    _active = false;
    _suspended = false;
  }

  @override
  Future<void> pauseForHigherPriority() async {
    pauseCalls += 1;
    _suspended = true;
  }

  @override
  Future<void> resume() async {
    resumeCalls += 1;
    _suspended = false;
  }
}

/// A [ResourceConsumer] backed by a REAL [AudioSessionCoordinator] lease, so
/// A2 measures the actual coordinator state rather than a mock (round brief
/// §0.0 R3 / L453).
final class _AudioBackedConsumer implements ResourceConsumer {
  _AudioBackedConsumer(this._coordinator, this.priority, this.owner);

  final AudioSessionCoordinator _coordinator;
  final AudioOwner owner;

  @override
  final ResourcePriority priority;

  AudioSessionLease? lease;
  bool _suspended = false;

  @override
  bool get isActive => lease?.isActive ?? false;

  @override
  bool get isSuspended => _suspended;

  @override
  Future<void> acquire() async {
    final result = await _coordinator.acquire(owner);
    lease = result.valueOrNull;
  }

  @override
  Future<void> release() async {
    await lease?.release();
  }

  @override
  Future<void> pauseForHigherPriority() async {
    // Cooperative pause only: the underlying lease stays held, proving the
    // arbiter has no separate path that revokes it (ADR 0476 D2).
    _suspended = true;
  }

  @override
  Future<void> resume() async {
    _suspended = false;
  }
}
