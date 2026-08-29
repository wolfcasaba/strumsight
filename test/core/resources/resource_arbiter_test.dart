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

  group('F2 — suspension has a way back, no silent stall', () {
    test('a suspended consumer resumes once the consumer that caused the '
        'suspension finishes via the arbiter', () async {
      final arbiter = ResourceArbiter();
      final background = _FakeConsumer(ResourcePriority.backgroundAi)
        ..state = 'partial-inference-buffer';
      arbiter.register(background);
      await arbiter.request(background);

      final live = _FakeConsumer(ResourcePriority.liveAudio);
      arbiter.register(live);
      await arbiter.request(live);
      expect(background.isSuspended, isTrue);

      await arbiter.releaseConsumer(live);

      expect(background.isSuspended, isFalse);
      expect(background.resumeCalls, 1);
      expect(background.isActive, isTrue);
      expect(
        background.state,
        'partial-inference-buffer',
        reason: 'the way back must not restart the resumed consumer',
      );
    });

    test('partial resume: a consumer still outranked by another active '
        'consumer stays suspended', () async {
      final arbiter = ResourceArbiter();
      final background = _FakeConsumer(ResourcePriority.backgroundAi);
      final camera = _FakeConsumer(ResourcePriority.cameraFeedback);
      final live = _FakeConsumer(ResourcePriority.liveAudio);
      arbiter
        ..register(background)
        ..register(camera)
        ..register(live);

      await arbiter.request(background);
      await arbiter.request(camera); // outranks background -> suspends it
      await arbiter.request(live); // outranks camera -> suspends it
      expect(background.isSuspended, isTrue);
      expect(camera.isSuspended, isTrue);

      await arbiter.releaseConsumer(live);

      expect(
        camera.isSuspended,
        isFalse,
        reason: 'nothing active outranks camera once live is gone',
      );
      expect(camera.resumeCalls, 1);
      expect(
        background.isSuspended,
        isTrue,
        reason: 'camera, now active again, still outranks background',
      );
      expect(background.resumeCalls, 0);
    });

    test('a consumer suspended by memory pressure resumes once the caller '
        'signals the pressure is relieved', () async {
      final arbiter = ResourceArbiter();
      final live = _FakeConsumer(ResourcePriority.liveAudio)
        ..state = 'measure-42';
      arbiter.register(live);
      await arbiter.request(live);

      await arbiter.onMemoryPressure();
      expect(live.isSuspended, isTrue);

      await arbiter.onMemoryPressureRelieved();

      expect(live.isSuspended, isFalse);
      expect(live.resumeCalls, 1);
      expect(live.isActive, isTrue);
      expect(live.state, 'measure-42');
    });
  });

  group('F1 — the ResourceConsumer contract is machine-checked, not just '
      'asserted in prose', () {
    runResourceConsumerContract(
      '_FakeConsumer honours pauseForHigherPriority as a pause',
      () => _FakeConsumer(ResourcePriority.backgroundAi),
      putWorkIn: (consumer) =>
          (consumer as _FakeConsumer).state = 'contract-probe',
      readWork: (consumer) => (consumer as _FakeConsumer).state,
    );

    test('self-guard: a consumer that discards state in '
        'pauseForHigherPriority (i.e. implements it as cancel) fails the '
        'contract check', () async {
      await expectLater(
        checkResourceConsumerContract(
          make: () => _CancellingFakeConsumer(ResourcePriority.backgroundAi),
          putWorkIn: (consumer) =>
              (consumer as _CancellingFakeConsumer).state = 'probe',
          readWork: (consumer) => (consumer as _CancellingFakeConsumer).state,
        ),
        throwsA(isA<TestFailure>()),
        reason:
            'proves the contract set actually catches a cancel-style '
            'consumer, not just a fake pauseForHigherPriority',
      );
    });
  });
}

/// A reusable conformance suite for any [ResourceConsumer] implementation:
/// `acquire` activates without suspending, `pauseForHigherPriority` suspends
/// WITHOUT discarding [putWorkIn]'s state (ADR 0476 D3 — a pause, not a
/// cancel), `resume` restores it, and both are idempotent. Wraps
/// [checkResourceConsumerContract] in a `group`/`test` so a conformant
/// implementation shows up as ordinary green cells.
void runResourceConsumerContract(
  String description,
  ResourceConsumer Function() make, {
  required void Function(ResourceConsumer consumer) putWorkIn,
  required Object? Function(ResourceConsumer consumer) readWork,
}) {
  group(description, () {
    test('acquire / pauseForHigherPriority / resume preserve isActive, '
        'isSuspended and in-progress work', () async {
      await checkResourceConsumerContract(
        make: make,
        putWorkIn: putWorkIn,
        readWork: readWork,
      );
    });
  });
}

/// The bare assertions behind [runResourceConsumerContract], factored out so
/// a self-guard cell can assert that THIS check throws for a non-conformant
/// consumer (`expectLater(checkResourceConsumerContract(...), throwsA(...))`)
/// instead of merely trusting that it would.
Future<void> checkResourceConsumerContract({
  required ResourceConsumer Function() make,
  required void Function(ResourceConsumer consumer) putWorkIn,
  required Object? Function(ResourceConsumer consumer) readWork,
}) async {
  final consumer = make();

  await consumer.acquire();
  expect(
    consumer.isActive,
    isTrue,
    reason: 'acquire() must activate the consumer',
  );
  expect(
    consumer.isSuspended,
    isFalse,
    reason: 'a freshly acquired consumer is not suspended',
  );

  putWorkIn(consumer);
  final work = readWork(consumer);

  await consumer.pauseForHigherPriority();
  expect(
    consumer.isActive,
    isTrue,
    reason:
        'pauseForHigherPriority is a pause, not a cancel — isActive must '
        'stay true (ADR 0476 D3)',
  );
  expect(consumer.isSuspended, isTrue);
  expect(
    readWork(consumer),
    work,
    reason: 'pauseForHigherPriority must preserve in-progress work',
  );

  // Idempotent pause.
  await consumer.pauseForHigherPriority();
  expect(consumer.isSuspended, isTrue);
  expect(readWork(consumer), work);

  await consumer.resume();
  expect(consumer.isSuspended, isFalse);
  expect(consumer.isActive, isTrue);
  expect(
    readWork(consumer),
    work,
    reason: 'resume must continue from the preserved state, not restart',
  );

  // Idempotent resume.
  await consumer.resume();
  expect(consumer.isSuspended, isFalse);
  expect(consumer.isActive, isTrue);
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

/// A deliberately non-conformant [ResourceConsumer]: it implements
/// [pauseForHigherPriority] as a `cancel` (discards [state]) instead of a
/// pause — the exact violation the F1 self-guard cell proves
/// [checkResourceConsumerContract] catches.
final class _CancellingFakeConsumer implements ResourceConsumer {
  _CancellingFakeConsumer(this.priority);

  @override
  final ResourcePriority priority;

  String state = '';
  bool _active = false;
  bool _suspended = false;

  @override
  bool get isActive => _active;

  @override
  bool get isSuspended => _suspended;

  @override
  Future<void> acquire() async {
    _active = true;
  }

  @override
  Future<void> release() async {
    _active = false;
    _suspended = false;
  }

  @override
  Future<void> pauseForHigherPriority() async {
    state = ''; // cancel, not pause — deliberately violates ADR 0476 D3.
    _suspended = true;
  }

  @override
  Future<void> resume() async {
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
    expect(
      result.isSuccess,
      isTrue,
      reason: 'the adapter must not silently swallow a BUSY failure (F4)',
    );
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
