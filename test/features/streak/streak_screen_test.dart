import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/streak/daily_challenge.dart';
import 'package:music_theory/features/streak/screens/streak_screen.dart';
import 'package:music_theory/features/streak/streak_logic.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the streak state and today\'s challenge', (tester) async {
    final now = DateTime(2026, 7, 9);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StreakScreen(now: now),
      ),
    ));
    await tester.pump();

    // Default (no practice yet) → "No streak yet" + a start nudge.
    expect(find.text('No streak yet'), findsOneWidget);
    expect(find.textContaining('Longest'), findsOneWidget);
    expect(find.textContaining('Freezes'), findsOneWidget);

    // Today's challenge card names the deterministic pattern for this day.
    final challenge = DailyChallenge.forDay(StreakLogic.epochDayOf(now));
    expect(find.text(challenge.name), findsOneWidget);
    // One arrow icon per stroke in the pattern.
    final arrows = tester
        .widgetList<Icon>(find.byType(Icon))
        .where((i) =>
            i.icon == Icons.arrow_downward || i.icon == Icons.arrow_upward)
        .length;
    expect(arrows, challenge.pattern.length);

    expect(find.text('Try it in Live'), findsOneWidget);
  });
}
