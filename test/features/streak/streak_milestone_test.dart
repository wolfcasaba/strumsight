import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/streak/data/streak_repository.dart';
import 'package:strumsight/features/streak/model/streak_data.dart';
import 'package:strumsight/features/streak/screens/streak_screen.dart';
import 'package:strumsight/features/streak/streak_logic.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

/// Ch18 spec §11 — the streak home: the hero is an `SsFlame` L, a
/// 7/30/100-day streak carries the milestone pill, an ordinary day does
/// not, and the staggered entrance is finite (settles with every section
/// on screen).
class _SeededStreak implements StreakRepository {
  _SeededStreak(this.data);
  StreakData? data;

  @override
  StreakData? load() => data;

  @override
  Future<void> save(StreakData streak) async => data = streak;
}

void main() {
  final now = DateTime(2026, 7, 12, 12);
  final today = StreakLogic.epochDayOf(now);

  Widget app(StreakData streak) => ProviderScope(
    overrides: [
      ...preferenceOverrides(),
      streakRepositoryProvider.overrideWithValue(_SeededStreak(streak)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StreakScreen(now: now),
    ),
  );

  testWidgets('a 7-day streak shows the milestone pill under the flame', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(StreakData(current: 7, longest: 7, lastPracticeDay: today)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SsFlame), findsOneWidget);
    expect(find.byKey(const Key('streak-milestone-pill')), findsOneWidget);
    expect(find.text('7-day milestone 🎉'), findsOneWidget);
    expect(find.text('7-day streak'), findsOneWidget);
  });

  testWidgets('an ordinary day has the flame but no pill', (tester) async {
    await tester.pumpWidget(
      app(StreakData(current: 5, longest: 9, lastPracticeDay: today)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SsFlame), findsOneWidget);
    expect(find.byKey(const Key('streak-milestone-pill')), findsNothing);
    expect(find.textContaining('milestone'), findsNothing);
  });

  testWidgets('the entrance is finite and every section lands', (tester) async {
    await tester.pumpWidget(app(const StreakData()));
    // First frame: the hero has not faded in yet.
    final hero = find.ancestor(
      of: find.byType(SsFlame),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(hero.first).opacity, 0);

    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(hero.first).opacity, 1);
    expect(find.text('No streak yet'), findsOneWidget);
    expect(find.text('Play along'), findsOneWidget);
    expect(find.byType(SsStaggeredEntrance), findsOneWidget);
  });
}
