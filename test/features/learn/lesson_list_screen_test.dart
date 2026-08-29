import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/features/learn/model/lesson.dart';
import 'package:strumsight/features/learn/providers/lesson_progress_provider.dart';
import 'package:strumsight/features/learn/screens/lesson_list_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';

import '../../support/preference_store.dart';

FeatureFlags _flags({
  bool practiceEngineV2Enabled = false,
  bool songTrainerV2Enabled = false,
}) => FeatureFlags(
  accountEnabled: false,
  diagnosticsEnabled: false,
  labModeAvailable: false,
  practiceEngineV2Enabled: practiceEngineV2Enabled,
  songTrainerV2Enabled: songTrainerV2Enabled,
);

AppConfig _config(FeatureFlags flags) => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: flags,
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

Future<void> _pump(
  WidgetTester tester, {
  FeatureFlags? flags,
  GoRouter? router,
  Locale locale = const Locale('en'),
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      ...preferenceOverrides(),
      appConfigProvider.overrideWithValue(_config(flags ?? _flags())),
    ],
    child: router == null
        ? MaterialApp(
            theme: SsLightTheme.data(),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LessonListScreen(now: DateTime(2026, 7, 9)),
          )
        : MaterialApp.router(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
  ),
);

GoRouter _router() => GoRouter(
  initialLocation: AppRoutes.learn,
  routes: [
    GoRoute(
      path: AppRoutes.learn,
      builder: (_, _) => LessonListScreen(now: DateTime(2026, 7, 9)),
    ),
    GoRoute(
      path: AppRoutes.practiceHub,
      builder: (_, _) => const Scaffold(body: SizedBox()),
    ),
    GoRoute(
      path: AppRoutes.songTrainerLibrary,
      builder: (_, _) => const Scaffold(body: SizedBox()),
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('groups lessons by tier and locks the un-earned ones', (
    tester,
  ) async {
    await _pump(tester);
    await tester.pump();

    // The Beginner tier header + its first (unlocked) lesson are on screen —
    // named twice since round 93: on the Continue card AND its own tile.
    expect(find.text('BEGINNER'), findsOneWidget);
    expect(find.text('First Strums'), findsNWidgets(2));
    // …and later lessons are locked.
    expect(find.byIcon(Icons.lock), findsWidgets);

    // Scroll down to confirm the Advanced tier renders too.
    await tester.scrollUntilVisible(find.text('ADVANCED'), 200);
    expect(find.text('ADVANCED'), findsOneWidget);
  });

  testWidgets('passing a lesson unlocks the next (lock clears)', (
    tester,
  ) async {
    final tier = Lessons.byDifficulty(Difficulty.beginner);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...preferenceOverrides(),
          appConfigProvider.overrideWithValue(_config(_flags())),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            // Pre-pass the first beginner lesson.
            return FutureBuilder(
              future: ref
                  .read(lessonProgressProvider.notifier)
                  .record(tier[0].id, 0.85),
              builder: (_, _) => MaterialApp(
                theme: SsLightTheme.data(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: LessonListScreen(now: DateTime(2026, 7, 9)),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The second beginner lesson is now unlocked → it is the Continue card's
    // target (round 93) plus its own tile, and stars from the passed first
    // lesson show somewhere in the list.
    expect(find.text(tier[1].name), findsNWidgets(2));
    expect(find.byIcon(Icons.star), findsWidgets); // first lesson earned stars
  });

  for (final cell in const [
    (practice: false, songTrainer: false),
    (practice: true, songTrainer: false),
    (practice: false, songTrainer: true),
    (practice: true, songTrainer: true),
  ]) {
    testWidgets(
      'V2 entries follow practice=${cell.practice}, songTrainer=${cell.songTrainer}',
      (tester) async {
        await _pump(
          tester,
          flags: _flags(
            practiceEngineV2Enabled: cell.practice,
            songTrainerV2Enabled: cell.songTrainer,
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const Key('learn-entry-practice-hub')),
          cell.practice ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('learn-entry-song-trainer')),
          cell.songTrainer ? findsOneWidget : findsNothing,
        );
      },
    );
  }

  testWidgets('production factory flags hide both V2 entries', (tester) async {
    await _pump(
      tester,
      flags: FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('learn-entry-practice-hub')), findsNothing);
    expect(find.byKey(const Key('learn-entry-song-trainer')), findsNothing);
  });

  testWidgets('Practice Hub entry pushes the Practice Hub route', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    await _pump(
      tester,
      flags: _flags(practiceEngineV2Enabled: true, songTrainerV2Enabled: true),
      router: router,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('learn-entry-practice-hub')));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppRoutes.practiceHub);
  });

  testWidgets('Song Trainer entry pushes the Song Trainer route', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    await _pump(
      tester,
      flags: _flags(practiceEngineV2Enabled: true, songTrainerV2Enabled: true),
      router: router,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('learn-entry-song-trainer')));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppRoutes.songTrainerLibrary);
  });

  for (final locale in [const Locale('en'), const Locale('hu')]) {
    testWidgets('E15-R04: textScaler 2.0 renders without overflow '
        '(${locale.languageCode})', (tester) async {
      tester.view.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(
        tester,
        flags: _flags(
          practiceEngineV2Enabled: true,
          songTrainerV2Enabled: true,
        ),
        locale: locale,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
