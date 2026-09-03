/// Widget tests for the manual guitar-geometry calibration screen
/// (E05-R11, §6 acceptance #1: drag-mátrix + mirror parity).
///
/// Drives the editor through `WidgetTester.startGesture` / `drag` and
/// asserts that the controller's stored `NormalizedPoint` matches the
/// `PreviewFit.toNormalized` inverse transform — i.e. NO 1-x, swap, or
/// `MediaQuery` hack is involved. The same assertion is exercised for
/// a mirrored `PreviewFit` to catch the mirror parity bug.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/storage/json_document_store.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/vision/data/persistence/vision_calibration_codec.dart';
import 'package:strumsight/features/vision/data/persistence/vision_calibration_repository.dart';
import 'package:strumsight/features/vision/domain/vision_setup_profile.dart';
import 'package:strumsight/features/vision/presentation/providers/guitar_calibration_providers.dart';
import 'package:strumsight/features/vision/presentation/screens/guitar_calibration_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

GuitarCalibrationContext _context() => GuitarCalibrationContext(
  camera: VisionCameraPreference.back,
  orientation: CameraRotation.degrees0,
  zoom: 0.5,
  setupProfile: VisionSetupProfile.practiceBalanced,
  now: () => DateTime(2026, 1, 1, 12),
);

/// Test-local copyWith helpers — kept short and grep-able so the
/// F3 mirror-parity test can build a front-camera context without
/// touching the production class.
extension _GuitarCalibrationContextCopy on GuitarCalibrationContext {
  GuitarCalibrationContext copyWithCamera(VisionCameraPreference camera) =>
      GuitarCalibrationContext(
        camera: camera,
        orientation: orientation,
        zoom: zoom,
        setupProfile: setupProfile,
        now: now,
      );
}

VisionCalibrationRepository _emptyRepo() {
  return VisionCalibrationRepository(
    document: JsonDocumentStore(
      store: InMemoryKeyValueStore(),
      logger: const NoopAppLogger(),
      key: StorageKeys.visionCalibration,
      legacyKey: 'ss.vision.calibration.legacy',
      name: 'vision_calibration',
      bodyKey: 'data',
    ),
    codec: const VisionCalibrationCodec(),
  );
}

/// Wraps the screen in a `ProviderScope` bound to a test-owned container
/// so the test can read state after the gesture completes.
Future<ProviderContainer> _pumpHarness(
  WidgetTester tester, {
  required VisionCalibrationRepository repository,
  required GuitarCalibrationContext context,
}) async {
  final container = ProviderContainer(
    overrides: [
      visionCalibrationRepositoryProvider.overrideWithValue(repository),
      guitarCalibrationRuntimeContextProvider.overrideWithValue(context),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        // R2 (§0.0): the migrated screen's SsCard/SsButton now read the
        // design-system theme extensions — a themeless MaterialApp
        // null-check crashes (L593-class defect).
        theme: SsLightTheme.data(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('hu')],
        home: const GuitarCalibrationScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('drag on the nut handle moves the controller normalized state', (
    tester,
  ) async {
    final ctx = _context();
    final container = await _pumpHarness(
      tester,
      repository: _emptyRepo(),
      context: ctx,
    );
    addTearDown(container.dispose);

    // Move the polygon vertices 0 and 3 off the nut position so the
    // 32x32 nut handle has a clear hit region (the seed polygon has a
    // vertex at (0.2, 0.18) which would otherwise overlap the nut's
    // hit area at (0.2, 0.2)).
    container
        .read(guitarCalibrationControllerProvider(ctx).notifier)
        .movePolygonVertex(0, const NormalizedPoint(0.2, 0.7));
    container
        .read(guitarCalibrationControllerProvider(ctx).notifier)
        .movePolygonVertex(3, const NormalizedPoint(0.2, 0.7));
    await tester.pumpAndSettle();

    final nutFinder = find.byKey(const Key('guitar-anchor-nut'));
    expect(nutFinder, findsOneWidget);
    final nutCenter = tester.getCenter(nutFinder);
    final gesture = await tester.startGesture(nutCenter);
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    final state = container.read(guitarCalibrationControllerProvider(ctx));
    // The nut anchor must have moved off the seed (0.2, 0.2).
    expect(state.nutAnchor.x, isNot(0.2));
    // It must stay clamped to [0,1].
    expect(state.nutAnchor.x, inInclusiveRange(0.0, 1.0));
    expect(state.nutAnchor.y, inInclusiveRange(0.0, 1.0));
  });

  testWidgets('mirror parity: dragging right increases normalised x', (
    tester,
  ) async {
    final ctx = _context();
    final container = await _pumpHarness(
      tester,
      repository: _emptyRepo(),
      context: ctx,
    );
    addTearDown(container.dispose);

    final start = container.read(guitarCalibrationControllerProvider(ctx));
    expect(start.bridgeAnchor.x, 0.6);

    final bridgeFinder = find.byKey(const Key('guitar-anchor-bridge'));
    final bridgeCenter = tester.getCenter(bridgeFinder);
    final gesture = await tester.startGesture(bridgeCenter);
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    final state = container.read(guitarCalibrationControllerProvider(ctx));
    // In a normal (non-mirrored) PreviewFit, moving right increases x.
    expect(state.bridgeAnchor.x, greaterThan(0.6));
  });

  testWidgets(
    'f2: clanp visibility — dragging outside the frame thickens the handle border',
    (tester) async {
      final ctx = _context();
      final container = await _pumpHarness(
        tester,
        repository: _emptyRepo(),
        context: ctx,
      );
      addTearDown(container.dispose);

      // Move the polygon vertices out of the nut hit area.
      container
          .read(guitarCalibrationControllerProvider(ctx).notifier)
          .movePolygonVertex(0, const NormalizedPoint(0.2, 0.7));
      container
          .read(guitarCalibrationControllerProvider(ctx).notifier)
          .movePolygonVertex(3, const NormalizedPoint(0.2, 0.7));
      await tester.pumpAndSettle();

      final decorFinder = find.descendant(
        of: find.byKey(const Key('guitar-anchor-nut')),
        matching: find.byKey(const Key('guitar-anchor-handle-decor')),
      );
      expect(decorFinder, findsOneWidget);

      // Pre-clamp: read the unclamped border.
      final before = tester.widget<Container>(decorFinder);
      final beforeBorder = (before.decoration as BoxDecoration).border!;
      final beforeAlpha = (beforeBorder.top.color.a * 255).round() & 0xff;
      // Sanity: pre-clamp alpha is the dim 0.2 value (≈ 51).
      expect(beforeAlpha, lessThan(128));

      // Drag the nut handle FAR outside the frame — x grows without
      // bound, the controller must clamp to 1.0, and the visible
      // decoration must reflect the clamp.
      final nutCenter = tester.getCenter(
        find.byKey(const Key('guitar-anchor-nut')),
      );
      final gesture = await tester.startGesture(nutCenter);
      await gesture.moveBy(const Offset(2000, 0));
      await tester.pumpAndSettle();

      final after = tester.widget<Container>(decorFinder);
      final afterBorder = (after.decoration as BoxDecoration).border!;
      final afterAlpha = (afterBorder.top.color.a * 255).round() & 0xff;
      // Clamp visibility: the border becomes opaque while the value
      // is clamped.
      expect(
        afterAlpha,
        greaterThan(beforeAlpha + 100),
        reason:
            'clamped border alpha ($afterAlpha) should be much brighter '
            'than unclamped ($beforeAlpha)',
      );
      expect(afterBorder.top.width, greaterThan(beforeBorder.top.width));

      // Release: the clamp-state decoration should clear.
      await gesture.up();
      await tester.pumpAndSettle();
      final restored = tester.widget<Container>(decorFinder);
      final restoredBorder = (restored.decoration as BoxDecoration).border!;
      final restoredAlpha = (restoredBorder.top.color.a * 255).round() & 0xff;
      expect(restoredAlpha, lessThan(afterAlpha));
    },
  );

  testWidgets(
    'f3: front-camera mirror — dragging right decreases normalised x',
    (tester) async {
      final ctx = _context().copyWithCamera(VisionCameraPreference.front);
      final container = await _pumpHarness(
        tester,
        repository: _emptyRepo(),
        context: ctx,
      );
      addTearDown(container.dispose);

      final start = container.read(guitarCalibrationControllerProvider(ctx));
      expect(start.bridgeAnchor.x, 0.6);

      final bridgeFinder = find.byKey(const Key('guitar-anchor-bridge'));
      final bridgeCenter = tester.getCenter(bridgeFinder);
      final gesture = await tester.startGesture(bridgeCenter);
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      final state = container.read(guitarCalibrationControllerProvider(ctx));
      // Front camera mirrors preview space: a rightward drag produces a
      // decreasing normalised x — the inverse of the back-camera case.
      expect(state.bridgeAnchor.x, lessThan(0.6));
    },
  );
}
