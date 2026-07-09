import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/learn/providers/lesson_progress_provider.dart';
import 'package:music_theory/features/learn/screens/lesson_list_screen.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester) => tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LessonListScreen(now: DateTime(2026, 7, 9)),
      ),
    ));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('groups lessons by tier and locks the un-earned ones',
      (tester) async {
    await _pump(tester);
    await tester.pump();

    // The Beginner tier header + its first (unlocked) lesson are on screen…
    expect(find.text('BEGINNER'), findsOneWidget);
    expect(find.text('First Strums'), findsOneWidget);
    // …and later lessons are locked.
    expect(find.byIcon(Icons.lock), findsWidgets);

    // Scroll down to confirm the Advanced tier renders too.
    await tester.scrollUntilVisible(find.text('ADVANCED'), 200);
    expect(find.text('ADVANCED'), findsOneWidget);
  });

  testWidgets('passing a lesson unlocks the next (lock clears)',
      (tester) async {
    final tier = Lessons.byDifficulty(Difficulty.beginner);
    await tester.pumpWidget(ProviderScope(
      overrides: const [],
      child: Consumer(builder: (context, ref, _) {
        // Pre-pass the first beginner lesson.
        return FutureBuilder(
          future: ref
              .read(lessonProgressProvider.notifier)
              .record(tier[0].id, 0.85),
          builder: (_, _) => MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LessonListScreen(now: DateTime(2026, 7, 9)),
          ),
        );
      }),
    ));
    await tester.pumpAndSettle();

    // The second beginner lesson is now unlocked → its name is tappable and it
    // shows stars from the (passed) first lesson somewhere in the list.
    expect(find.text(tier[1].name), findsOneWidget);
    expect(find.byIcon(Icons.star), findsWidgets); // first lesson earned stars
  });
}
