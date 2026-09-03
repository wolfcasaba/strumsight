// E13-R30 acceptance: A3 (the Stage shows exactly one priority cue — the
// zero/one/three-simultaneous threshold matrix from the round brief's §6.1)
// and A8 (the debug skeleton is labor-only, unavailable on the production
// route). See docs/rounds/e13-r30-vision-ui.md.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/camera/camera_permission.dart';
import 'package:strumsight/core/camera/camera_providers.dart';
import 'package:strumsight/core/camera/camera_session_coordinator.dart';
import 'package:strumsight/core/camera/fake_camera_capture.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/vision/application/vision_session_controller.dart';
import 'package:strumsight/features/vision/domain/feedback/cue_budget.dart';
import 'package:strumsight/features/vision/domain/feedback/insight_code.dart';
import 'package:strumsight/features/vision/domain/vision_session.dart';
import 'package:strumsight/features/vision/presentation/screens/vision_session_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../core/storage/in_memory_key_value_store.dart';

final class _PermissionGateway implements CameraPermissionGateway {
  @override
  Future<CameraPermissionState> currentState() async =>
      CameraPermissionState.granted;

  @override
  Future<CameraPermissionState> request() async =>
      CameraPermissionState.granted;
}

// R2 (§0.0): the migrated screen's SsButton/SsSwitchRow now read the
// design-system theme extensions — a themeless MaterialApp null-check
// crashes (L593-class defect).
Widget _host(Widget child) => MaterialApp(
  theme: SsLightTheme.data(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

AppConfig _config({required bool labModeAvailable}) => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: labModeAvailable,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

final class _Rig {
  _Rig(this.container, this.capture);

  final ProviderContainer container;
  final FakeCameraCapture capture;

  VisionSessionController get controller =>
      container.read(visionSessionControllerProvider.notifier);

  void dispose() => container.dispose();
}

_Rig _rig({bool labModeAvailable = false, bool labModeOn = false}) {
  final capture = FakeCameraCapture();
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        _config(labModeAvailable: labModeAvailable),
      ),
      cameraPermissionGatewayProvider.overrideWithValue(_PermissionGateway()),
      cameraCaptureFactoryProvider.overrideWithValue(() => capture),
      cameraSessionCoordinatorProvider.overrideWithValue(
        CameraSessionCoordinator(),
      ),
      keyValueStoreProvider.overrideWithValue(
        InMemoryKeyValueStore(<String, Object>{StorageKeys.labMode: labModeOn}),
      ),
      visionSessionClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 8, 27, 12),
      ),
      visionSessionIdFactoryProvider.overrideWithValue(
        () => VisionSessionId.create('one-cue-test-session'),
      ),
    ],
  );
  container.listen(visionSessionControllerProvider, (_, _) {});
  return _Rig(container, capture);
}

Future<void> _reachRunning(WidgetTester tester, _Rig rig) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: rig.container,
      child: _host(const VisionSessionScreen()),
    ),
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('vision-session-begin')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('vision-session-calibrate')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('vision-session-start')));
  await tester.pumpAndSettle();
}

VisionInsight _insight(InsightCode code, double confidence) => VisionInsight(
  code: code,
  policyVersion: 'e05-r23-v1',
  evidenceIds: const <String>['evidence-1'],
  confidence: confidence,
);

void main() {
  group('A3 — exactly one priority cue at a time', () {
    testWidgets('no finding → the Stage shows zero cues', (tester) async {
      final rig = _rig();
      addTearDown(rig.dispose);
      await _reachRunning(tester, rig);

      rig.controller.reportRealtimeCue(null);
      await tester.pump();

      expect(find.byKey(const Key('vision-realtime-cue')), findsNothing);
    });

    testWidgets('exactly one finding → the Stage shows that one cue', (
      tester,
    ) async {
      final rig = _rig();
      addTearDown(rig.dispose);
      await _reachRunning(tester, rig);

      final only = _insight(InsightCode.pickingStable, 0.9);
      rig.controller.reportRealtimeCue(only);
      await tester.pump();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(VisionSessionScreen)),
      );
      expect(find.byKey(const Key('vision-realtime-cue')), findsOneWidget);
      expect(find.text(l10n.visionInsightPickingStable), findsOneWidget);
    });

    testWidgets('three simultaneous findings → the Stage shows only the '
        "domain's highest-priority selection, never all three", (tester) async {
      final rig = _rig();
      addTearDown(rig.dispose);
      await _reachRunning(tester, rig);

      // Priority ties at 50 (FeedbackPolicies), so the tie-break is
      // confidence, then direction, then code — postureFocus (0.95) beats
      // the two 0.90 candidates (measured against
      // `domain/feedback/cue_budget.dart`, read-only in this round).
      final frettingFocus = _insight(InsightCode.frettingFocus, 0.9);
      final pickingStable = _insight(InsightCode.pickingStable, 0.9);
      final postureFocus = _insight(InsightCode.postureFocus, 0.95);
      final budget = CueBudget(now: () => DateTime.utc(2026, 8, 27, 12));
      final selected = budget.selectRealtime(<VisionInsight>[
        frettingFocus,
        pickingStable,
        postureFocus,
      ]);
      expect(selected?.code, InsightCode.postureFocus);

      rig.controller.reportRealtimeCue(selected);
      await tester.pump();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(VisionSessionScreen)),
      );
      expect(find.byKey(const Key('vision-realtime-cue')), findsOneWidget);
      expect(find.text(l10n.visionInsightPostureFocus), findsOneWidget);
      expect(find.text(l10n.visionInsightFrettingFocus), findsNothing);
      expect(find.text(l10n.visionInsightPickingStable), findsNothing);
    });
  });

  group('A8 — the debug skeleton is labor-only', () {
    testWidgets(
      'production (labModeAvailable=false) hides the toggle and never '
      'renders the skeleton even if detailedOverlayEnabled is set',
      (tester) async {
        final rig = _rig(labModeAvailable: false, labModeOn: true);
        addTearDown(rig.dispose);
        await _reachRunning(tester, rig);

        rig.controller.setDetailedOverlayEnabled(true);
        await tester.pump();

        expect(
          find.byKey(const Key('vision-detailed-overlay-toggle')),
          findsNothing,
        );
        expect(find.byKey(const Key('vision-preview-skeleton')), findsNothing);
      },
    );

    testWidgets(
      'a Lab-mode build (labModeAvailable=true, user opted in) can reach '
      'the skeleton',
      (tester) async {
        final rig = _rig(labModeAvailable: true, labModeOn: true);
        addTearDown(rig.dispose);
        await _reachRunning(tester, rig);

        expect(
          find.byKey(const Key('vision-detailed-overlay-toggle')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const Key('vision-detailed-overlay-toggle')),
        );
        await tester.pump();

        expect(
          find.byKey(const Key('vision-preview-skeleton')),
          findsOneWidget,
        );
      },
    );
  });
}
