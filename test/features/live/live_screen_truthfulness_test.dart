// E14-R13 — the Live screen's "why didn't this register a chord" statement
// comes from the MERGED recognition vocabulary (LiveFrame.chordRejectReason,
// ADR 0516 D1/D5), not a screen-local heuristic (ADR 0520). Three cells:
//   1. Producer-cell — the three reasons LivePipeline.debugDeriveChordDecision
//      produces today reach the REAL LiveScreen and show their own text.
//   2. Mutual exclusion — the banner and the heuristic `liveWeakSignal`
//      warning never coexist (ADR 0520 D4).
//   3. Textscale triple — the banner wraps rather than overflowing up to and
//      including the 200% supported ceiling (ADR 0520 D8); above it the
//      round makes no overflow guarantee, only a no-crash one.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_decision.dart';
import 'package:strumsight/features/live/domain/recognition/signal_quality_snapshot.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/live/widgets/uncertainty_reason_banner.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/main.dart';

import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

Future<FakeStrumEngine> _pumpLive(WidgetTester tester) async {
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
  container.read(routerProvider).go(AppRoutes.practiceLive);
  await tester.pumpAndSettle();
  return engine;
}

LiveFrame _frame({
  Chord? current,
  double inputLevel = 0.6,
  RecognitionRejectReason? chordRejectReason,
}) => LiveFrame(
  current: current,
  next: null,
  latestStrum: null,
  bar: const [],
  bpm: 96,
  inputLevel: inputLevel,
  tuningHz: 440,
  listening: true,
  engineTimeSec: 1.0,
  chordRejectReason: chordRejectReason,
);

void main() {
  group('producer cell — LivePipeline reasons reach the real LiveScreen', () {
    final cases = <String, RecognitionRejectReason>{
      'signalQuality (poor mic reading)': LivePipeline.debugDeriveChordDecision(
        chordLatched: false,
        hasMatch: false,
        signalQualityState: SignalQualityState.tooQuiet,
      ).$2!,
      'noChord (nothing recognized, good signal)':
          LivePipeline.debugDeriveChordDecision(
            chordLatched: false,
            hasMatch: false,
            signalQualityState: SignalQualityState.good,
          ).$2!,
      'lowConfidence (a match that never latched)':
          LivePipeline.debugDeriveChordDecision(
            chordLatched: false,
            hasMatch: true,
            signalQualityState: SignalQualityState.good,
          ).$2!,
    };

    for (final MapEntry(key: name, value: reason) in cases.entries) {
      testWidgets('$name shows its own localized banner text', (tester) async {
        final engine = await _pumpLive(tester);
        final l10n = lookupAppLocalizations(const Locale('en'));
        engine.emit(_frame(current: null, chordRejectReason: reason));
        await tester.pumpAndSettle();

        expect(
          find.text(UncertaintyReasonBanner.textFor(l10n, reason)),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 400));
      });
    }
  });

  group('mutual exclusion (ADR 0520 D4)', () {
    testWidgets(
      'a rejected decision hides the heuristic liveWeakSignal warning, '
      'even while the raw input level is also below the weak threshold',
      (tester) async {
        final engine = await _pumpLive(tester);
        final l10n = lookupAppLocalizations(const Locale('en'));
        engine.emit(
          _frame(
            current: null,
            // Weak enough to ALSO trip the heuristic, if it weren't gated.
            inputLevel: 0.02,
            chordRejectReason: RecognitionRejectReason.noChord,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(l10n.liveWeakSignal), findsNothing);
        expect(
          find.text(
            UncertaintyReasonBanner.textFor(
              l10n,
              RecognitionRejectReason.noChord,
            ),
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 400));
      },
    );
  });

  group('textscale threshold triple (ADR 0520 D8)', () {
    const compactPortrait = Size(412, 915);

    Future<void> pumpAtScale(WidgetTester tester, double textScale) async {
      tester.view.physicalSize = compactPortrait;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final engine = FakeStrumEngine();
      addTearDown(engine.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...preferenceOverrides(),
            strumEngineProvider.overrideWithValue(engine),
          ],
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
            home: const LiveScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      engine.emit(
        _frame(
          current: null,
          chordRejectReason: RecognitionRejectReason.modelUnavailable,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('150% (below the 200% ceiling) — no overflow, banner visible', (
      tester,
    ) async {
      await pumpAtScale(tester, 1.5);
      expect(find.byType(UncertaintyReasonBanner), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '200% (exactly the inclusive ceiling) — no overflow, banner visible',
      (tester) async {
        await pumpAtScale(tester, 2.0);
        expect(find.byType(UncertaintyReasonBanner), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '250% (above the ceiling) — no guarantee against overflow, only that '
      'the screen does not crash (ADR 0520 D8)',
      (tester) async {
        await pumpAtScale(tester, 2.5);
        // Above 200% the round makes no overflow promise, but it DOES still
        // guarantee no crash: only a layout-overflow exception is acceptable
        // here — anything else (e.g. a StateError) must fail this cell.
        final taken = tester.takeException();
        if (taken != null) {
          expect(taken.toString(), contains('overflowed'));
        }
      },
    );
  });
}
