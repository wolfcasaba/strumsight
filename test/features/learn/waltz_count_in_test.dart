import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/learn/screens/learn_screen.dart';
import 'package:music_theory/features/live/providers/live_providers.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';

/// Round 111 — the count-in must be ONE BAR of the lesson's own metre:
/// counting "1-2-3-4" into a 3/4 waltz is musically wrong (and misaligns
/// the player's internal clock with the downbeat).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a 3/4 lesson counts in 1-2-3 — never a fourth beat',
      (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [strumEngineProvider.overrideWithValue(engine)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LearnScreen(lesson: Lessons.waltzTime),
      ),
    ));
    await tester.tap(find.text('Play'));
    await tester.pump();

    const spb = 60.0 / 84.0; // Waltz Time BPM
    // 2.5 beats in: the LAST count of a one-bar 3/4 count-in.
    await tester
        .pump(Duration(microseconds: (2.5 * spb * 1e6).round()));
    expect(find.text('3'), findsOneWidget);

    // 3.2 beats in: play has started — the old 4-beat count-in would still
    // be showing "4" here.
    await tester
        .pump(Duration(microseconds: (0.7 * spb * 1e6).round()));
    expect(find.text('4'), findsNothing,
        reason: 'a waltz has no fourth count');
  });
}
