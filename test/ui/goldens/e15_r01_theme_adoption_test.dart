// PNG-free variant matrix — E15-R01 A4 (ADR 0466 D7): proves the ADOPTED
// design-system theme (`SsLightTheme.data()` / `SsDarkTheme.data()`, this
// round's app theme) renders every risk-selected screen without a
// `RenderFlex` overflow or a build exception, compact portrait only, with
// NO exclusion list (§5.5): a red cell here is either this round's theme-
// wiring regression (fixed in this round) or a `lib/features/**` defect,
// which triggers the round brief's STOP-protocol instead of an exclusion
// entry.
//
// Screen set (six screens, chosen for risk — the same set as
// `test/ui/goldens/e13_r36_variant_matrix_test.dart`):
//   - today_hub      — the main landing surface, mixed card grid
//   - live           — DSP-critical real-time stage
//   - tuner          — DSP-critical real-time stage
//   - settings       — data-heavy switch/list rows, longest hu strings
//   - vision_result  — complex analytics cards, locale-sensitive labels
//   - login          — the pre-auth critical path, first screen logged out
//
// Fixture pattern (fake-engine/fake-repository doubles) reused verbatim
// from `e13_r36_variant_matrix_test.dart`. Two differences from that file:
// the theme fed to `MaterialApp` is the ADOPTED `SsLightTheme.data()` /
// `SsDarkTheme.data()`, not `AppTheme` directly; and the viewport is fixed
// to compact portrait (412x915) only — ADR 0466's pre-flight measured no
// known overflow there (the four `e13_r36` exclusions are all `landscape`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/auth/screens/login_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/settings/data/settings_repository.dart';
import 'package:strumsight/features/settings/screens/settings_screen.dart';
import 'package:strumsight/features/today/screens/today_hub_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/features/vision/application/calibration_loss_machine.dart';
import 'package:strumsight/features/vision/domain/feedback/insight_code.dart';
import 'package:strumsight/features/vision/domain/quality/vision_quality_summary.dart';
import 'package:strumsight/features/vision/domain/vision_session.dart';
import 'package:strumsight/features/vision/domain/vision_session_result.dart';
import 'package:strumsight/features/vision/presentation/screens/vision_result_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_auth.dart';
import '../../support/fake_engines.dart';
import '../../support/fake_settings.dart';
import '../../support/preference_store.dart';

// ---------------------------------------------------------------------------
// Viewport — compact portrait only (ADR 0466 D7)
// ---------------------------------------------------------------------------

const _viewportSize = Size(412, 915);

// ---------------------------------------------------------------------------
// Screen fixtures — one Widget builder + one (fresh-per-call) overrides
// builder per screen, mirroring the e13_r36 pattern.
// ---------------------------------------------------------------------------

Widget _todayHubScreen() => TodayHubScreen(now: DateTime(2026, 8, 27));
List<Override> _todayHubOverrides() => [...preferenceOverrides()];

Widget _liveScreen() => const LiveScreen();
List<Override> _liveOverrides() {
  final engine = FakeStrumEngine();
  addTearDown(engine.dispose);
  return [
    ...preferenceOverrides(),
    strumEngineProvider.overrideWithValue(engine),
  ];
}

Widget _tunerScreen() => const TunerScreen();
List<Override> _tunerOverrides() {
  final engine = FakeTunerEngine();
  addTearDown(engine.dispose);
  return [
    ...preferenceOverrides(),
    tunerEngineProvider.overrideWithValue(engine),
  ];
}

Widget _settingsScreen() => const Scaffold(body: SettingsScreen());
List<Override> _settingsOverrides() => [
  ...preferenceOverrides(),
  tokenStoreProvider.overrideWithValue(FakeTokenStore()),
  authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
  settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
];

VisionSessionResult _goldenVisionResult() => VisionSessionResult(
  session: VisionSession(
    id: VisionSessionId.create('e15-r01-variant-matrix-session'),
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

Widget _visionResultScreen() => VisionResultScreen(
  result: _goldenVisionResult(),
  onStartCorrectivePractice: () {},
);
List<Override> _visionResultOverrides() => const [];

Widget _loginScreen() => const LoginScreen();
List<Override> _loginOverrides() => [
  ...preferenceOverrides(),
  tokenStoreProvider.overrideWithValue(FakeTokenStore()),
  authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
];

final _screens = <String, (Widget Function(), List<Override> Function())>{
  'today_hub': (_todayHubScreen, _todayHubOverrides),
  'live': (_liveScreen, _liveOverrides),
  'tuner': (_tunerScreen, _tunerOverrides),
  'settings': (_settingsScreen, _settingsOverrides),
  'vision_result': (_visionResultScreen, _visionResultOverrides),
  'login': (_loginScreen, _loginOverrides),
};

// ---------------------------------------------------------------------------
// Pump + capture
// ---------------------------------------------------------------------------

final _overflowPattern = RegExp(r'overflowed by ([\d.]+) pixels');

class _CellResult {
  _CellResult({required this.overflowPx, required this.otherErrors});

  /// Null when no `RenderFlex` overflow was reported.
  final double? overflowPx;

  /// Any FlutterError report that is NOT a RenderFlex overflow — never
  /// excludable (§5.5: no exception may occur while pumping a cell).
  final List<String> otherErrors;
}

Future<_CellResult> _pumpCell(
  WidgetTester tester, {
  required Widget Function() build,
  required List<Override> Function() overridesBuilder,
  required bool dark,
  required Locale locale,
  required double textScale,
}) async {
  tester.view.physicalSize = _viewportSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final captured = <FlutterErrorDetails>[];
  final previousOnError = FlutterError.onError;
  FlutterError.onError = captured.add;

  try {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overridesBuilder(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? SsDarkTheme.data() : SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: build(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  } finally {
    FlutterError.onError = previousOnError;
  }

  double? overflowPx;
  final otherErrors = <String>[];
  for (final details in captured) {
    final message = details.exception.toString();
    final match = _overflowPattern.firstMatch(message);
    if (match != null) {
      final px = double.parse(match.group(1)!);
      overflowPx = overflowPx == null ? px : (overflowPx + px);
    } else {
      otherErrors.add(message);
    }
  }
  return _CellResult(overflowPx: overflowPx, otherErrors: otherErrors);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final screenEntry in _screens.entries) {
    final screenName = screenEntry.key;
    final (build, overridesBuilder) = screenEntry.value;

    for (final dark in [false, true]) {
      final themeName = dark ? 'dark' : 'light';

      for (final localeCode in ['en', 'hu']) {
        for (final textScale in [1.0, 2.0]) {
          final cellKey = '$screenName|$themeName|$localeCode|$textScale';

          testWidgets(cellKey, (tester) async {
            final result = await _pumpCell(
              tester,
              build: build,
              overridesBuilder: overridesBuilder,
              dark: dark,
              locale: Locale(localeCode),
              textScale: textScale,
            );

            expect(
              result.otherErrors,
              isEmpty,
              reason:
                  'no exception may occur while pumping this cell (ADR '
                  '0466 D7); got: ${result.otherErrors}',
            );
            expect(
              result.overflowPx,
              isNull,
              reason:
                  'unexpected RenderFlex overflow of ${result.overflowPx}px '
                  '— no exclusion list is permitted for this matrix (§5.5): '
                  'this is either a theme-wiring regression (fix in this '
                  'round) or a lib/features/** defect (STOP-protocol)',
            );
          });
        }
      }
    }
  }
}
