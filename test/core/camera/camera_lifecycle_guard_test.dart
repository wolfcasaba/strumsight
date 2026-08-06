import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strumsight/core/camera/camera_lifecycle_guard.dart';
import 'package:strumsight/core/camera/camera_providers.dart';
import 'package:strumsight/core/camera/camera_session_coordinator.dart';
import 'package:strumsight/core/camera/camera_session_lease.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/logging/logger_provider.dart';
import 'package:strumsight/core/platform/platform_providers.dart';

import '../../support/fake_audio.dart';

CameraSessionLease _leaseOf(AppResult<CameraSessionLease> result) =>
    (result as Success<CameraSessionLease>).value;

void main() {
  ({
    CameraSessionCoordinator coordinator,
    FakeAppLifecycleEvents lifecycle,
    CameraLifecycleGuard guard,
  })
  rig() {
    final coordinator = CameraSessionCoordinator();
    final lifecycle = FakeAppLifecycleEvents();
    final guard = CameraLifecycleGuard(
      coordinator: coordinator,
      events: lifecycle,
    );
    addTearDown(guard.dispose);
    return (coordinator: coordinator, lifecycle: lifecycle, guard: guard);
  }

  for (final state in const <AppLifecycleState>[
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.detached,
  ]) {
    test('$state revokes the active camera owner', () async {
      final r = rig();
      var teardowns = 0;
      final lease = _leaseOf(
        await r.coordinator.acquire(
          CameraOwner.visionSetup,
          onRevoke: () async => teardowns += 1,
        ),
      );

      r.lifecycle.emit(state);
      await Future<void>.delayed(Duration.zero);

      expect(teardowns, 1);
      expect(lease.isActive, isFalse);
      expect(r.coordinator.activeOwner, isNull);
    });
  }

  for (final state in const <AppLifecycleState>[
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    test('$state neither revokes nor auto-starts the camera', () async {
      final r = rig();
      var teardowns = 0;
      final lease = _leaseOf(
        await r.coordinator.acquire(
          CameraOwner.visionPractice,
          onRevoke: () async => teardowns += 1,
        ),
      );

      r.lifecycle.emit(state);
      await Future<void>.delayed(Duration.zero);

      expect(teardowns, 0);
      expect(lease.isActive, isTrue);
      expect(r.coordinator.activeOwner, CameraOwner.visionPractice);
    });
  }

  test(
    'a disposed guard cannot update camera state after route disposal',
    () async {
      final r = rig();
      var teardowns = 0;
      final lease = _leaseOf(
        await r.coordinator.acquire(
          CameraOwner.labCapture,
          onRevoke: () async => teardowns += 1,
        ),
      );

      r.guard.dispose();
      r.lifecycle.emit(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);

      expect(teardowns, 0);
      expect(lease.isActive, isTrue);
      expect(r.lifecycle.listeners, isEmpty);
    },
  );

  test(
    'the provider-owned guard detaches when its container is disposed',
    () async {
      final lifecycle = FakeAppLifecycleEvents();
      final container = ProviderContainer(
        overrides: [
          appLifecycleEventsProvider.overrideWithValue(lifecycle),
          appLoggerProvider.overrideWithValue(const NoopAppLogger()),
        ],
      );
      final coordinator = container.read(cameraSessionCoordinatorProvider);
      container.read(cameraLifecycleGuardProvider);
      var teardowns = 0;
      final lease = _leaseOf(
        await coordinator.acquire(
          CameraOwner.visionSetup,
          onRevoke: () async => teardowns += 1,
        ),
      );

      container.dispose();
      lifecycle.emit(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);

      expect(teardowns, 0);
      expect(lease.isActive, isTrue);
      expect(lifecycle.listeners, isEmpty);
    },
  );
}
