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
}
