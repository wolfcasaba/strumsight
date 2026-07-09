import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/chords/widgets/chord_diagram.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/learn/screens/learn_screen.dart';
import 'package:music_theory/features/live/providers/live_providers.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';

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

  testWidgets('starts paused, then plays and scores without settling',
      (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    await _pump(tester, engine);

    // Paused: Play control + lesson header (chords/BPM), no score HUD yet.
    expect(find.text('Play'), findsOneWidget);
    expect(find.textContaining('Chords'), findsOneWidget);
    // The current chord's fretting diagram is shown (First Strums starts on Em).
    expect(find.byType(ChordDiagram), findsOneWidget);

    await tester.tap(find.text('Play'));
    await tester.pump(); // _playing = true; engine.start()
    expect(find.text('Pause'), findsOneWidget);
    expect(engine.startCalls, greaterThan(0));

    // Advance the ticker; the score HUD appears (0 hits so far).
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Combo'), findsOneWidget);

    // Pause to leave no active ticker at teardown.
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('the metronome can be muted from the app bar', (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    await _pump(tester, engine);

    expect(find.byIcon(Icons.volume_up), findsOneWidget);
    await tester.tap(find.byIcon(Icons.volume_up));
    await tester.pump();
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
  });

  testWidgets('practice-speed control scales the tempo', (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    await _pump(tester, engine); // First Strums = 70 BPM

    expect(find.text('70 BPM'), findsOneWidget);
    await tester.tap(find.text('50%'));
    await tester.pump();
    expect(find.text('35 BPM'), findsOneWidget); // 70 × 0.5
  });
}
