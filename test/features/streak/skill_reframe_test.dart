import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/progress/model/practice_entry.dart';
import 'package:music_theory/features/progress/providers/practice_log_provider.dart';
import 'package:music_theory/features/streak/screens/streak_screen.dart';
import 'package:music_theory/features/streak/streak_logic.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 152 — the streak→SKILL reframe (chunk 013 #2 TODO, Simply's
/// evidence: a growing-skill narrative retains more durably than pure
/// loss-aversion). The flame is what you protect; this section is what
/// you BUILT.
class _SeededLog extends PracticeLogController {
  _SeededLog(this._seed);
  final List<PracticeEntry> _seed;
  @override
  List<PracticeEntry> build() {
    super.build(); // opens the r150 write gate (mock prefs are empty)
    return _seed;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final now = DateTime(2026, 7, 12, 12);
  final today = StreakLogic.epochDayOf(now);

  Widget app(List<PracticeEntry> entries) => ProviderScope(
        overrides: [
          practiceLogProvider.overrideWith(() => _SeededLog(entries)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: StreakScreen(now: now),
        ),
      );

  testWidgets('shows skill stats with an accuracy trend arrow',
      (tester) async {
    await tester.pumpWidget(app([
      // Last week: 70% accuracy.
      PracticeEntry(
          day: today - 8,
          source: PracticeSource.learn,
          seconds: 300,
          strokes: 50,
          directionAccuracy: 0.7),
      // This week: 90% — improving.
      PracticeEntry(
          day: today - 1,
          source: PracticeSource.learn,
          seconds: 600,
          strokes: 120,
          directionAccuracy: 0.9),
    ]));
    await tester.pump();

    expect(find.text('YOUR SKILL'), findsOneWidget);
    expect(find.text('170'), findsOneWidget); // total strums, all time
    expect(find.text('10 min'), findsOneWidget); // this week only
    expect(find.text('90% ▲'), findsOneWidget,
        reason: 'this week beat last week — the trend must say so');
  });

  testWidgets('the skill section hides while there is nothing built yet',
      (tester) async {
    await tester.pumpWidget(app(const []));
    await tester.pump();
    expect(find.text('YOUR SKILL'), findsNothing,
        reason: 'zeros would demotivate — hide until real practice exists');
  });
}
