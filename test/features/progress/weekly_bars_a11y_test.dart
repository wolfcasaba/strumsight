import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/epoch_day.dart';
import 'package:strumsight/features/progress/model/practice_stats.dart';
import 'package:strumsight/features/progress/widgets/weekly_bars.dart';
import 'package:strumsight/features/streak/streak_logic.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// Round 127 — the weekly bar chart used to expose only disconnected "12" /
/// "M" text fragments to a screen reader (no unit, no full day). Each bar is
/// now one Semantics node stating the day and minutes.
void main() {
  Future<void> pump(WidgetTester tester, List<DayTotal> days) =>
      tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: WeeklyBars(days: days)),
        ),
      );

  testWidgets('each bar speaks its weekday and minutes as one fact', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    // The day integers come from the canonical conversion (not a literal), so
    // this pins WeeklyBars' label to that convention on every device rather
    // than to a number someone typed. 2024-01-01 is a Monday.
    final monday = EpochDay.of(DateTime(2024, 1, 1, 12));
    await pump(tester, [
      DayTotal(day: monday, seconds: 720, sessions: 1), // Monday, 12 min
      DayTotal(day: monday + 1, seconds: 0, sessions: 0), // Tuesday, idle
    ]);

    expect(
      find.bySemanticsLabel('Monday: 12 minutes practised'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Tuesday: 0 minutes practised'),
      findsOneWidget,
    );
    // The bare single-letter glyph must NOT leak as its own semantics node.
    expect(find.bySemanticsLabel('M'), findsNothing);
    handle.dispose();
  });

  testWidgets('a bar names the weekday the session was actually recorded on', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    // ADR 0583, end to end. The chart is a two-sided contract: the PRODUCER
    // (`StreakLogic.epochDayOf`, which is what every recording path stores)
    // and the CONSUMER (`WeeklyBars`' weekday label) must read the same
    // integer the same way. `WeeklyBars` itself is unchanged by that ADR — the
    // label was always read off the true epoch day; what moved is the integer
    // reaching it.
    //
    // The offset is explicit, so this measures the defect rather than the
    // runner: at +02:00 the old conversion answered one day less for this
    // instant and the bar announced THURSDAY.
    const utcPlus2 = Duration(hours: 2);
    // 2026-09-18 is a Friday; 07:30 in Budapest is 05:30 UTC.
    final recordedOnAFriday = DateTime.utc(2026, 9, 18, 5, 30);
    final friday = StreakLogic.epochDayOf(
      recordedOnAFriday,
      utcOffset: utcPlus2,
    );

    await pump(tester, [DayTotal(day: friday, seconds: 1500, sessions: 1)]);

    expect(
      find.bySemanticsLabel('Friday: 25 minutes practised'),
      findsOneWidget,
      reason:
          'the chart must name the local calendar day the user practised '
          'on, not the day before it',
    );
    // Second, so the label above is what fails when the producer regresses:
    // the integer it announced is the whole story.
    expect(
      friday,
      EpochDay.ofCalendarDate(2026, 9, 18),
      reason: 'the producer must answer the day the user actually practised',
    );
    handle.dispose();
  });
}
