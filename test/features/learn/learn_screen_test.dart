import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/chords/widgets/chord_diagram.dart';
import 'package:strumsight/features/learn/model/lesson.dart';
import 'package:strumsight/features/learn/providers/practice_speed_provider.dart';
import 'package:strumsight/features/learn/screens/learn_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

/// A practice-speed controller pinned to 75% (a stored preference), so the
/// LearnScreen's synchronous initState read is deterministic.
class _Speed75 extends PracticeSpeedController {
  @override
  double build() => 0.75;
}

Future<void> _pump(WidgetTester tester, FakeStrumEngine engine) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...preferenceOverrides(),
          strumEngineProvider.overrideWithValue(engine),
        ],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LearnScreen(lesson: Lessons.firstStrums),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('starts paused, then plays and scores without settling', (
    tester,
  ) async {
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

  testWidgets('opens at the persisted practice speed (round 132)', (
    tester,
  ) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    // The learner last drilled at 75% — the screen's initState reads the
    // (here overridden) persisted speed, so it must open there, not 100%.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...preferenceOverrides(),
          strumEngineProvider.overrideWithValue(engine),
          practiceSpeedProvider.overrideWith(_Speed75.new),
        ],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LearnScreen(lesson: Lessons.firstStrums),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '75%'))
          .selected,
      isTrue,
      reason: 'the screen restored the persisted 75% drill speed',
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '100%'))
          .selected,
      isFalse,
    );
  });

  testWidgets('jam mode can be toggled from the app bar', (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    await _pump(tester, engine);

    // The jam (backing) toggle is present and toggling it doesn't throw.
    expect(find.byIcon(Icons.music_note), findsOneWidget);
    await tester.tap(find.byIcon(Icons.music_note));
    await tester.pump();
    expect(find.byIcon(Icons.music_note), findsOneWidget);
  });

  testWidgets('easy mode can be toggled from the app bar', (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...preferenceOverrides(),
          strumEngineProvider.overrideWithValue(engine),
        ],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LearnScreen(lesson: Lessons.downUpGroove), // simplifies
        ),
      ),
    );

    expect(find.byIcon(Icons.school_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.school_outlined));
    await tester.pump();
    // Toggling doesn't throw and keeps the tempo (simplify preserves BPM).
    expect(find.byIcon(Icons.school_outlined), findsOneWidget);
    expect(find.text('90 BPM'), findsOneWidget);
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
