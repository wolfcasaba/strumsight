// Audit U6 — the Live stage used to stack hero/feedback/timeline against the
// header, leaving the screen's middle third empty while the content crowded
// top and bottom. `LiveScreen` now distributes that spare height with token
// spacing of its own (a `Padding` on the hero and the feedback slots), which
// is a purely additive layout change: no widget key, no semantics label and
// no `SsStageScaffold` slot moves.
//
// This file is the safety net that change needs. It pumps the screen across
// {360×640, 412×915} × {textScale 1.0, 2.0} × {idle, chord on screen} and
// asserts NO `RenderFlex` overflow and no other framework error in any cell —
// the overflow-detection approach of
// `test/ui/goldens/e15_r13_full_variant_matrix_test.dart` (capture
// `FlutterError.onError`, match the "overflowed by N pixels" message), inside
// this feature's own test directory. 360×640 is NARROWER and SHORTER than
// every viewport that matrix covers, so the added vertical spacing is proven
// against the tightest phone we support, not only the roomy one.
//
// L558: every cell sets its own `tester.view.physicalSize` +
// `devicePixelRatio` and resets it via `addTearDown` — the flutter_test
// default 800×600 viewport is not what any of these cells measure.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

final _overflowPattern = RegExp(r'overflowed by ([\d.]+) pixels');

LiveFrame _frame({Chord? current, Strum? latestStrum}) => LiveFrame(
  current: current,
  next: null,
  latestStrum: latestStrum,
  bar: const [],
  bpm: 96,
  inputLevel: 0.6,
  tuningHz: 440,
  listening: true,
  engineTimeSec: 1.0,
);

void main() {
  const viewports = <String, Size>{
    'compact 360×640': Size(360, 640),
    'modern 412×915': Size(412, 915),
  };

  for (final MapEntry(key: viewportName, value: size) in viewports.entries) {
    for (final textScale in const <double>[1.0, 2.0]) {
      for (final withChord in const <bool>[false, true]) {
        final state = withChord ? 'chord on screen' : 'idle';
        testWidgets('U6 — Live stage lays out without overflow: $viewportName, '
            'textScale $textScale, $state', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          final engine = FakeStrumEngine();
          addTearDown(engine.dispose);

          final captured = <FlutterErrorDetails>[];
          final previousOnError = FlutterError.onError;
          FlutterError.onError = captured.add;

          try {
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  ...preferenceOverrides(),
                  ...fakeAudioOverrides(),
                  strumEngineProvider.overrideWithValue(engine),
                ],
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: SsLightTheme.data(),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(textScale)),
                    child: child!,
                  ),
                  home: const LiveScreen(),
                ),
              ),
            );
            await tester.pumpAndSettle();

            if (withChord) {
              engine.emit(
                _frame(
                  current: const Chord('Am'),
                  latestStrum: const Strum(
                    direction: StrumDirection.down,
                    confidence: 0.92,
                  ),
                ),
              );
              await tester.pumpAndSettle();
            }
            // Let the live-region announcer's timer drain before teardown.
            await tester.pump(const Duration(milliseconds: 400));
          } finally {
            FlutterError.onError = previousOnError;
          }

          final overflows = <String>[];
          final otherErrors = <String>[];
          for (final details in captured) {
            final message = details.exception.toString();
            if (_overflowPattern.hasMatch(message)) {
              overflows.add(message);
            } else {
              otherErrors.add(message);
            }
          }

          expect(
            overflows,
            isEmpty,
            reason:
                'the Live stage must not overflow at $viewportName / '
                'textScale $textScale ($state)',
          );
          expect(otherErrors, isEmpty);
        });
      }
    }
  }
}
