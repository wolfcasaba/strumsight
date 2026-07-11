import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/learn/providers/lesson_progress_provider.dart';
import 'package:music_theory/features/learn/screens/lesson_list_screen.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 93 — the list-side half of the retention loop: a "Continue" hero
/// card at the top of the Learn home deep-links to the first unlocked,
/// not-yet-passed curriculum lesson. Also locks in the stale-list fix: the
/// screen must REBUILD when progress changes (it used to watch only the
/// notifier, so a pass recorded behind a pushed route never re-rendered
/// the unlock states).
Future<void> _pump(WidgetTester tester) => tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LessonListScreen(now: DateTime(2026, 7, 11)),
      ),
    ));

void main() {
  group('recommendedNext', () {
    test('fresh install points at the first lesson', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(lessonProgressProvider.notifier).recommendedNext()!
          .id, 'first-strums');
    });

    test('advances past passed lessons and is null when all are done',
        () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final progress = container.read(lessonProgressProvider.notifier);
      await progress.record('first-strums', 0.85);
      expect(progress.recommendedNext()!.id, 'two-chord-change');
      for (final l in Lessons.all) {
        await progress.record(l.id, 0.95);
      }
      expect(progress.recommendedNext(), isNull);
    });
  });

  testWidgets('the Learn home shows a Continue card for the next lesson',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('Continue'), findsOneWidget);
    // Named on the card AND as its own tile below.
    expect(find.text('First Strums'), findsNWidgets(2));
  });

  testWidgets('recording a pass MOVES the card — the list rebuilds on '
      'progress change', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
        tester.element(find.byType(LessonListScreen)));
    await container
        .read(lessonProgressProvider.notifier)
        .record('first-strums', 0.9);
    await tester.pumpAndSettle();

    expect(find.text('Two-Chord Change'), findsNWidgets(2),
        reason: 'the Continue card must follow the new progress');
  });

  testWidgets('all lessons passed → no Continue card', (tester) async {
    SharedPreferences.setMockInitialValues({
      'lesson_progress_v1':
          jsonEncode({for (final l in Lessons.all) l.id: 1.0}),
    });
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('Continue'), findsNothing);
  });
}
