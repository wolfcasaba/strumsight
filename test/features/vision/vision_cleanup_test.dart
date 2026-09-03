// E13-R30 acceptance A7: the camera (and, where acquired, the microphone)
// are released on every exit path — explicit stop, leaving the route,
// backgrounding, and process/provider teardown. See
// docs/rounds/e13-r30-vision-ui.md §6.
//
// Every path below ends in `VisionSessionController._finalizeOnce`, which
// closes the `FakeCameraCapture`'s broadcast stream controller. Under
// `testWidgets`'s fake clock that resolution needs real event-loop turns —
// measured: the identical call resolves instantly in a plain `test()`, but
// hangs indefinitely under `testWidgets` without `tester.runAsync`. Some of
// these paths (backgrounding, container disposal) are also `unawaited` by
// the controller itself, so `_runRealAndSettle` gives any detached
// continuation real turns to finish, not just one.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_permission.dart';
import 'package:strumsight/core/camera/camera_providers.dart';
import 'package:strumsight/core/camera/camera_session_coordinator.dart';
import 'package:strumsight/core/camera/fake_camera_capture.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/platform/app_lifecycle.dart';
import 'package:strumsight/core/platform/platform_providers.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/vision/application/vision_session_controller.dart';
import 'package:strumsight/features/vision/domain/vision_session.dart';
import 'package:strumsight/features/vision/presentation/screens/vision_session_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../core/storage/in_memory_key_value_store.dart';

final class _PermissionGateway implements CameraPermissionGateway {
  @override
  Future<CameraPermissionState> currentState() async =>
      CameraPermissionState.granted;

  @override
  Future<CameraPermissionState> request() async =>
      CameraPermissionState.granted;
}

final class _FakeLifecycleEvents implements AppLifecycleEvents {
  final List<void Function(AppLifecycleState)> _listeners =
      <void Function(AppLifecycleState)>[];
  bool disposed = false;

  @override
  void addListener(void Function(AppLifecycleState state) listener) =>
      _listeners.add(listener);

  @override
  void removeListener(void Function(AppLifecycleState state) listener) =>
      _listeners.remove(listener);

  @override
  void dispose() => disposed = true;

  void emit(AppLifecycleState state) {
    for (final listener in List.of(_listeners)) {
      listener(state);
    }
  }
}

// R2 (§0.0, extended measurement): VisionSessionScreen now reads the
// design-system theme extensions via its migrated SsButton/SsSwitchRow — a
// themeless MaterialApp null-check crashes (L593-class defect).
Widget _host(Widget child) => MaterialApp(
  theme: SsLightTheme.data(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

final class _Rig {
  _Rig(this.container, this.capture, this.coordinator, this.lifecycle);

  final ProviderContainer container;
  final FakeCameraCapture capture;
  final CameraSessionCoordinator coordinator;
  final _FakeLifecycleEvents lifecycle;

  VisionSessionController get controller =>
      container.read(visionSessionControllerProvider.notifier);

  void dispose() => container.dispose();
}

_Rig _rig() {
  final capture = FakeCameraCapture();
  final coordinator = CameraSessionCoordinator();
  final lifecycle = _FakeLifecycleEvents();
  final container = ProviderContainer(
    overrides: [
      cameraPermissionGatewayProvider.overrideWithValue(_PermissionGateway()),
      cameraCaptureFactoryProvider.overrideWithValue(() => capture),
      cameraSessionCoordinatorProvider.overrideWithValue(coordinator),
      appLifecycleEventsProvider.overrideWithValue(lifecycle),
      keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
      visionSessionClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 8, 27, 12),
      ),
      visionSessionIdFactoryProvider.overrideWithValue(
        () => VisionSessionId.create('cleanup-test-session'),
      ),
    ],
  );
  container.listen(visionSessionControllerProvider, (_, _) {});
  return _Rig(container, capture, coordinator, lifecycle);
}

Future<void> _reachRunning(WidgetTester tester, _Rig rig) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: rig.container,
      child: _host(const VisionSessionScreen()),
    ),
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('vision-session-begin')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('vision-session-calibrate')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('vision-session-start')));
  await tester.pumpAndSettle();
  expect(rig.capture.startCalls, 1);
}

/// Runs [action] (which may leave detached/`unawaited` continuations behind,
/// e.g. a lifecycle-revoke or a provider disposal) in a real event-loop zone
/// and gives those continuations real turns to finish before returning.
Future<void> _runRealAndSettle(
  WidgetTester tester,
  FutureOr<void> Function() action,
) async {
  await tester.runAsync(() async {
    await action();
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  });
  await tester.pump();
}

void main() {
  group('A7 — the camera is released on every exit path', () {
    testWidgets('explicit stop releases the capture and the lease', (
      tester,
    ) async {
      final rig = _rig();
      addTearDown(rig.dispose);
      await _reachRunning(tester, rig);

      await _runRealAndSettle(tester, rig.controller.stop);

      expect(rig.capture.isClosed, isTrue);
      expect(rig.coordinator.activeOwner, isNull);
    });

    testWidgets('leaving the route without an explicit stop still releases', (
      tester,
    ) async {
      final rig = _rig();
      addTearDown(rig.dispose);
      await _reachRunning(tester, rig);

      await _runRealAndSettle(tester, rig.controller.leaveRoute);

      expect(rig.capture.isClosed, isTrue);
      expect(rig.coordinator.activeOwner, isNull);
    });

    testWidgets(
      'the app going to the background revokes and releases the camera',
      (tester) async {
        final rig = _rig();
        addTearDown(rig.dispose);
        await _reachRunning(tester, rig);

        await _runRealAndSettle(
          tester,
          () => rig.lifecycle.emit(AppLifecycleState.paused),
        );

        expect(rig.capture.isClosed, isTrue);
        expect(rig.coordinator.activeOwner, isNull);
      },
    );

    testWidgets(
      'a transient system overlay (inactive) does NOT release the camera',
      (tester) async {
        final rig = _rig();
        addTearDown(rig.dispose);
        await _reachRunning(tester, rig);

        await _runRealAndSettle(
          tester,
          () => rig.lifecycle.emit(AppLifecycleState.inactive),
        );

        expect(rig.capture.isClosed, isFalse);
        expect(rig.coordinator.activeOwner, isNotNull);
      },
    );

    testWidgets('provider/process teardown while running still releases', (
      tester,
    ) async {
      final rig = _rig();
      await _reachRunning(tester, rig);

      await _runRealAndSettle(tester, rig.dispose);

      expect(rig.capture.isClosed, isTrue);
      expect(rig.coordinator.activeOwner, isNull);
    });
  });

  group(
    'A7 — the microphone (where any Vision-adjacent path would acquire one)',
    () {
      test('neither the session nor the setup controller acquires a '
          'microphone lease — measured, §0.0/B2: the only other `.acquire(` '
          'caller in `lib/` is `core/audio/mic_capture.dart`, unrelated to '
          'Vision — so there is nothing for Vision to release here', () {
        final sessionSource = File(
          'lib/features/vision/application/vision_session_controller.dart',
        ).readAsStringSync();
        final setupSource = File(
          'lib/features/vision/application/vision_setup_controller.dart',
        ).readAsStringSync();

        for (final source in [sessionSource, setupSource]) {
          expect(source.contains('MicCapture'), isFalse);
          expect(source.contains('AudioSessionCoordinator'), isFalse);
        }
      });
    },
  );
}
