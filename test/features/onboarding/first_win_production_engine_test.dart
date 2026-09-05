import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/first_win_engine.dart';
import 'package:strumsight/features/onboarding/first_win_providers.dart';
import 'package:strumsight/features/onboarding/screens/first_win_stage_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_engines.dart';

/// The E17-R01 self-heal (ADR 0534 §0.0/D3): the SHIPPED default factory of
/// `onboardingFirstWinEngineFactoryProvider` must build a production engine
/// reading the real `strumEngineProvider` frame stream, not
/// `FakeOnboardingFirstWinEngine` — a fake default would leave the Stage
/// permanently on "Listening…" while every OTHER acceptance cell (A1/A4)
/// still measured green (the halt's hibaosztálya, L606).
LiveFrame _frame(double confidence) => LiveFrame(
  current: null,
  next: null,
  latestStrum: Strum(direction: StrumDirection.down, confidence: confidence),
  bar: const [],
  bpm: 0,
  inputLevel: 0.5,
  tuningHz: 440,
  listening: true,
);

Future<FakeStrumEngine> _pumpStage(WidgetTester tester) async {
  final engine = FakeStrumEngine();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [strumEngineProvider.overrideWithValue(engine)],
      child: MaterialApp(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FirstWinStageScreen(),
      ),
    ),
  );
  await tester.pump();
  return engine;
}

/// A5-A7 pump against an EXPLICIT `FakeOnboardingFirstWinEngine` override —
/// deliberately independent of whatever `onboardingFirstWinEngineFactoryProvider`'s
/// default happens to build. This is what makes the round's §6.1 third
/// falsification probe meaningful: reverting the default factory to the fake
/// must flip ONLY A8 red while these boundary cells (driven by their OWN
/// override) stay green.
Future<FakeOnboardingFirstWinEngine> _pumpStageWithFake(
  WidgetTester tester,
) async {
  final fake = FakeOnboardingFirstWinEngine();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        onboardingFirstWinEngineFactoryProvider.overrideWithValue(() => fake),
      ],
      child: MaterialApp(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FirstWinStageScreen(),
      ),
    ),
  );
  await tester.pump();
  return fake;
}

void main() {
  group('A8 — the shipped factory is the production engine, not the fake', () {
    test(
      'the default factory builds a LiveFirstWinEngine over strumEngineProvider',
      () {
        final engine = FakeStrumEngine();
        final container = ProviderContainer(
          overrides: [strumEngineProvider.overrideWithValue(engine)],
        );
        addTearDown(container.dispose);

        final factory = container.read(onboardingFirstWinEngineFactoryProvider);
        final built = factory();

        expect(
          built,
          isA<LiveFirstWinEngine>(),
          reason:
              'ADR 0534 D3 — the shipped default must be the production '
              'engine, not FakeOnboardingFirstWinEngine',
        );
      },
    );

    test(
      'the produced confidence is sourced from the live frame stream',
      () async {
        final engine = FakeStrumEngine();
        final container = ProviderContainer(
          overrides: [strumEngineProvider.overrideWithValue(engine)],
        );
        addTearDown(container.dispose);

        final values = <double>[];
        final sub = container.listen(onboardingFirstWinConfidenceProvider, (
          _,
          next,
        ) {
          final v = next.value;
          if (v != null) values.add(v);
        });
        addTearDown(sub.close);

        expect(
          engine.startCalls,
          1,
          reason: 'mounting the Stage must start the SHARED strum engine',
        );

        engine.emit(_frame(0.85));
        await Future<void>.delayed(Duration.zero);

        expect(values, contains(0.85));
      },
    );
  });

  group('A5-A7 — the inclusive threshold at its exact boundary (override-based '
      "— brief §6.1's third falsification probe requires these independent "
      'of the default factory)', () {
    testWidgets('0.59 (just below) stays on the weak/retry branch', (
      tester,
    ) async {
      final fake = await _pumpStageWithFake(tester);
      fake.emit(0.59);
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('onboard-first-win-continue')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('onboard-first-win-retry')),
        findsOneWidget,
      );
    });

    testWidgets('0.60 (exactly at the threshold) is a success — inclusive', (
      tester,
    ) async {
      final fake = await _pumpStageWithFake(tester);
      fake.emit(kFirstWinConfidenceThreshold);
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('onboard-first-win-continue')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('onboard-first-win-retry')),
        findsNothing,
      );
    });

    testWidgets('0.61 (just above) is a success — same branch as 0.60', (
      tester,
    ) async {
      final fake = await _pumpStageWithFake(tester);
      fake.emit(0.61);
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('onboard-first-win-continue')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('onboard-first-win-retry')),
        findsNothing,
      );
    });
  });

  group('A9 — leaving the Stage releases the motor; the next mini-lesson still '
      'detects (no dead motor)', () {
    test('stop() runs on dispose and the shared engine restarts for the '
        'next watcher', () async {
      final engine = FakeStrumEngine();
      final container = ProviderContainer(
        overrides: [strumEngineProvider.overrideWithValue(engine)],
      );
      addTearDown(container.dispose);

      final stageSub = container.listen(
        onboardingFirstWinConfidenceProvider,
        (_, _) {},
      );
      expect(engine.startCalls, 1);
      expect(engine.stopCalls, 0);

      stageSub.close(); // "leaving the Stage" — nothing watches it
      await Future<void>.delayed(Duration.zero);
      expect(
        engine.stopCalls,
        1,
        reason: 'the Stage must release the motor once left',
      );

      // The following mini-lesson watches the SAME strumEngineProvider,
      // via liveFrameProvider (learn_screen.dart's own precedent) — it
      // must still get frames, proving the SHARED engine was stopped,
      // not disposed.
      final lessonSub = container.listen(liveFrameProvider, (_, _) {});
      addTearDown(lessonSub.close);
      await Future<void>.delayed(Duration.zero);
      expect(
        engine.startCalls,
        2,
        reason:
            'no dead motor — the next watcher must restart the SAME '
            'shared engine',
      );

      engine.emit(_frame(0.5));
      await Future<void>.delayed(Duration.zero);
    });
  });

  group(
    'A10 — a confidence-source failure is stated, never silent Listening…',
    () {
      test('a stream error surfaces as an AsyncValue error', () async {
        final engine = FakeStrumEngine();
        final container = ProviderContainer(
          overrides: [strumEngineProvider.overrideWithValue(engine)],
        );
        addTearDown(container.dispose);

        AsyncValue<double>? seen;
        final sub = container.listen(onboardingFirstWinConfidenceProvider, (
          _,
          next,
        ) {
          seen = next;
        });
        addTearDown(sub.close);

        engine.emitError(StateError('mic busy'));
        await Future<void>.delayed(Duration.zero);

        expect(seen?.hasError, isTrue);
      });

      testWidgets('the Stage states the error and keeps "Not now" reachable', (
        tester,
      ) async {
        final engine = await _pumpStage(tester);
        engine.emitError(StateError('mic busy'));
        await tester.pump();
        await tester.pump();

        final l10n = lookupAppLocalizations(const Locale('en'));
        expect(find.text(l10n.micPermissionBody), findsOneWidget);
        expect(
          find.byKey(const ValueKey('onboard-first-win-skip')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('onboard-first-win-continue')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('onboard-first-win-retry')),
          findsNothing,
        );
      });
    },
  );
}
