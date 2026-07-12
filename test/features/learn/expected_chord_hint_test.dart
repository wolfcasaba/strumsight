import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/learn/screens/learn_screen.dart';
import 'package:music_theory/features/live/providers/live_providers.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';

/// Round 137 — the expected-target prior's Learn wiring (chunk 016 rec #1):
/// while a lesson plays, the engine is HINTED with the chord the player is
/// supposed to fret, and the hint is CLEARED when the screen goes away so no
/// stale bias ever leaks into free-play Live detection.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('playing a lesson hints the target chord; leaving clears it',
      (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    final lesson = Lessons.all.first;
    final firstChord =
        lesson.events.firstWhere((e) => e.chord.isNotEmpty).chord;

    await tester.pumpWidget(ProviderScope(
      overrides: [strumEngineProvider.overrideWithValue(engine)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LearnScreen(lesson: lesson),
      ),
    ));
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50)); // one ticker frame

    expect(engine.expectedChordCalls, contains(firstChord),
        reason: 'the count-in pre-roll must already hint the first chord');

    // Leaving the screen must clear the hint — a lesson bias left behind
    // would silently skew free-play Live detection afterwards.
    await tester.pumpWidget(const SizedBox());
    expect(engine.expectedChordCalls.last, isNull,
        reason: 'dispose must clear the expected-chord hint');
  });
}
