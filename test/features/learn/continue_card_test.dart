import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/learn/model/lesson.dart';
import 'package:strumsight/features/learn/providers/lesson_progress_provider.dart';
import 'package:strumsight/features/learn/screens/lesson_list_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';

import '../../support/preference_store.dart';

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

/// Round 93 — the list-side half of the retention loop: a "Continue" hero
/// card at the top of the Learn home deep-links to the first unlocked,
/// not-yet-passed curriculum lesson. Also locks in the stale-list fix: the
/// screen must REBUILD when progress changes (it used to watch only the
/// notifier, so a pass recorded behind a pushed route never re-rendered
/// the unlock states).
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
          home: LessonListScreen(now: DateTime(2026, 7, 11)),
        ),
      ),
    );

void main() {
  group('recommendedNext', () {
    test('fresh install points at the first lesson', () async {
      final container = ProviderContainer(overrides: preferenceOverrides());
      addTearDown(container.dispose);
      expect(
        container.read(lessonProgressProvider.notifier).recommendedNext()!.id,
        'first-strums',
      );
    });

    test(
      'advances past passed lessons and is null when all are done',
      () async {
        final container = ProviderContainer(overrides: preferenceOverrides());
        addTearDown(container.dispose);
        final progress = container.read(lessonProgressProvider.notifier);
        await progress.record('first-strums', 0.85);
        expect(progress.recommendedNext()!.id, 'two-chord-change');
        for (final l in Lessons.all) {
          await progress.record(l.id, 0.95);
        }
        expect(progress.recommendedNext(), isNull);
      },
    );
  });

  testWidgets('the Learn home shows a Continue card for the next lesson', (
    tester,
  ) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('Continue'), findsOneWidget);
    // Named on the card AND as its own tile below.
    expect(find.text('First Strums'), findsNWidgets(2));
  });

  testWidgets('recording a pass MOVES the card — the list rebuilds on '
      'progress change', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LessonListScreen)),
    );
    await container
        .read(lessonProgressProvider.notifier)
        .record('first-strums', 0.9);
    await tester.pumpAndSettle();

    expect(
      find.text('Two-Chord Change'),
      findsNWidgets(2),
      reason: 'the Continue card must follow the new progress',
    );
  });

  testWidgets('all lessons passed → no Continue card', (tester) async {
    await _pump(tester, {
      StorageKeys.lessonProgress: storedDocument({
        for (final l in Lessons.all) l.id: 1.0,
      }),
    });
    await tester.pumpAndSettle();

    expect(find.text('Continue'), findsNothing);
  });
}
