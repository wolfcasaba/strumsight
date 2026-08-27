// PNG-free variant matrix, the round brief §0.0.B/B4 closing-gate device:
// a risk-based screen set x {light, dark} x {en, hu} x {compact portrait,
// landscape, medium, expanded} x {textScale 1.0, 2.0}. Each cell asserts
// TWO things — no `RenderFlex` overflow and no exception during pumping —
// via `FlutterError.onError` (never a text heuristic on rendered output).
//
// Screen set (six screens, chosen for risk, not coverage-for-its-own-sake):
//   - today_hub      — the main landing surface, mixed card grid
//   - live           — DSP-critical real-time stage (§5.6)
//   - tuner          — DSP-critical real-time stage (§5.6)
//   - settings       — data-heavy switch/list rows, longest hu strings
//   - vision_result  — complex analytics cards, locale-sensitive labels
//   - login          — the pre-auth critical path, first screen logged out
//
// Fixture pattern reused verbatim from the merged
// `test/ui/goldens/e13_r{17,18,19,30,35}_screens_golden_test.dart` files —
// `AppTheme` (the app's actual runtime theme, not `SsLightTheme`/
// `SsDarkTheme` directly) and the same fake-engine/fake-repository doubles.
//
// Sizes are real risk profiles, not an arbitrary sweep:
//   - compact portrait (412x915)  — phone portrait (SsBreakpoints: compact)
//   - landscape        (915x412) — phone rotated: SHORT height, the classic
//                                   vertical-squeeze overflow risk
//   - medium            (700x1000) — small tablet / foldable (SsBreakpoints:
//                                   medium)
//   - expanded          (1024x1366) — tablet portrait (SsBreakpoints:
//                                   expanded)
//
// Exclusion list (§0.0.B/B5): a cell that genuinely overflows here cannot be
// fixed in this round — `lib/**` is this round's tilos zona (brief §4). Each
// entry carries the MEASURED overflow in px and the date it was measured,
// and every entry is mirrored in `docs/ui/legacy-backlog.md`. The exclusion
// list can ONLY shrink: a listed cell that no longer overflows fails this
// suite (`_ExcludedCell.expectOverflow`) rather than silently staying on the
// list forever (L180 — a declared-shape list is weaker than an enforced
// one). `skip`, tolerance increases and disabling cells are forbidden
// (brief §5.1) — nothing in this file uses them.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:strumsight/core/theme/app_theme.dart';
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
// Size profiles
// ---------------------------------------------------------------------------

enum _ViewportProfile { compactPortrait, landscape, medium, expanded }

const _viewportSizes = <_ViewportProfile, Size>{
  _ViewportProfile.compactPortrait: Size(412, 915),
  _ViewportProfile.landscape: Size(915, 412),
  _ViewportProfile.medium: Size(700, 1000),
  _ViewportProfile.expanded: Size(1024, 1366),
};

const _viewportNames = <_ViewportProfile, String>{
  _ViewportProfile.compactPortrait: 'compact_portrait',
  _ViewportProfile.landscape: 'landscape',
  _ViewportProfile.medium: 'medium',
  _ViewportProfile.expanded: 'expanded',
};

// ---------------------------------------------------------------------------
// Screen fixtures — one Widget builder + one (fresh-per-call) overrides
// builder per screen, mirroring the e13_r35 golden pattern.
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
    id: VisionSessionId.create('variant-matrix-session'),
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
// Exclusion list (brief §0.0.B/B5) — dated, measured, mirrored in
// docs/ui/legacy-backlog.md. Empty for now: see §10 handoff for whether this
// round's measurement run populated it.
// ---------------------------------------------------------------------------

/// One dated, measured `lib/**` layout defect this round could not fix
/// (`lib/**` is this round's tilos zona, brief §4). `screen` + `theme` +
/// `locale` + `viewport` + `textScale` must match the cell key exactly; a
/// stale entry (the cell no longer overflows) turns this suite RED — see
/// `_runCell`.
final class _ExcludedCell {
  const _ExcludedCell({
    required this.screen,
    required this.theme,
    required this.locale,
    required this.viewport,
    required this.textScale,
    required this.measuredOverflowPx,
    required this.measuredOn,
  });

  final String screen;
  final String theme;
  final String locale;
  final _ViewportProfile viewport;
  final double textScale;

  /// The overflow measured when this entry was written — documentation of
  /// the defect's magnitude, not a tolerance: the assertion only checks
  /// "still overflows", not "overflows by exactly this much" (§0.0.B/B5
  /// forbids raising tolerance, and a px-exact re-check would be a false
  /// positive if the surrounding layout shifts by a few px for unrelated
  /// reasons).
  final double measuredOverflowPx;

  final String measuredOn;

  String get key =>
      '$screen|$theme|$locale|${_viewportNames[viewport]}|$textScale';
}

/// Cells with a MEASURED, dated `lib/**` overflow this round cannot fix.
/// Populate only from an actual run of this file — never guess a px value.
///
/// All four entries below are the SAME defect: `lib/features/live/screens/
/// live_screen.dart:477` builds a horizontal `Row` (its stat strip) that
/// does not wrap an `Expanded`/`Flexible` around its children. At the
/// `landscape` viewport (915x412) with `textScale: 2.0`, the Row's
/// constraint narrows to `w<=334.0` while its children need more — the
/// overflow is 12px in `en` and 34px in `hu` (longer label text), on both
/// `light` and `dark` (the theme does not affect layout width). Measured
/// 2026-08-27 on this box via a direct run of this file
/// (`flutter test test/ui/goldens/e13_r36_variant_matrix_test.dart
/// --plain-name "live|<theme>|<locale>|landscape|2.0"`); mirrored in
/// `docs/ui/legacy-backlog.md`. `lib/**` is this round's tilos zona (brief
/// §4), so the fix (wrap the Row's children in `Expanded`, or let the strip
/// scroll) is left to a future round.
const _excludedCells = <_ExcludedCell>[
  _ExcludedCell(
    screen: 'live',
    theme: 'light',
    locale: 'en',
    viewport: _ViewportProfile.landscape,
    textScale: 2.0,
    measuredOverflowPx: 12.0,
    measuredOn: '2026-08-27',
  ),
  _ExcludedCell(
    screen: 'live',
    theme: 'dark',
    locale: 'en',
    viewport: _ViewportProfile.landscape,
    textScale: 2.0,
    measuredOverflowPx: 12.0,
    measuredOn: '2026-08-27',
  ),
  _ExcludedCell(
    screen: 'live',
    theme: 'light',
    locale: 'hu',
    viewport: _ViewportProfile.landscape,
    textScale: 2.0,
    measuredOverflowPx: 34.0,
    measuredOn: '2026-08-27',
  ),
  _ExcludedCell(
    screen: 'live',
    theme: 'dark',
    locale: 'hu',
    viewport: _ViewportProfile.landscape,
    textScale: 2.0,
    measuredOverflowPx: 34.0,
    measuredOn: '2026-08-27',
  ),
];

final _excludedByKey = {for (final cell in _excludedCells) cell.key: cell};

// ---------------------------------------------------------------------------
// Pump + capture
// ---------------------------------------------------------------------------

final _overflowPattern = RegExp(r'overflowed by ([\d.]+) pixels');

class _CellResult {
  _CellResult({required this.overflowPx, required this.otherErrors});

  /// Null when no `RenderFlex` overflow was reported.
  final double? overflowPx;

  /// Any FlutterError report (build exception surfaced as an ErrorWidget,
  /// etc.) that is NOT a RenderFlex overflow — never excludable (brief §3
  /// "NINCS pumpolás közbeni kivétel").
  final List<String> otherErrors;
}

Future<_CellResult> _pumpCell(
  WidgetTester tester, {
  required Widget Function() build,
  required List<Override> Function() overridesBuilder,
  required bool dark,
  required Locale locale,
  required _ViewportProfile viewport,
  required double textScale,
}) async {
  tester.view.physicalSize = _viewportSizes[viewport]!;
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
          theme: dark ? AppTheme.dark() : AppTheme.light(),
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
        for (final viewport in _ViewportProfile.values) {
          for (final textScale in [1.0, 2.0]) {
            final cellKey =
                '$screenName|$themeName|$localeCode|'
                '${_viewportNames[viewport]}|$textScale';

            testWidgets(cellKey, (tester) async {
              final result = await _pumpCell(
                tester,
                build: build,
                overridesBuilder: overridesBuilder,
                dark: dark,
                locale: Locale(localeCode),
                viewport: viewport,
                textScale: textScale,
              );

              expect(
                result.otherErrors,
                isEmpty,
                reason:
                    'no exception may occur while pumping this cell (brief '
                    '§3); got: ${result.otherErrors}',
              );

              final excluded = _excludedByKey[cellKey];
              if (excluded == null) {
                expect(
                  result.overflowPx,
                  isNull,
                  reason:
                      'unexpected RenderFlex overflow of '
                      '${result.overflowPx}px — either this is a new '
                      'lib/** regression (blocked, this round cannot fix '
                      'lib/**) or a dated _ExcludedCell entry is missing',
                );
              } else {
                expect(
                  result.overflowPx,
                  isNotNull,
                  reason:
                      'STALE exclusion-list entry (measured '
                      '${excluded.measuredOverflowPx}px on '
                      '${excluded.measuredOn}): this cell no longer '
                      'overflows — remove the _ExcludedCell entry and its '
                      'docs/ui/legacy-backlog.md mirror (§0.0.B/B5: the '
                      'list may only shrink)',
                );
              }
            });
          }
        }
      }
    }
  }
}
