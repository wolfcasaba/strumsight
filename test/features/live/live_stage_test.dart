// E13-R18 — Live Stage UI migration acceptance tests (brief §6):
//   A1 — no DSP-parameter change (the git diff on `engine/dsp/**` is the
//        other half of this cell's evidence — this file proves the UI keeps
//        showing exactly what a fixed detection frame reports).
//   A2 — weak signal and "no chord" are separate states with separate cues.
//   A3 — confidence is never colour-only (a readable percentage accompanies
//        every strum direction).
//   A6 — no overflow in portrait, landscape or expanded layouts.
//   A10 — Pause AND Finish are visible in every active transport state
//         (active, paused, finishing), in both portrait and landscape.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_decision.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/live/widgets/uncertainty_reason_banner.dart';
import 'package:strumsight/features/today/screens/today_hub_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/main.dart';

import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

const _pausePauseKey = ValueKey('ss-session-transport-pause');
const _finishKey = ValueKey('ss-session-transport-finish');

Future<FakeStrumEngine> _pumpLive(
  WidgetTester tester, {
  Size? size,
  double devicePixelRatio = 1.0,
}) async {
  if (size != null) {
    tester.view.physicalSize = Size(
      size.width * devicePixelRatio,
      size.height * devicePixelRatio,
    );
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.reset);
  }
  final engine = FakeStrumEngine();
  addTearDown(engine.dispose);
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      strumEngineProvider.overrideWithValue(engine),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const StrumSightApp(),
    ),
  );
  await tester.pumpAndSettle();
  // E15-R02 (ADR 0467 D9): the app now boots on the adaptive shell's
  // /today entry point by default; /live is reachable through
  // legacyRedirects' target, AppRoutes.practiceLive.
  container.read(routerProvider).go(AppRoutes.practiceLive);
  await tester.pumpAndSettle();
  return engine;
}

LiveFrame _frame({
  Chord? current,
  Strum? latestStrum,
  double inputLevel = 0.6,
  bool listening = true,
  double bpm = 96,
  double engineTimeSec = 1.0,
  RecognitionRejectReason? chordRejectReason,
}) => LiveFrame(
  current: current,
  next: null,
  latestStrum: latestStrum,
  bar: const [],
  bpm: bpm,
  inputLevel: inputLevel,
  tuningHz: 440,
  listening: listening,
  engineTimeSec: engineTimeSec,
  chordRejectReason: chordRejectReason,
);

void main() {
  group('A1 — DSP output reaches the UI unaltered by the migration', () {
    testWidgets('a fixed detection frame shows the exact same chord/confidence/'
        'direction as pre-migration', (tester) async {
      final engine = await _pumpLive(tester);
      engine.emit(
        _frame(
          current: const Chord('C'),
          latestStrum: const Strum(
            direction: StrumDirection.down,
            confidence: 0.9,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('C'), findsWidgets);
      expect(find.textContaining('90%'), findsWidgets);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('A2 — weak signal and "no chord" are distinct states', () {
    testWidgets(
      'weak signal WHILE a chord is held shows the mic warning, not the '
      '"play a chord" prompt',
      (tester) async {
        final engine = await _pumpLive(tester);
        final l10n = lookupAppLocalizations(const Locale('en'));
        engine.emit(
          _frame(
            current: const Chord('C'),
            latestStrum: const Strum(
              direction: StrumDirection.down,
              confidence: 0.9,
            ),
            inputLevel: 0.02,
            // ADR 0520 D5: this cell is the "no decision" branch of the
            // MERGED reject-reason source — chordRejectReason is explicitly
            // null (not merely defaulted), so the heuristic weak-signal
            // warning is the one displaying, and the new decision-based
            // banner (E14-R13) stays out of the tree.
            chordRejectReason: null,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(l10n.liveWeakSignal), findsOneWidget);
        expect(find.text(l10n.liveWaitingForChord), findsNothing);
        expect(find.byType(UncertaintyReasonBanner), findsNothing);
        await tester.pump(const Duration(milliseconds: 400));
      },
    );

    testWidgets(
      'no chord WHILE the signal is adequate shows the "play a chord" '
      'prompt, not the mic warning',
      (tester) async {
        final engine = await _pumpLive(tester);
        final l10n = lookupAppLocalizations(const Locale('en'));
        engine.emit(
          _frame(
            current: null,
            inputLevel: 0.6,
            // ADR 0520 D5: no decision yet — the merged source agrees with
            // the heuristic's "no chord" reading, so the decision-based
            // banner stays out of the tree here too.
            chordRejectReason: null,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(l10n.liveWaitingForChord), findsWidgets);
        expect(find.text(l10n.liveWeakSignal), findsNothing);
        expect(find.byType(UncertaintyReasonBanner), findsNothing);
        await tester.pump(const Duration(milliseconds: 400));
      },
    );
  });

  group('A3 — confidence is never colour-only', () {
    testWidgets(
      'a low-confidence and a high-confidence strum read as DIFFERENT text, '
      'not just a colour swap',
      (tester) async {
        final engine = await _pumpLive(tester);
        engine.emit(
          _frame(
            current: const Chord('C'),
            latestStrum: const Strum(
              direction: StrumDirection.down,
              confidence: 0.2,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(RegExp('Down 20%')), findsWidgets);

        engine.emit(
          _frame(
            current: const Chord('C'),
            latestStrum: const Strum(
              direction: StrumDirection.down,
              confidence: 0.92,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(RegExp('Down 92%')), findsWidgets);
        await tester.pump(const Duration(milliseconds: 400));
      },
    );
  });

  group('A6 — no overflow across layouts', () {
    for (final MapEntry(key: name, value: size) in const {
      'portrait compact (412×915)': Size(412, 915),
      'landscape compact (915×412)': Size(915, 412),
      'expanded (1300×900)': Size(1300, 900),
    }.entries) {
      testWidgets('$name renders a full frame without overflow', (
        tester,
      ) async {
        final engine = await _pumpLive(tester, size: size);
        engine.emit(
          _frame(
            current: const Chord('Am'),
            latestStrum: const Strum(
              direction: StrumDirection.up,
              confidence: 0.7,
            ),
            bpm: 120,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 400));
      });
    }
  });

  group(
    'A10 — Pause and Finish stay visible in every active transport state',
    () {
      for (final MapEntry(key: name, value: size) in const {
        'portrait': Size(412, 915),
        'landscape': Size(915, 412),
      }.entries) {
        testWidgets('$name — active', (tester) async {
          final engine = await _pumpLive(tester, size: size);
          engine.emit(_frame(current: const Chord('C')));
          await tester.pumpAndSettle();

          expect(find.byKey(_pausePauseKey), findsOneWidget);
          expect(find.byKey(_finishKey), findsOneWidget);
          await tester.pump(const Duration(milliseconds: 400));
        });

        testWidgets('$name — paused', (tester) async {
          final engine = await _pumpLive(tester, size: size);
          engine.emit(_frame(current: const Chord('C')));
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(_pausePauseKey));
          await tester.pumpAndSettle();

          expect(find.byKey(_pausePauseKey), findsOneWidget);
          expect(find.byKey(_finishKey), findsOneWidget);
          await tester.pump(const Duration(milliseconds: 400));
        });

        testWidgets('$name — finishing', (tester) async {
          final engine = await _pumpLive(tester, size: size);
          engine.emit(_frame(current: const Chord('C')));
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(_finishKey));
          // One frame only — catches the transient `finishing` state before
          // the deferred navigation (300 ms) actually leaves the route.
          await tester.pump();

          expect(find.byKey(_pausePauseKey), findsOneWidget);
          expect(find.byKey(_finishKey), findsOneWidget);
          expect(
            find.byKey(const ValueKey('ss-session-transport-finishing-marker')),
            findsOneWidget,
          );

          // Let the deferred navigation settle so no Timer is left pending.
          await tester.pump(const Duration(milliseconds: 350));
        });
      }
    },
  );

  group('Finish fallback target is the app entry route, not a fixed screen '
      '(review MINOR-2)', () {
    testWidgets('E15-R02 (ADR 0467 D9): with the adaptive shell on (now the '
        'non-production default) and nothing to pop to, Finish navigates to '
        '/today — the entry route — instead of staying on Live', (
      tester,
    ) async {
      final engine = await _pumpLive(tester);
      engine.emit(_frame(current: const Chord('C')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_finishKey));
      await tester.pump();
      // Past the 300 ms deferred-navigation beat.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Navigated away to the entry route — not stuck on Live.
      expect(find.byType(LiveScreen), findsNothing);
      expect(find.byType(TodayHubScreen), findsOneWidget);
    });
  });
}
