import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/camera/camera_format.dart';
import 'package:strumsight/core/camera/camera_frame.dart';
import 'package:strumsight/core/camera/camera_frame_binding.dart';
import 'package:strumsight/core/camera/camera_providers.dart';
import 'package:strumsight/core/camera/camera_timestamp.dart';
import 'package:strumsight/core/camera/fake_camera_capture.dart';
import 'package:strumsight/core/camera/plugin_camera_capture.dart';

void main() {
  group('PluginCameraCapture buffer release matrix', () {
    test('processed frame releases its platform buffer exactly once', () async {
      final controller = _FakePlatformCameraController();
      final capture = PluginCameraCapture(
        controllerFactory: () async => controller,
      );
      final releases = <int>[];
      final frames = <int>[];
      final subscription = capture.frames.listen(
        (frame) => frames.add(frame.frameId),
      );
      addTearDown(subscription.cancel);

      await capture.start();
      controller.emit(_frame(1, releases));
      await _flushFrameDelivery();

      expect(frames, <int>[0]);
      expect(releases, <int>[1]);
    });

    test(
      'dropped pending frame and latest delivered frame release exactly once',
      () async {
        final controller = _FakePlatformCameraController();
        final capture = PluginCameraCapture(
          controllerFactory: () async => controller,
        );
        final releases = <int>[];
        final delivered = <int>[];
        final subscription = capture.frames.listen(
          (frame) => delivered.add(frame.byteAt(0)),
        );
        addTearDown(subscription.cancel);

        await capture.start();
        controller.emit(_frame(1, releases));
        controller.emit(_frame(2, releases));
        await _flushFrameDelivery();

        expect(delivered, <int>[2]);
        expect(releases, unorderedEquals(<int>[1, 2]));
        expect(capture.droppedFrameCount, 1);
      },
    );

    test(
      'throwing frame callback still releases the platform buffer once',
      () async {
        final controller = _FakePlatformCameraController();
        final capture = PluginCameraCapture(
          controllerFactory: () async => controller,
        );
        final releases = <int>[];
        final errors = <Object>[];
        final subscription = runZonedGuarded(
          () =>
              capture.frames.listen((_) => throw StateError('consumer failed')),
          (error, _) => errors.add(error),
        );
        addTearDown(subscription!.cancel);

        await capture.start();
        controller.emit(_frame(1, releases));
        await _flushFrameDelivery();

        expect(errors.single, isA<StateError>());
        expect(releases, <int>[1]);
      },
    );

    test(
      'close releases an undelivered platform buffer exactly once',
      () async {
        final controller = _FakePlatformCameraController();
        final capture = PluginCameraCapture(
          controllerFactory: () async => controller,
        );
        final releases = <int>[];

        await capture.start();
        controller.emit(_frame(1, releases));
        await capture.close();
        await _flushFrameDelivery();

        expect(releases, <int>[1]);
        expect(controller.stopCalls, 1);
        expect(controller.disposeCalls, 1);
      },
    );
  });

  test(
    'rapid frames retain only the latest frame and count the drops',
    () async {
      final controller = _FakePlatformCameraController();
      final capture = PluginCameraCapture(
        controllerFactory: () async => controller,
      );
      final delivered = <int>[];
      final subscription = capture.frames.listen(
        (frame) => delivered.add(frame.byteAt(0)),
      );
      addTearDown(subscription.cancel);

      await capture.start();
      for (var byte = 1; byte <= 5; byte += 1) {
        controller.emit(_frame(byte, <int>[]));
      }
      await _flushFrameDelivery();

      expect(delivered, <int>[5]);
      expect(capture.droppedFrameCount, 4);
    },
  );

  test('vision flag off never constructs the platform capture adapter', () {
    var factoryCalls = 0;
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(_config(visionEnabled: false)),
        cameraCaptureFactoryProvider.overrideWithValue(() {
          factoryCalls += 1;
          return FakeCameraCapture();
        }),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(cameraCaptureProvider), isNull);
    expect(factoryCalls, 0);
  });

  test(
    'stop then start reuses the initialized platform camera session',
    () async {
      final controller = _FakePlatformCameraController();
      var factoryCalls = 0;
      final capture = PluginCameraCapture(
        controllerFactory: () async {
          factoryCalls += 1;
          return controller;
        },
      );

      await capture.start();
      await capture.stop();
      await capture.start();

      expect(factoryCalls, 1);
      expect(controller.initializeCalls, 1);
      expect(controller.startCalls, 2);
    },
  );

  test('binding preserves every rotation and mirror metadata combination', () {
    for (final orientation in CameraOrientation.values) {
      for (final mirror in <bool>[false, true]) {
        final bound = CameraFrameBinding.bind(
          _frame(
            9,
            <int>[],
            orientation: orientation,
            mirror: mirror,
            crop: const CameraCrop(left: 1, top: 2, width: 3, height: 4),
          ),
          frameId: 42,
        );

        expect(bound.orientation, orientation);
        expect(bound.mirror, mirror);
        expect(
          bound.crop,
          const CameraCrop(left: 1, top: 2, width: 3, height: 4),
        );
      }
    }
  });
}

Future<void> _flushFrameDelivery() => Future<void>.delayed(Duration.zero);

AppConfig _config({required bool visionEnabled}) => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    visionEnabled: visionEnabled,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

PlatformCameraFrame _frame(
  int byte,
  List<int> releases, {
  CameraOrientation orientation = CameraOrientation.portraitUp,
  bool mirror = false,
  CameraCrop? crop,
}) => PlatformCameraFrame(
  bytes: Uint8List.fromList(<int>[byte]),
  timestamp: CameraTimestamp(byte),
  width: 1,
  height: 1,
  format: CameraPixelFormat.yuv420,
  orientation: orientation,
  mirror: mirror,
  crop: crop,
  release: () => releases.add(byte),
);

final class _FakePlatformCameraController implements PlatformCameraController {
  void Function(PlatformCameraFrame frame)? _onFrame;
  int initializeCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }

  void emit(PlatformCameraFrame frame) => _onFrame!(frame);

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<void> startImageStream(
    void Function(PlatformCameraFrame frame) onFrame,
  ) async {
    startCalls += 1;
    _onFrame = onFrame;
  }

  @override
  Future<void> stopImageStream() async {
    stopCalls += 1;
  }
}
