import 'package:flutter/widgets.dart';

import '../../platform/app_lifecycle.dart';
import 'audio_session_coordinator.dart';

/// Stops the microphone when the app leaves the foreground (SDD Ch2 Kör 9
/// §9.4).
///
/// Backgrounding revokes the active session, which runs the owner's teardown:
/// the PCM subscription is cancelled and the DSP isolate is killed. Resuming
/// does NOT restart anything — a microphone that turns itself back on while
/// the user is not looking at the screen is exactly what §9.4 forbids.
final class AudioLifecycleGuard {
  AudioLifecycleGuard({required this._coordinator, required this._events}) {
    _events.addListener(_onState);
  }

  final AudioSessionCoordinator _coordinator;
  final AppLifecycleEvents _events;

  void _onState(AppLifecycleState state) {
    if (!isBackgroundLifecycleState(state)) return;
    // Fire-and-forget: the binding callback is synchronous, and the teardown
    // itself is idempotent, so nothing is lost by not awaiting it here.
    _coordinator.revokeActive();
  }

  void dispose() => _events.removeListener(_onState);
}
