// E09-R28a: the session screen finally shows what the camera sees.
//
// Before this round `grep CameraPreview lib/` had zero hits: the session
// opened a real CameraX lease and rendered a flat `surfaceSunken` rectangle,
// so even a perfect pipeline would have looked broken. The preview is exposed
// as a nullable provider only a capture adapter owning a real platform
// texture can satisfy — which is why the pinned Vision goldens (and every
// widget test) keep rendering the identical inert box.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_frame.dart';
import 'package:strumsight/core/camera/camera_permission.dart';
import 'package:strumsight/core/camera/camera_providers.dart';
import 'package:strumsight/core/camera/camera_session_coordinator.dart';
import 'package:strumsight/core/camera/fake_camera_capture.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/vision/application/calibration_loss_machine.dart';
import 'package:strumsight/features/vision/application/vision_pipeline_providers.dart';
import 'package:strumsight/features/vision/application/vision_session_controller.dart';
import 'package:strumsight/features/vision/application/vision_session_state.dart';
import 'package:strumsight/features/vision/data/pipeline/vision_frame_pipeline.dart';
import 'package:strumsight/features/vision/domain/quality/vision_frame_quality.dart';
import 'package:strumsight/features/vision/domain/quality/vision_quality_summary.dart';
import 'package:strumsight/features/vision/presentation/overlays/vision_preview_overlay.dart';
import 'package:strumsight/features/vision/presentation/providers/vision_preview_providers.dart';
import 'package:strumsight/features/vision/presentation/screens/vision_session_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

const Key _previewKey = Key('test-camera-preview');
const Key _stackKey = Key('vision-preview-stack');

final class _GrantedGateway implements CameraPermissionGateway {
  @override
  Future<CameraPermissionState> currentState() async =>
      CameraPermissionState.granted;

  @override
  Future<CameraPermissionState> request() async =>
      CameraPermissionState.granted;
}

final class _DeniedGateway implements CameraPermissionGateway {
  @override
  Future<CameraPermissionState> currentState() async =>
      CameraPermissionState.denied;

  @override
  Future<CameraPermissionState> request() async => CameraPermissionState.denied;
}

final class _SeededController extends VisionSessionController {
  _SeededController(this.initialStatus);

  final VisionSessionStatus initialStatus;

  @override
  VisionSessionState build() => VisionSessionState.idle().copyWith(
    status: initialStatus,
    qualitySummary: VisionQualitySummary.fromFrames(const []),
    overlayQuality: const VisionOverlayQuality(
      hand: VisionMetricState.notObservable,
      pose: VisionMetricState.notObservable,
      guitar: CalibrationLossState.tracking,
    ),
  );
}

/// A processor that measures nothing: these cells are about the preview seam.
final class _InertProcessor implements VisionFrameProcessor {
  final StreamController<VisionPipelineUpdate> _updates =
      StreamController<VisionPipelineUpdate>.broadcast();

  @override
  Stream<VisionPipelineUpdate> get updates => _updates.stream;

  @override
  void onFrame(CameraFrame frame) {}

  @override
  void reset() {}

  @override
  Future<void> dispose() => _updates.close();
}

Widget _host(Widget child) => MaterialApp(
  theme: SsLightTheme.data(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required VisionSessionStatus status,
  VisionPreviewBuilder? preview,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        cameraSessionCoordinatorProvider.overrideWithValue(
          CameraSessionCoordinator(),
        ),
        visionSessionControllerProvider.overrideWith(
          () => _SeededController(status),
        ),
        if (preview != null)
          visionPreviewBuilderProvider.overrideWithValue(preview),
      ],
      child: _host(const VisionSessionScreen()),
    ),
  );
  await tester.pump();
}

ProviderContainer _sessionContainer() {
  final container = ProviderContainer(
    overrides: [
      keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
      cameraPermissionGatewayProvider.overrideWithValue(_GrantedGateway()),
      cameraCaptureFactoryProvider.overrideWithValue(() => FakeCameraCapture()),
      cameraSessionCoordinatorProvider.overrideWithValue(
        CameraSessionCoordinator(),
      ),
      visionFrameProcessorFactoryProvider.overrideWithValue(
        () => _InertProcessor(),
      ),
    ],
  );
  container.listen(visionSessionControllerProvider, (_, _) {});
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('visionPreviewBuilderProvider', () {
    test('is null before the session is running', () {
      final container = _sessionContainer();

      expect(container.read(visionPreviewBuilderProvider), isNull);
    });

    test('is null while a session runs on a plugin-free capture', () async {
      final container = _sessionContainer();
      final controller = container.read(
        visionSessionControllerProvider.notifier,
      );

      await controller.begin();
      controller.beginCalibration();
      await controller.start();

      expect(
        container.read(visionSessionControllerProvider).status,
        VisionSessionStatus.running,
      );
      // `FakeCameraCapture` is a plain `CameraCapture`: it owns no platform
      // texture and therefore cannot answer with a preview.
      expect(controller.previewSource, isNull);
      expect(container.read(visionPreviewBuilderProvider), isNull);
    });

    test('stays null when permission is denied', () async {
      final container = ProviderContainer(
        overrides: [
          keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
          cameraPermissionGatewayProvider.overrideWithValue(_DeniedGateway()),
          cameraSessionCoordinatorProvider.overrideWithValue(
            CameraSessionCoordinator(),
          ),
        ],
      );
      container.listen(visionSessionControllerProvider, (_, _) {});
      addTearDown(container.dispose);

      await container.read(visionSessionControllerProvider.notifier).begin();

      expect(
        container.read(visionSessionControllerProvider).status,
        VisionSessionStatus.permissionDenied,
      );
      expect(container.read(visionPreviewBuilderProvider), isNull);
    });
  });

  group('mirrorVisionPreview', () {
    test('a back lens is drawn unchanged', () {
      const preview = SizedBox(key: _previewKey);

      expect(mirrorVisionPreview(preview, mirror: false), same(preview));
    });

    testWidgets('a front lens is flipped horizontally', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: mirrorVisionPreview(
            const SizedBox(key: _previewKey),
            mirror: true,
          ),
        ),
      );

      // A front sensor delivers the scene reversed; unmirrored, the player's
      // fretting hand appears on the wrong side of the neck.
      final transform = tester.widget<Transform>(find.byType(Transform));
      expect(transform.transform.storage[0], -1);
      expect(find.byKey(_previewKey), findsOneWidget);
    });
  });

  group('VisionSessionScreen preview composition', () {
    testWidgets('renders no preview when the provider has none', (
      tester,
    ) async {
      await _pumpScreen(tester, status: VisionSessionStatus.running);

      expect(find.byKey(_previewKey), findsNothing);
      expect(find.byKey(_stackKey), findsNothing);
      expect(find.byType(VisionPreviewOverlay), findsOneWidget);
    });

    testWidgets('draws the preview behind the overlay', (tester) async {
      await _pumpScreen(
        tester,
        status: VisionSessionStatus.running,
        preview: () => const ColoredBox(key: _previewKey, color: Colors.black),
      );

      expect(find.byKey(_previewKey), findsOneWidget);
      expect(find.byType(VisionPreviewOverlay), findsOneWidget);
      final stack = tester.widget<Stack>(find.byKey(_stackKey));
      expect(stack.children.first.key, _previewKey);
      expect(stack.children.last, isA<VisionPreviewOverlay>());
    });

    testWidgets('a builder that yields nothing keeps the inert box', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        status: VisionSessionStatus.running,
        preview: () => null,
      );

      expect(find.byKey(_stackKey), findsNothing);
      expect(find.byType(VisionPreviewOverlay), findsOneWidget);
    });
  });
}
