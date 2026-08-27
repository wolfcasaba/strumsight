// Golden snapshots of the E13-R30 Vision Setup, Vision Coach Stage and
// Vision Result screens at a compact portrait phone (412×915) and the same
// frame at textScaler 2.0, per the round brief §7/A9. Pattern follows the
// merged `test/ui/goldens/e13_r29_screens_golden_test.dart` precedent:
// `AppTheme` (the app's actual runtime theme), not `SsLightTheme`/
// `SsDarkTheme` directly — the Result screen instead wraps itself in a
// local `VisionThemeScope` (mirrors `library_theme_scope.dart`'s measured
// fix) because `AppTheme` alone does not carry the design-system's
// `SsColorScheme`/`SsTypography` extensions its cards need.
//
// Recorded on x86_64 (ADR 0426, §0.0/B6) via `tools/golden-x86.sh record` —
// NOT `flutter test --update-goldens` on this (aarch64) box.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_permission.dart';
import 'package:strumsight/core/camera/camera_providers.dart';
import 'package:strumsight/core/camera/camera_session_coordinator.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/vision/application/calibration_loss_machine.dart';
import 'package:strumsight/features/vision/application/vision_session_controller.dart';
import 'package:strumsight/features/vision/application/vision_session_state.dart';
import 'package:strumsight/features/vision/domain/feedback/insight_code.dart';
import 'package:strumsight/features/vision/domain/quality/vision_frame_quality.dart';
import 'package:strumsight/features/vision/domain/quality/vision_quality_summary.dart';
import 'package:strumsight/features/vision/domain/vision_session.dart';
import 'package:strumsight/features/vision/domain/vision_session_result.dart';
import 'package:strumsight/features/vision/presentation/screens/vision_result_screen.dart';
import 'package:strumsight/features/vision/presentation/screens/vision_session_screen.dart';
import 'package:strumsight/features/vision/presentation/screens/vision_setup_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../core/storage/in_memory_key_value_store.dart';

const _compactPortrait = Size(412, 915);

final class _DeniedPermissionGateway implements CameraPermissionGateway {
  @override
  Future<CameraPermissionState> currentState() async =>
      CameraPermissionState.denied;

  @override
  Future<CameraPermissionState> request() async => CameraPermissionState.denied;
}

final class _SeededVisionSessionController extends VisionSessionController {
  @override
  VisionSessionState build() => VisionSessionState.idle().copyWith(
    status: VisionSessionStatus.running,
    qualitySummary: VisionQualitySummary.fromFrames(const []),
    overlayQuality: const VisionOverlayQuality(
      hand: VisionMetricState.good,
      pose: VisionMetricState.needsImprovement,
      guitar: CalibrationLossState.tracking,
    ),
    calibrationState: CalibrationLossState.tracking,
    realtimeCue: VisionInsight(
      code: InsightCode.pickingFocus,
      policyVersion: 'e05-r23-v1',
      evidenceIds: const <String>['evidence-1'],
      confidence: 0.9,
    ),
  );
}

VisionSessionResult _goldenResult() => VisionSessionResult(
  session: VisionSession(
    id: VisionSessionId.create('golden-session'),
    startedAt: DateTime.utc(2026, 8, 27, 12),
  ),
  endedAt: DateTime.utc(2026, 8, 27, 12, 8),
  endReason: VisionSessionEndReason.explicitStop,
  qualitySummary: VisionQualitySummary.fromFrames(const []),
  calibrationState: CalibrationLossState.tracking,
  sessionSummary: <VisionInsight>[
    VisionInsight(
      code: InsightCode.frettingStable,
      policyVersion: 'e05-r23-v1',
      evidenceIds: const <String>['evidence-1'],
      confidence: 0.9,
    ),
    VisionInsight(
      code: InsightCode.postureFocus,
      policyVersion: 'e05-r23-v1',
      evidenceIds: const <String>['evidence-2'],
      confidence: 0.3,
    ),
  ],
  observedFrameCount: 480,
);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const <Override>[],
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expectGolden(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/$name.png'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final textScale in [1.0, 2.0]) {
    final suffix = textScale == 1.0 ? 'compact' : 'compact_scale2';

    testWidgets('vision setup — $suffix', (tester) async {
      await _pump(
        tester,
        const VisionSetupScreen(),
        overrides: [
          cameraPermissionGatewayProvider.overrideWithValue(
            _DeniedPermissionGateway(),
          ),
          cameraSessionCoordinatorProvider.overrideWithValue(
            CameraSessionCoordinator(),
          ),
          keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        ],
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r30_vision_setup_$suffix');
    });

    testWidgets('vision coach stage — $suffix', (tester) async {
      await _pump(
        tester,
        const VisionSessionScreen(),
        overrides: [
          visionSessionControllerProvider.overrideWith(
            _SeededVisionSessionController.new,
          ),
          cameraSessionCoordinatorProvider.overrideWithValue(
            CameraSessionCoordinator(),
          ),
          keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        ],
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r30_vision_coach_stage_$suffix');
    });

    testWidgets('vision result — $suffix', (tester) async {
      await _pump(
        tester,
        VisionResultScreen(
          result: _goldenResult(),
          onStartCorrectivePractice: () {},
        ),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r30_vision_result_$suffix');
    });
  }
}
