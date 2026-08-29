import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/learn/model/lesson.dart';
import 'package:strumsight/features/learn/screens/lesson_list_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';

import '../../support/preference_store.dart';

/// A3/A5/A8 (ADR 0282 §3/§5, §0.0/R11/R13) — the migrated learning path must
/// (a) name WHICH lesson unlocks a locked one, never a bare "locked" dead
/// end, (b) keep the accessible LINEAR list as the curriculum's structure —
/// no separate graphical path is required to reach any lesson, and (c) never
/// lose progress recorded before this round.

FeatureFlags _flags() => const FeatureFlags(
  accountEnabled: false,
  diagnosticsEnabled: false,
  labModeAvailable: false,
);

AppConfig _config(FeatureFlags flags) => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: flags,
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

Future<void> _pump(WidgetTester tester, [Map<String, Object>? stored]) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...preferenceOverrides(stored),
          appConfigProvider.overrideWithValue(_config(_flags())),
        ],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LessonListScreen(now: DateTime(2026, 8, 26)),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'A3: a locked lesson names WHICH lesson unlocks it, not just "locked"',
    (tester) async {
      await _pump(tester);
      await tester.pumpAndSettle();

      final tier = Lessons.byDifficulty(Difficulty.beginner);
      // The second lesson of the tier is locked on a fresh install; its
      // subtitle must already state the requirement, with no tap needed
      // (ADR 0282 §3 — the reason must ALWAYS show, not hide behind a tap
      // a disabled/locked tile can never receive).
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, tier[1].name),
          matching: find.textContaining(tier[0].name),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('A8: the curriculum is a single linear, accessible list — no '
      'separate graphical path is required to reach any lesson', (
    tester,
  ) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    // Exactly one linear container carries every tier — scrolling it top to
    // bottom (never panning a 2-D canvas) reaches every tier in curriculum
    // order, ending at the final tier's final lesson.
    expect(find.byType(ListView), findsOneWidget);
    await tester.scrollUntilVisible(find.text('INTERMEDIATE'), 200);
    expect(find.text('INTERMEDIATE'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('ADVANCED'), 200);
    expect(find.text('ADVANCED'), findsOneWidget);
    final lastLesson = Lessons.byDifficulty(Difficulty.advanced).last;
    final lastTile = find.byKey(ValueKey('lesson-tile-${lastLesson.id}'));
    await tester.scrollUntilVisible(lastTile, 200);
    expect(lastTile, findsOneWidget);
  });

  testWidgets(
    'A5: progress recorded before this round still shows — stars and the '
    'next unlocked tier survive the migrated screen',
    (tester) async {
      final tier = Lessons.byDifficulty(Difficulty.beginner);
      await _pump(tester, {
        StorageKeys.lessonProgress: storedDocument({
          tier[0].id: 0.9,
          tier[1].id: 0.75,
        }),
      });
      await tester.pumpAndSettle();

      // Both passed lessons show their stars…
      expect(find.byIcon(Icons.star), findsWidgets);
      // …and the THIRD lesson — unlocked only by the pre-existing pass of
      // the second — is reachable, not locked behind a reset progress map.
      final thirdTile = find.byKey(ValueKey('lesson-tile-${tier[2].id}'));
      await tester.scrollUntilVisible(thirdTile, 200);
      expect(
        find.descendant(of: thirdTile, matching: find.byIcon(Icons.lock)),
        findsNothing,
        reason: 'the third lesson must be UNLOCKED, not reset to locked',
      );
    },
  );
}
