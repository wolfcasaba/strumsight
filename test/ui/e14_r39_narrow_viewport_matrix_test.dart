// E14-R39 (ADR 0547) — the 360 px profile the adaptive matrix was missing.
//
// The shipped variant matrix starts at compact 412 (`e13_r36`, `e15_r13`),
// which is WIDER than the narrowest phones still in use (360 dp is the
// Android baseline for a 5" device and for split-screen). This file adds the
// missing profile as an OVERFLOW/EXCEPTION matrix — deliberately not a
// golden: a byte-comparison at a new size would only add churn, while the
// thing the audit needs to know is whether anything breaks its layout.
//
// Scope is PKG-C's own screens (Today hub, Tuner, Metronome), including the
// E14-R36 chain states, which are new surface at this size.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/features/metronome/screens/metronome_screen.dart';
import 'package:strumsight/features/today/domain/ten_minute_flow.dart';
import 'package:strumsight/features/today/providers/ten_minute_flow_providers.dart';
import 'package:strumsight/features/today/screens/today_hub_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../support/fake_audio.dart';
import '../support/fake_engines.dart';
import '../support/preference_store.dart';

/// The narrowest profile the app claims to support. Portrait, so the stage
/// screens take their `_CompactStage` branch — the one a 412 landscape cell
/// never exercises.
const _narrowViewport = Size(360, 640);

/// 1.0 is the baseline, 1.3 the common "slightly larger" system setting,
/// 2.0 the accessibility bound the rest of the suite already pins.
const _textScales = <double>[1.0, 1.3, 2.0];

/// Hungarian is the long-string locale: every measured overflow in this
/// tree so far reproduced in `hu` and not in `en`.
const _locales = <String>['en', 'hu'];

final _now = DateTime(2026, 8, 25, 18);

class _SeededFlowController extends TenMinuteFlowController {
  _SeededFlowController(this._seed);
  final TenMinuteFlowState? _seed;

  @override
  TenMinuteFlowState? build() => _seed;
}

Override _chainAt(TenMinuteStep step) => tenMinuteFlowProvider.overrideWith(
  () => _SeededFlowController(
    TenMinuteFlowState(
      plan: TenMinutePlan.standard,
      step: step,
      startedAt: _now,
      baselineActiveSeconds: 0,
    ),
  ),
);

Future<List<String>> _renderCell(
  WidgetTester tester, {
  required String locale,
  required double textScale,
  required Widget home,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = _narrowViewport;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final captured = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) =>
      captured.add(details.exception.toString());
  try {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...preferenceOverrides(),
          ...fakeAudioOverrides(),
          ...overrides,
        ],
        child: MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    // Two frames: the first lays out, the second lets any post-frame work
    // (the tuner's permission read) land. Never `pumpAndSettle` — a running
    // stage ticker would make it hang rather than fail.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
  } finally {
    FlutterError.onError = previous;
  }
  return captured;
}

void _expectClean(List<String> errors, String cell) {
  expect(
    errors,
    isEmpty,
    reason:
        '$cell at 360x640 reported: ${errors.join(" | ")} — the 360 profile '
        'is a supported size, so an overflow here is a defect, not a '
        'tolerated variant',
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the 360 px profile renders every PKG-C screen cleanly', () {
    for (final locale in _locales) {
      for (final scale in _textScales) {
        final suffix = '$locale @ textScale $scale';

        testWidgets('Today hub — $suffix', (tester) async {
          _expectClean(
            await _renderCell(
              tester,
              locale: locale,
              textScale: scale,
              home: TodayHubScreen(now: _now),
            ),
            'Today hub ($suffix)',
          );
        });

        testWidgets('Today hub, 10-minute chain on its recap — $suffix', (
          tester,
        ) async {
          _expectClean(
            await _renderCell(
              tester,
              locale: locale,
              textScale: scale,
              home: TodayHubScreen(now: _now),
              overrides: [_chainAt(TenMinuteStep.review)],
            ),
            'Today hub / chain recap ($suffix)',
          );
        });

        testWidgets('Tuner — $suffix', (tester) async {
          final engine = FakeTunerEngine();
          addTearDown(engine.dispose);
          _expectClean(
            await _renderCell(
              tester,
              locale: locale,
              textScale: scale,
              home: const TunerScreen(),
              overrides: [tunerEngineProvider.overrideWithValue(engine)],
            ),
            'Tuner ($suffix)',
          );
        });

        testWidgets('Tuner, 10-minute chain hand-off visible — $suffix', (
          tester,
        ) async {
          final engine = FakeTunerEngine();
          addTearDown(engine.dispose);
          _expectClean(
            await _renderCell(
              tester,
              locale: locale,
              textScale: scale,
              home: const TunerScreen(),
              overrides: [
                tunerEngineProvider.overrideWithValue(engine),
                _chainAt(TenMinuteStep.tune),
              ],
            ),
            'Tuner / chain hand-off ($suffix)',
          );
        });

        testWidgets('Metronome — $suffix', (tester) async {
          _expectClean(
            await _renderCell(
              tester,
              locale: locale,
              textScale: scale,
              home: const MetronomeScreen(),
            ),
            'Metronome ($suffix)',
          );
        });
      }
    }
  });

  // Without this the whole matrix above could be green because the detector
  // never fires — the same falsification discipline the A2 depth probe uses
  // in `hub_navigation_test.dart`.
  group('the detector itself', () {
    testWidgets('a row that really does not fit 360 px IS reported', (
      tester,
    ) async {
      tester.view.physicalSize = _narrowViewport;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final previous = FlutterError.onError;
      final captured = <String>[];
      FlutterError.onError = (details) =>
          captured.add(details.exception.toString());
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  SizedBox(width: 500, height: 10),
                  SizedBox(width: 500, height: 10),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
      } finally {
        FlutterError.onError = previous;
      }

      expect(
        captured.any((e) => e.contains('overflowed')),
        isTrue,
        reason:
            'the capture mechanism must actually see a RenderFlex overflow, '
            'otherwise every "clean" cell above proves nothing',
      );
    });
  });
}
