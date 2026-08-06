import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../foundation/app_failure.dart';

/// Every state the camera permission can be in.
///
/// `unavailable` is deliberately not a success: a missing or broken platform
/// channel never proves that the camera may be opened.
enum CameraPermissionState {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  unavailable;

  bool get isGranted => this == CameraPermissionState.granted;

  /// The failure this state maps to, or `null` when the permission is granted.
  ///
  /// Retrying only helps after a normal denial. Permanently denied, restricted,
  /// and unavailable states require settings or a working platform channel.
  AppFailure? get failure => switch (this) {
    CameraPermissionState.granted => null,
    CameraPermissionState.denied => const PermissionFailure(
      code: FailureCode.permissionCameraDenied,
    ),
    CameraPermissionState.permanentlyDenied ||
    CameraPermissionState.restricted => const PermissionFailure(
      code: FailureCode.permissionCameraDenied,
      retryable: false,
    ),
    CameraPermissionState.unavailable => const PermissionFailure(
      code: FailureCode.permissionUnavailable,
      retryable: false,
    ),
  };
}

/// The camera states surfaced by the platform-plugin adapter.
///
/// This small type keeps `permission_handler` types out of the gateway
/// contract and lets tests inject a deterministic fake adapter.
enum CameraPermissionPluginState {
  granted,
  limited,
  provisional,
  denied,
  permanentlyDenied,
  restricted,
}

/// Adapter around the platform permission plugin.
///
/// The gateway owns fail-closed error mapping; adapters only expose the plugin
/// result in a local, plugin-independent enum.
abstract interface class CameraPermissionPlugin {
  Future<CameraPermissionPluginState> currentState();

  Future<CameraPermissionPluginState> request();
}

/// Production [CameraPermissionPlugin] backed by `permission_handler`.
final class PermissionHandlerCameraPlugin implements CameraPermissionPlugin {
  const PermissionHandlerCameraPlugin();

  @override
  Future<CameraPermissionPluginState> currentState() async =>
      _map(await Permission.camera.status);

  @override
  Future<CameraPermissionPluginState> request() async =>
      _map(await Permission.camera.request());

  static CameraPermissionPluginState _map(PermissionStatus status) =>
      switch (status) {
        PermissionStatus.granted => CameraPermissionPluginState.granted,
        PermissionStatus.limited => CameraPermissionPluginState.limited,
        PermissionStatus.provisional => CameraPermissionPluginState.provisional,
        PermissionStatus.denied => CameraPermissionPluginState.denied,
        PermissionStatus.permanentlyDenied =>
          CameraPermissionPluginState.permanentlyDenied,
        PermissionStatus.restricted => CameraPermissionPluginState.restricted,
      };
}

/// The only way the app may access the camera permission plugin.
abstract interface class CameraPermissionGateway {
  /// Returns the current state without presenting a system dialog.
  Future<CameraPermissionState> currentState();

  /// Requests permission after an explicit user action.
  Future<CameraPermissionState> request();
}

/// Production camera-permission gateway.
///
/// A missing platform channel or an unexpected adapter error always maps to
/// [CameraPermissionState.unavailable], never to `granted`.
final class PermissionHandlerCameraGateway implements CameraPermissionGateway {
  const PermissionHandlerCameraGateway({
    this.plugin = const PermissionHandlerCameraPlugin(),
  });

  final CameraPermissionPlugin plugin;

  @override
  Future<CameraPermissionState> currentState() => _guard(plugin.currentState);

  @override
  Future<CameraPermissionState> request() => _guard(plugin.request);

  Future<CameraPermissionState> _guard(
    Future<CameraPermissionPluginState> Function() read,
  ) async {
    try {
      return _map(await read());
    } on MissingPluginException {
      return CameraPermissionState.unavailable;
    } on Object {
      return CameraPermissionState.unavailable;
    }
  }

  static CameraPermissionState _map(
    CameraPermissionPluginState state,
  ) => switch (state) {
    CameraPermissionPluginState.granted ||
    CameraPermissionPluginState.limited ||
    CameraPermissionPluginState.provisional => CameraPermissionState.granted,
    CameraPermissionPluginState.denied => CameraPermissionState.denied,
    CameraPermissionPluginState.permanentlyDenied =>
      CameraPermissionState.permanentlyDenied,
    CameraPermissionPluginState.restricted => CameraPermissionState.restricted,
  };
}

/// The camera permission gateway. Tests override this with a fake gateway.
final cameraPermissionGatewayProvider = Provider<CameraPermissionGateway>(
  (_) => const PermissionHandlerCameraGateway(),
);
