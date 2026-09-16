// Owner bug report (device APK, build-apk run 35071659469): "the camera
// vibration does not work". MEASURED cause: the Vision/camera surface had no
// haptic code at ALL — SDD Ch6 §24.3 specifies `coachCue` as "vizuális +
// opcionális haptic", but only the visual half shipped
// (`vision_preview_overlay.dart` renders the `vision-realtime-cue` text;
// `grep -rn HapticFeedback lib/features/vision lib/core/camera` was empty).
//
// This suite pins the missing half against the REAL production widget, using
// the same platform-channel interception the share/wakelock suites use
// (`test/features/share/share_service_test.dart`,
// `test/core/design_system/stage/ss_stage_scaffold_test.dart`): the fix has
// to reach `SystemChannels.platform`, not just a local bool, or it is not a
// vibration on the device.
//
// The rig mirrors `vision_one_cue_test.dart` so the cue path under test is
// the one the router composes, not a stand-in.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

Widget _host(Widget child) => MaterialApp(
  theme: SsLightTheme.data(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

AppConfig _config() => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: const FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

final class _Rig {
  _Rig(this.container);

  final ProviderContainer container;

  VisionSessionController get controller =>
      container.read(visionSessionControllerProvider.notifier);

  void dispose() => container.dispose();
}

_Rig _rig() {
  final capture = FakeCameraCapture();
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(_config()),
      cameraPermissionGatewayProvider.overrideWithValue(_PermissionGateway()),
      cameraCaptureFactoryProvider.overrideWithValue(() => capture),
      cameraSessionCoordinatorProvider.overrideWithValue(
        CameraSessionCoordinator(),
      ),
      keyValueStoreProvider.overrideWithValue(
        InMemoryKeyValueStore(<String, Object>{StorageKeys.labMode: false}),
      ),
      visionSessionClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 9, 16, 12),
      ),
      visionSessionIdFactoryProvider.overrideWithValue(
        () => VisionSessionId.create('cue-haptics-test-session'),
      ),
    ],
  );
  container.listen(visionSessionControllerProvider, (_, _) {});
  return _Rig(container);
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

/// Intercepts `SystemChannels.platform` inside the running test (the
/// `ss_stage_scaffold_test.dart` pattern) and returns the list into which
/// every `HapticFeedback.vibrate` argument is recorded, in order. Everything
/// else on the channel keeps its null default, so the surrounding
/// MaterialApp/AppBar behave exactly as they do untouched.
List<Object?> _hapticProbe(WidgetTester tester) {
  final pulses = <Object?>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        pulses.add(call.arguments);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return pulses;
}

void main() {
  group('camera cue haptics (SDD Ch6 §24.3 coachCue)', () {
    testWidgets('a new realtime cue fires exactly one impact pulse', (
      tester,
    ) async {
      final pulses = _hapticProbe(tester);
      final rig = _rig();
      addTearDown(rig.dispose);
      await _reachRunning(tester, rig);

      // Reaching `running` is setup, not coaching — nothing has vibrated yet.
      expect(pulses, isEmpty);

      rig.controller.reportRealtimeCue(
        _insight(InsightCode.pickingStable, 0.9),
      );
      await tester.pump();

      expect(find.byKey(const Key('vision-realtime-cue')), findsOneWidget);
      // `mediumImpact`, NOT `vibrate`: on Android the impact variants go
      // through `View.performHapticFeedback`, which needs no VIBRATE
      // permission and follows the system touch-feedback setting.
      expect(pulses, <String>['HapticFeedbackType.mediumImpact']);
    });

    testWidgets('re-reporting the SAME cue does not pulse again', (
      tester,
    ) async {
      final pulses = _hapticProbe(tester);
      final rig = _rig();
      addTearDown(rig.dispose);
      await _reachRunning(tester, rig);

      final cue = _insight(InsightCode.pickingStable, 0.9);
      rig.controller.reportRealtimeCue(cue);
      await tester.pump();
      // The controller re-reports the held selection on every quality tick;
      // a buzz per frame would be the opposite of a coaching signal.
      rig.controller.reportRealtimeCue(
        _insight(InsightCode.pickingStable, 0.9),
      );
      await tester.pump();
      rig.controller.reportRealtimeCue(cue);
      await tester.pump();

      expect(pulses, hasLength(1));
    });

    testWidgets('a DIFFERENT cue pulses again; clearing the cue does not', (
      tester,
    ) async {
      final pulses = _hapticProbe(tester);
      final rig = _rig();
      addTearDown(rig.dispose);
      await _reachRunning(tester, rig);

      rig.controller.reportRealtimeCue(
        _insight(InsightCode.pickingStable, 0.9),
      );
      await tester.pump();
      rig.controller.reportRealtimeCue(
        _insight(InsightCode.postureFocus, 0.95),
      );
      await tester.pump();
      expect(pulses, hasLength(2));

      rig.controller.reportRealtimeCue(null);
      await tester.pump();

      expect(find.byKey(const Key('vision-realtime-cue')), findsNothing);
      expect(pulses, hasLength(2), reason: 'a cleared cue is not an event');
    });
  });
}
