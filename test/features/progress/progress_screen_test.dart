import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/progress/model/practice_entry.dart';
import 'package:music_theory/features/progress/providers/practice_log_provider.dart';
import 'package:music_theory/features/progress/screens/progress_screen.dart';
import 'package:music_theory/features/progress/widgets/weekly_bars.dart';
import 'package:music_theory/features/streak/streak_logic.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A log seeded with fixed entries and NOT touching disk (so the populated
/// dashboard is deterministic in a widget test).
class _SeededLog extends PracticeLogController {
  _SeededLog(this._seed);
  final List<PracticeEntry> _seed;
  @override
  List<PracticeEntry> build() => _seed;
}

Widget _host(DateTime now, {List<PracticeEntry>? seed}) => ProviderScope(
      overrides: [
        if (seed != null)
          practiceLogProvider.overrideWith(() => _SeededLog(seed)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProgressScreen(now: now),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final now = DateTime(2026, 7, 9);
  final today = StreakLogic.epochDayOf(now);

  testWidgets('empty log shows the empty-state nudge, no chart', (tester) async {
    await tester.pumpWidget(_host(now));
    await tester.pump();
    expect(find.textContaining('your progress shows up here'), findsOneWidget);
    expect(find.byType(WeeklyBars), findsNothing);
  });

  testWidgets('populated log shows totals, weekly chart, strum accuracy',
      (tester) async {
    await tester.pumpWidget(_host(now, seed: [
      PracticeEntry(
        day: today,
        source: PracticeSource.learn,
        seconds: 120,
        strokes: 10,
        chords: 3,
        directionAccuracy: 0.8,
      ),
      PracticeEntry(
        day: today,
        source: PracticeSource.analyze,
        seconds: 60,
        strokes: 5,
      ),
      PracticeEntry(
        day: today - 1,
        source: PracticeSource.live,
        seconds: 90,
        strokes: 8,
      ),
    ]));
    await tester.pump();

    // Total practice = 270s = 4m.
    expect(find.text('4m'), findsOneWidget);
    // Daily goal card (default 10 min; today has 180s = 3 min → not met).
    expect(find.text('Daily goal'), findsOneWidget);
    expect(find.textContaining('3 of 10 min'), findsOneWidget);
    // Weekly chart is rendered (7 days).
    expect(find.byType(WeeklyBars), findsOneWidget);
    // The moat metric with its scored value (below the fold → scroll to it).
    await tester.scrollUntilVisible(find.text('Strum-direction accuracy'), 120,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Strum-direction accuracy'), findsOneWidget);
    expect(find.text('80%'), findsWidgets);
    // Source breakdown (below the fold in a 600px viewport) lists all three
    // practice surfaces — scroll it into view first.
    await tester.scrollUntilVisible(find.text('Live'), 120,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Learn'), findsOneWidget);
    expect(find.text('Analyze'), findsOneWidget);
  });

  testWidgets('daily goal shows "reached" once today crosses the target',
      (tester) async {
    await tester.pumpWidget(_host(now, seed: [
      PracticeEntry(
        day: today,
        source: PracticeSource.learn,
        seconds: 700, // > default 10-min goal
        strokes: 40,
        directionAccuracy: 0.9,
      ),
    ]));
    await tester.pump();
    expect(find.text('Goal reached today 🎉'), findsOneWidget);
  });

  testWidgets('with practice but no scored run, prompts to score in Learn',
      (tester) async {
    await tester.pumpWidget(_host(now, seed: [
      PracticeEntry(
        day: today,
        source: PracticeSource.analyze,
        seconds: 60,
        strokes: 5,
      ),
    ]));
    await tester.pump();
    await tester.scrollUntilVisible(find.textContaining('Pass a lesson'), 120,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Pass a lesson'), findsOneWidget);
  });
}
