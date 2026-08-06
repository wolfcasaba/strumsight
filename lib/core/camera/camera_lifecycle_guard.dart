import 'package:flutter/widgets.dart';

import '../platform/app_lifecycle.dart';
import 'camera_session_coordinator.dart';
import 'camera_session_lease.dart';

/// Revokes the camera when the app leaves the foreground.
///
/// The guard deliberately does nothing for `inactive` and `resumed`: a
/// transient system overlay must not stop a session, and resuming must never
/// turn the camera back on without an explicit user action.
final class CameraLifecycleGuard {
  CameraLifecycleGuard({required this._coordinator, required this._events}) {
    _events.addListener(_onState);
  }

  final CameraSessionCoordinator _coordinator;
  final AppLifecycleEvents _events;

  void _onState(AppLifecycleState state) {
    if (!isBackgroundLifecycleState(state)) return;
    _coordinator.revokeActive(
      reason: CameraSessionRevocationReason.appBackground,
    );
  }

  void dispose() => _events.removeListener(_onState);
}
