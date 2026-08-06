import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/logger_provider.dart';
import '../platform/platform_providers.dart';
import 'camera_lifecycle_guard.dart';
import 'camera_session_coordinator.dart';

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
