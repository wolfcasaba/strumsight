import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_permission.dart';
import 'package:strumsight/core/foundation/app_failure.dart';

void main() {
  group('PermissionHandlerCameraGateway', () {
    for (final testCase in _stateCases) {
      test(
        'currentState maps ${testCase.pluginState} to ${testCase.expected}',
        () async {
          final plugin = _FakeCameraPermissionPlugin(
            current: Future.value(testCase.pluginState),
            requested: Future.value(testCase.pluginState),
          );
          final gateway = PermissionHandlerCameraGateway(plugin: plugin);

          expect(await gateway.currentState(), testCase.expected);
          expect(plugin.currentCalls, 1);
          expect(plugin.requestCalls, 0);
        },
      );

      test(
        'request maps ${testCase.pluginState} to ${testCase.expected}',
        () async {
          final plugin = _FakeCameraPermissionPlugin(
            current: Future.value(testCase.pluginState),
            requested: Future.value(testCase.pluginState),
          );
          final gateway = PermissionHandlerCameraGateway(plugin: plugin);

          expect(await gateway.request(), testCase.expected);
          expect(plugin.currentCalls, 0);
          expect(plugin.requestCalls, 1);
        },
      );
    }

    test('a MissingPluginException maps currentState to unavailable', () async {
      final gateway = PermissionHandlerCameraGateway(
        plugin: _FakeCameraPermissionPlugin(
          current: Future<CameraPermissionPluginState>.error(
            MissingPluginException('camera permission channel missing'),
          ),
          requested: Future.value(CameraPermissionPluginState.granted),
        ),
      );

      expect(await gateway.currentState(), CameraPermissionState.unavailable);
    });

    test('a MissingPluginException maps request to unavailable', () async {
      final gateway = PermissionHandlerCameraGateway(
        plugin: _FakeCameraPermissionPlugin(
          current: Future.value(CameraPermissionPluginState.granted),
          requested: Future<CameraPermissionPluginState>.error(
            MissingPluginException('camera permission channel missing'),
          ),
        ),
      );

      expect(await gateway.request(), CameraPermissionState.unavailable);
    });

    test(
      'an unexpected plugin error also fails closed as unavailable',
      () async {
        final gateway = PermissionHandlerCameraGateway(
          plugin: _FakeCameraPermissionPlugin(
            current: Future<CameraPermissionPluginState>.error(
              StateError('bad'),
            ),
            requested: Future.value(CameraPermissionPluginState.granted),
          ),
        );

        expect(await gateway.currentState(), CameraPermissionState.unavailable);
      },
    );
  });

  test('granted is the only state without a failure', () {
    for (final state in CameraPermissionState.values) {
      expect(
        state.failure == null,
        state == CameraPermissionState.granted,
        reason: '$state',
      );
    }
  });

  test(
    'camera permission failures use the camera code and correct retryability',
    () {
      final denied = CameraPermissionState.denied.failure!;
      expect(denied, isA<PermissionFailure>());
      expect(denied.code, FailureCode.permissionCameraDenied);
      expect(denied.retryable, isTrue);

      for (final state in const [
        CameraPermissionState.permanentlyDenied,
        CameraPermissionState.restricted,
      ]) {
        expect(state.failure!.code, FailureCode.permissionCameraDenied);
        expect(state.failure!.retryable, isFalse, reason: '$state');
      }

      final unavailable = CameraPermissionState.unavailable.failure!;
      expect(unavailable.code, FailureCode.permissionUnavailable);
      expect(unavailable.retryable, isFalse);
      expect(CameraPermissionState.unavailable.isGranted, isFalse);
    },
  );
}

final List<_StateCase> _stateCases = [
  const _StateCase(
    CameraPermissionPluginState.granted,
    CameraPermissionState.granted,
  ),
  const _StateCase(
    CameraPermissionPluginState.denied,
    CameraPermissionState.denied,
  ),
  const _StateCase(
    CameraPermissionPluginState.permanentlyDenied,
    CameraPermissionState.permanentlyDenied,
  ),
  const _StateCase(
    CameraPermissionPluginState.restricted,
    CameraPermissionState.restricted,
  ),
  const _StateCase(
    CameraPermissionPluginState.limited,
    CameraPermissionState.granted,
  ),
  const _StateCase(
    CameraPermissionPluginState.provisional,
    CameraPermissionState.granted,
  ),
];

final class _StateCase {
  const _StateCase(this.pluginState, this.expected);

  final CameraPermissionPluginState pluginState;
  final CameraPermissionState expected;
}

final class _FakeCameraPermissionPlugin implements CameraPermissionPlugin {
  _FakeCameraPermissionPlugin({required this.current, required this.requested});

  final Future<CameraPermissionPluginState> current;
  final Future<CameraPermissionPluginState> requested;
  int currentCalls = 0;
  int requestCalls = 0;

  @override
  Future<CameraPermissionPluginState> currentState() {
    currentCalls += 1;
    return current;
  }

  @override
  Future<CameraPermissionPluginState> request() {
    requestCalls += 1;
    return requested;
  }
}
