import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/chords/chord_shape.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/onboarding/screens/onboarding_screen.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 155 — the onboarding "first win" (chunk 017 rec #4): the shortest
/// route from install to a SCORED strum, inside the first two minutes.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the first-win lesson is a true 30-second starter', () {
    final l = Lessons.firstWin;
    expect(l.events, isNotEmpty);
    expect(l.events.every((e) => e.direction == StrumDirection.down), isTrue,
        reason: 'downstrokes only — nothing to fail on but the beat');
    expect(l.events.map((e) => e.chord).toSet(), {'Em'},
        reason: 'one easy chord');
    expect(ChordShapes.has('Em'), isTrue,
        reason: 'the diagram must render for the very first screen');
    final seconds = l.totalBeats * 60 / l.bpm;
    expect(seconds, lessThanOrEqualTo(35),
        reason: 'a first win must be ~30 seconds, not a commitment');
    expect(Lessons.all.map((x) => x.id), isNot(contains('first-win')),
        reason: 'outside the curriculum/unlock chain');
  });

  test('a passed first win funnels into the curriculum (r159)', () {
    final next = Lessons.nextAfter('first-win');
    expect(next, isNotNull,
        reason: 'the finish dialog must offer the first real lesson, '
            'not dead-end a brand-new user on "Play again"');
    expect(next!.id, Lessons.all.first.id);
  });

  testWidgets('the last page leads with the first-win CTA', (tester) async {
    var firstWin = 0;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OnboardingScreen(
          onDone: () {},
          onFirstWin: () => firstWin++,
          primeMic: () async {},
        ),
      ),
    ));
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
}
