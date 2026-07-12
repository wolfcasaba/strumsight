import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/progress/model/practice_stats.dart';
import 'package:music_theory/features/progress/widgets/weekly_bars.dart';
import 'package:music_theory/l10n/app_localizations.dart';

/// Round 127 — the weekly bar chart used to expose only disconnected "12" /
/// "M" text fragments to a screen reader (no unit, no full day). Each bar is
/// now one Semantics node stating the day and minutes.
void main() {
  Future<void> pump(WidgetTester tester, List<DayTotal> days) =>
      tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: WeeklyBars(days: days)),
      ));

  testWidgets('each bar speaks its weekday and minutes as one fact',
      (tester) async {
    final handle = tester.ensureSemantics();
    // epoch day 19723 = 2024-01-01 = a Monday (the widget derives the weekday
    // purely from the integer, so this is timezone-stable).
    await pump(tester, const [
      DayTotal(day: 19723, seconds: 720, sessions: 1), // Monday, 12 min
      DayTotal(day: 19724, seconds: 0, sessions: 0), // Tuesday, idle
    ]);

    expect(find.bySemanticsLabel('Monday: 12 minutes practised'),
        findsOneWidget);
    expect(find.bySemanticsLabel('Tuesday: 0 minutes practised'),
        findsOneWidget);
    // The bare single-letter glyph must NOT leak as its own semantics node.
    expect(find.bySemanticsLabel('M'), findsNothing);
    handle.dispose();
  });
}
