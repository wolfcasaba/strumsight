import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/audio_providers.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/chords/chord_shape.dart';
import 'package:strumsight/features/learn/model/lesson.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/onboarding/first_win_engine.dart';
import 'package:strumsight/features/onboarding/first_win_providers.dart';
import 'package:strumsight/features/onboarding/screens/first_win_stage_screen.dart';
import 'package:strumsight/features/onboarding/screens/onboarding_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_audio.dart';
import '../../support/preference_store.dart';

/// Round 155 — the onboarding "first win" (chunk 017 rec #4): the shortest
/// route from install to a SCORED strum, inside the first two minutes.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the first-win lesson is a true 30-second starter', () {
    final l = Lessons.firstWin;
    expect(l.events, isNotEmpty);
    expect(
      l.events.every((e) => e.direction == StrumDirection.down),
      isTrue,
      reason: 'downstrokes only — nothing to fail on but the beat',
    );
    expect(l.events.map((e) => e.chord).toSet(), {
      'Em',
    }, reason: 'one easy chord');
    expect(
      ChordShapes.has('Em'),
      isTrue,
      reason: 'the diagram must render for the very first screen',
    );
    final seconds = l.totalBeats * 60 / l.bpm;
    expect(
      seconds,
      lessThanOrEqualTo(35),
      reason: 'a first win must be ~30 seconds, not a commitment',
    );
    expect(
      Lessons.all.map((x) => x.id),
      isNot(contains('first-win')),
      reason: 'outside the curriculum/unlock chain',
    );
  });

  test('a passed first win funnels into the curriculum (r159)', () {
    final next = Lessons.nextAfter('first-win');
    expect(
      next,
      isNotNull,
      reason:
          'the finish dialog must offer the first real lesson, '
          'not dead-end a brand-new user on "Play again"',
    );
    expect(next!.id, Lessons.all.first.id);
  });

  testWidgets('the last page leads with the first-win CTA', (tester) async {
    var firstWin = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...preferenceOverrides(),
          microphonePermissionGatewayProvider.overrideWithValue(
            FakeMicrophonePermissionGateway(),
          ),
        ],
        child: MaterialApp(
          // R2 (§0.0, extended measurement): the migrated OnboardingScreen
          // now reads the design-system theme extensions via SsButton — a
          // themeless MaterialApp null-check crashes (L593-class defect).
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OnboardingScreen(onDone: () {}, onFirstWin: () => firstWin++),
        ),
      ),
    );
    // Page 1+2: normal Next; the CTA must not appear early.
    expect(find.text('Try your first win — 30 seconds'), findsNothing);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Try your first win — 30 seconds'), findsOneWidget);
    await tester.tap(find.text('Try your first win — 30 seconds'));
    await tester.pumpAndSettle();
    expect(firstWin, 1, reason: 'the CTA must route to the mini-lesson');
  });

  // SDD Ch13 Kör 16 (ADR 0281 §2) — the mini Stage's three mandatory
  // threshold cells (§6.1). The boundary is inclusive at exactly 0.60.
  group('the first-win threshold (§6.1) — inclusive at 0.60', () {
    test('0.45 — below the threshold is NOT a success', () {
      expect(isFirstWinSuccess(0.45), isFalse);
    });

    test('0.60 — exactly at the threshold IS a success (inclusive)', () {
      expect(isFirstWinSuccess(kFirstWinConfidenceThreshold), isTrue);
      expect(kFirstWinConfidenceThreshold, 0.60);
    });

    test('0.85 — above the threshold is a success', () {
      expect(isFirstWinSuccess(0.85), isTrue);
    });
  });

  group('A5 — the mic (fake motor) releases when the Stage is left', () {
    test('stop() runs once nothing watches the confidence provider', () async {
      final fake = FakeOnboardingFirstWinEngine();
      final container = ProviderContainer(
        overrides: [
          onboardingFirstWinEngineFactoryProvider.overrideWithValue(() => fake),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(
        onboardingFirstWinConfidenceProvider,
        (_, _) {},
      );
      expect(fake.isStarted, isTrue);
      expect(fake.isStopped, isFalse, reason: 'still mounted, still owns it');

      sub.close(); // "leaving the route" — nothing watches it any more
      await Future<void>.delayed(Duration.zero);

      expect(fake.isStopped, isTrue, reason: 'released, not left open');
    });
  });

  group('A3 — the mini Stage never lies about a weak signal', () {
    Future<FakeOnboardingFirstWinEngine> pumpStage(
      WidgetTester tester, {
      VoidCallback? onContinue,
    }) async {
      final fake = FakeOnboardingFirstWinEngine();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onboardingFirstWinEngineFactoryProvider.overrideWithValue(
              () => fake,
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: FirstWinStageScreen(onContinue: onContinue),
          ),
        ),
      );
      await tester.pump();
      return fake;
    }

    testWidgets('a weak (0.45) reading offers no Continue, only Retry', (
      tester,
    ) async {
      var continued = 0;
      final fake = await pumpStage(tester, onContinue: () => continued++);
      fake.emit(0.45);
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
      expect(continued, 0);
    });

    testWidgets('a genuine (0.85) reading offers Continue', (tester) async {
      final fake = await pumpStage(tester);
      fake.emit(0.85);
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
}
