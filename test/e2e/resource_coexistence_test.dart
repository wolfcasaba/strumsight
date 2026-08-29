// E12-R15 — A3 (ADR 0476 §0.0 R3): an arbiter-registered camera consumer
// frees the REAL CameraSessionCoordinator after route-leave / backgrounding.
//
// Plain `test()`, deliberately NOT `testWidgets` (round brief §0.0 R6 / L513):
// a broadcast StreamController.close() future never resolves inside the
// `testWidgets` fake-clock zone, so this measures the real coordinator state
// directly instead of walking the full `StrumSightApp` widget tree — nothing
// in this round wires the arbiter to a screen (ADR 0476 consequences), so a
// full-app walk would only re-measure the existing coordinator tests (A6).
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_session_coordinator.dart';
import 'package:strumsight/core/camera/camera_session_lease.dart';
import 'package:strumsight/core/resources/public.dart';

void main() {
  group('A3 — camera lease released after route-leave / backgrounding', () {
    test('route-leave: releasing the arbiter-registered consumer frees the '
        'real CameraSessionCoordinator (no leak)', () async {
      final coordinator = CameraSessionCoordinator();
      final arbiter = ResourceArbiter();
      final consumer = _CameraBackedConsumer(
        coordinator,
        CameraOwner.visionPractice,
      );
      arbiter.register(consumer);

      final decision = await arbiter.request(consumer);
      expect(decision, isA<ResourceGranted>());
      expect(coordinator.activeOwner, CameraOwner.visionPractice);
      expect(consumer.lease!.isActive, isTrue);

      // What a route's dispose() does on leave: release its own lease.
      await consumer.release();

      expect(
        coordinator.activeOwner,
        isNull,
        reason:
            'route-leave must free the coordinator, not just the '
            'consumer wrapper',
      );
      expect(consumer.lease!.isActive, isFalse);
    });

    test('backgrounding: the coordinator revokes the lease directly, '
        'independent of the arbiter', () async {
      final coordinator = CameraSessionCoordinator();
      final arbiter = ResourceArbiter();
      final consumer = _CameraBackedConsumer(
        coordinator,
        CameraOwner.visionSetup,
      );
      arbiter.register(consumer);
      await arbiter.request(consumer);
      expect(coordinator.activeOwner, CameraOwner.visionSetup);

      await coordinator.revokeActive(
        reason: CameraSessionRevocationReason.appBackground,
      );

      expect(
        coordinator.activeOwner,
        isNull,
        reason:
            'app-background revocation is the coordinator\'s own '
            'lifecycle path — the arbiter never had to touch it',
      );
      expect(consumer.lease!.isActive, isFalse);
      expect(
        consumer.isActive,
        isFalse,
        reason: 'the consumer must observe the revoked lease too',
      );
    });
  });
}

/// A [ResourceConsumer] backed by a REAL [CameraSessionCoordinator] lease, so
/// A3 measures the actual coordinator state rather than a mocked channel
/// (round brief §0.0 R3 / L453).
final class _CameraBackedConsumer implements ResourceConsumer {
  _CameraBackedConsumer(this._coordinator, this.owner);

  final CameraSessionCoordinator _coordinator;
  final CameraOwner owner;

  @override
  ResourcePriority get priority => ResourcePriority.cameraFeedback;

  CameraSessionLease? lease;
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
    _suspended = true;
  }

  @override
  Future<void> resume() async {
    _suspended = false;
  }
}
