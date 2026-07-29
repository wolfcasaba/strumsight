import 'package:flutter/services.dart' show MissingPluginException;
import 'package:permission_handler/permission_handler.dart';

import '../foundation/app_failure.dart';

/// Every state the microphone permission can be in (SDD Ch2, Kör 9 §9.1).
///
/// `unavailable` is deliberately NOT a success: a missing or broken permission
/// channel means we do not KNOW that we may record, and a silent "granted" is
/// exactly the no-op class this app refuses to ship.
enum MicrophonePermissionState {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  unavailable;

  bool get isGranted => this == MicrophonePermissionState.granted;

  /// The failure this state maps to, or `null` when it is [granted].
  ///
  /// `retryable` answers one question only: can showing the system dialog
  /// again help? Permanently denied / restricted / unavailable need a trip to
  /// the system settings (or a working platform channel) first.
  AppFailure? get failure => switch (this) {
    MicrophonePermissionState.granted => null,
    MicrophonePermissionState.denied => const PermissionFailure(
      code: FailureCode.permissionMicrophoneDenied,
    ),
    MicrophonePermissionState.permanentlyDenied ||
    MicrophonePermissionState.restricted => const PermissionFailure(
      code: FailureCode.permissionMicrophoneDenied,
      retryable: false,
    ),
    MicrophonePermissionState.unavailable => const PermissionFailure(
      code: FailureCode.permissionUnavailable,
      retryable: false,
    ),
  };
}

/// The ONLY way the app may touch the microphone permission plugin (§9.1).
///
/// UI, engines and providers depend on this interface; tests inject a fake
/// instead of installing platform-channel mocks.
abstract interface class MicrophonePermissionGateway {
  /// The current state — never shows a dialog.
  Future<MicrophonePermissionState> currentState();

  /// The state after asking the user (shows the system dialog if it can).
  Future<MicrophonePermissionState> request();
}

/// The real gateway, backed by `permission_handler`.
///
/// A plugin error (no channel, platform exception) maps to
/// [MicrophonePermissionState.unavailable] — never to `granted`. This is the
/// production rule from §9.1: an unknown permission state must not open the
/// microphone.
final class PermissionHandlerMicrophoneGateway
    implements MicrophonePermissionGateway {
  const PermissionHandlerMicrophoneGateway();

  @override
  Future<MicrophonePermissionState> currentState() =>
      _guard(() => Permission.microphone.status);

  @override
  Future<MicrophonePermissionState> request() =>
      _guard(() => Permission.microphone.request());

  Future<MicrophonePermissionState> _guard(
    Future<PermissionStatus> Function() read,
  ) async {
    try {
      return _map(await read());
    } on MissingPluginException {
      return MicrophonePermissionState.unavailable;
    } catch (_) {
      return MicrophonePermissionState.unavailable;
    }
  }

  static MicrophonePermissionState _map(PermissionStatus status) =>
      switch (status) {
        PermissionStatus.granted ||
        PermissionStatus.limited ||
        PermissionStatus.provisional => MicrophonePermissionState.granted,
        PermissionStatus.permanentlyDenied =>
          MicrophonePermissionState.permanentlyDenied,
        PermissionStatus.restricted => MicrophonePermissionState.restricted,
        PermissionStatus.denied => MicrophonePermissionState.denied,
      };
}
