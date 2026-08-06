import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config/app_config.dart';
import '../logging/logger_provider.dart';
import '../platform/platform_providers.dart';
import 'camera_capture.dart';
import 'camera_lifecycle_guard.dart';
import 'camera_session_coordinator.dart';
import 'plugin_camera_capture.dart';

/// Constructs a fresh platform capture only when the Vision flag permits it.
typedef CameraCaptureFactory = CameraCapture Function();

final cameraCaptureFactoryProvider = Provider<CameraCaptureFactory>(
  (_) => createPlatformCameraCapture,
);

/// Optional production capture boundary for future Vision routes.
///
/// With `visionEnabled` off this returns `null` without constructing an adapter
/// or touching the platform camera plugin.
final cameraCaptureProvider = Provider<CameraCapture?>((ref) {
  if (!ref.watch(appConfigProvider).flags.visionEnabled) {
    return null;
  }
  final capture = ref.watch(cameraCaptureFactoryProvider)();
  ref.onDispose(() => unawaited(capture.close()));
  return capture;
});

/// One camera coordinator per [ProviderScope], enforcing exclusive ownership.
final cameraSessionCoordinatorProvider = Provider<CameraSessionCoordinator>(
  (ref) => CameraSessionCoordinator(logger: ref.watch(appLoggerProvider)),
);

/// Lifecycle guard for the optional camera feature.
///
/// This provider is intentionally not mounted by `StrumSightApp` in E05-R05;
/// a later Vision route owns that explicit integration. Tests and future routes
/// can instantiate it through normal Riverpod lifecycle ownership.
final cameraLifecycleGuardProvider = Provider<CameraLifecycleGuard>((ref) {
  final guard = CameraLifecycleGuard(
    coordinator: ref.watch(cameraSessionCoordinatorProvider),
    events: ref.watch(appLifecycleEventsProvider),
  );
  ref.onDispose(guard.dispose);
  return guard;
});
