import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/learn/screens/learn_screen.dart';
import 'package:music_theory/features/live/model/live_frame.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/live/providers/live_providers.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';

/// Round 92 — the retention loop's missing link: PASSING a lesson offers the
/// NEXT one right in the summary dialog (Yousician's core loop: finish →
/// next). Failing keeps the focus on "Play again"; one-off lessons (daily
/// challenge, Analyze imports) have no curriculum successor.
LiveFrame _strumFrame(int seq) => LiveFrame(
      current: null,
      next: null,
      latestStrum: const Strum(direction: StrumDirection.down, confidence: 1),
      bar: const [],
      bpm: 0,
      inputLevel: 0.5,
      tuningHz: 440,
      listening: true,
      strumSeq: seq,
    );

Future<void> _pump(WidgetTester tester, FakeStrumEngine engine) =>
    tester.pumpWidget(ProviderScope(
      overrides: [strumEngineProvider.overrideWithValue(engine)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LearnScreen(lesson: Lessons.firstStrums),
      ),
    ));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Lessons.nextAfter', () {
    test('walks the curriculum in order', () {
      expect(Lessons.nextAfter('first-strums')!.id, 'two-chord-change');
      expect(Lessons.nextAfter('two-chord-change')!.id, 'eighth-drive');
    });

    test('the last lesson and one-off lessons have no successor', () {
      expect(Lessons.nextAfter(Lessons.all.last.id), isNull);
      expect(Lessons.nextAfter('daily-3'), isNull);
      expect(Lessons.nextAfter('analyze-import'), isNull);
    });
  });

  testWidgets('a PASSED lesson offers "Next lesson" and it opens the '
      'curriculum successor', (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    await _pump(tester, engine);

    await tester.tap(find.text('Play'));
    await tester.pump();

    // First Strums: 70 BPM, 4 count-in beats, a down-stroke on every beat of
    // 4×4 bars → 16 events. Strike each one dead-on.
    const spb = 60.0 / 70.0;
    var elapsed = 0.0;
    var seq = 0;
    for (var k = 0; k < 16; k++) {
      final target = (4 + k) * spb + 0.01;
      await tester
          .pump(Duration(microseconds: ((target - elapsed) * 1e6).round()));
      elapsed = target;
      engine.emit(_strumFrame(++seq));
      await tester.pump();
    }
    // Cross the finish line (a few beats of tail, stepped to stay realistic).
    for (var i = 0; i < 8; i++) {
      await tester.pump(Duration(microseconds: (spb * 1e6).round()));
    }
    await tester.pump();

    expect(find.text('Passed! 🎉'), findsOneWidget);
    expect(find.text('Next lesson'), findsOneWidget);

    await tester.tap(find.text('Next lesson'));
    await tester.pumpAndSettle();
    expect(find.text('Two-Chord Change'), findsOneWidget);
  });

  testWidgets('a FAILED run keeps the focus on retrying — no next-lesson CTA',
      (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    await _pump(tester, engine);

    await tester.tap(find.text('Play'));
    await tester.pump();
    // Let the whole lesson pass by without a single strum.
    const spb = 60.0 / 70.0;
    for (var i = 0; i < 28; i++) {
      await tester.pump(Duration(microseconds: (spb * 1e6).round()));
    }
    await tester.pump();

    expect(find.text('Keep going!'), findsOneWidget);
    expect(find.text('Next lesson'), findsNothing);
  });
}
