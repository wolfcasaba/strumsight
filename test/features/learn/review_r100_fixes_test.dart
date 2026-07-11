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

/// Round 100 — the two RISK findings of the sprint-88–99 adversarial review.
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

Future<void> _playToPass(WidgetTester tester, FakeStrumEngine engine) async {
  await tester.tap(find.text('Play'));
  await tester.pump();
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
  for (var i = 0; i < 8; i++) {
    await tester.pump(Duration(microseconds: (spb * 1e6).round()));
  }
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('an EASY-mode pass must NOT offer "Next lesson" — Easy '
      'deliberately does not advance the curriculum', (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    await _pump(tester, engine);

    // Easy mode on (First Strums is all on-beat downs, so the event list is
    // unchanged — only the progression policy differs).
    await tester.tap(find.byIcon(Icons.school_outlined));
    await tester.pump();

    await _playToPass(tester, engine);

    expect(find.text('Passed! 🎉'), findsOneWidget);
    expect(find.text('Next lesson'), findsNothing,
        reason: 'Easy passes must not walk a locked curriculum');
  });

  testWidgets('switching to Jam mid-play releases the mic — the frame '
      'subscription must close, not idle behind the backing', (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    await _pump(tester, engine);

    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(engine.startCalls, greaterThan(0));

    // Toggle Jam while playing: scoring stops AND the autoDispose frame
    // provider must lose its last listener → the engine stops.
    await tester.tap(find.byIcon(Icons.music_note));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(engine.stopCalls, greaterThan(0),
        reason: 'jam mode must not keep the mic open');
  });
}
