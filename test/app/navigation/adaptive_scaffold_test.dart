// E13-R08 (ADR 0275) — A1, A4, A6.
//
// A1: the five adaptive-shell destinations + eleven target sub-routes are
// reachable exactly once when `adaptiveShellEnabled` is on, the flag
// defaults to OFF, and it is carried through all six `FeatureFlags`
// extension points (brief §0.0 D2).
// A4: primary navigation is hidden on the pinned Stage-route set, both at
// the pure-predicate level and at the shell-widget level (anti-vacuum,
// L403, brief §0.0 D13).
// A6: the breakpoint resolver picks the right navigation form from
// `SsBreakpoints` tokens alone (brief §6.2).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/home_shell.dart';
import 'package:strumsight/app/routing/adaptive_shell_routes.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/platform/screen_wakelock.dart';
import 'package:strumsight/features/analyze/screens/analyze_screen.dart';
import 'package:strumsight/features/chords/screens/chord_library_screen.dart';
import 'package:strumsight/features/learn/screens/lesson_list_screen.dart';
import 'package:strumsight/features/library_v2/screens/unified_library_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/metronome/screens/metronome_screen.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice_hub/screens/practice_area_hub_screen.dart';
import 'package:strumsight/features/profile_hub/screens/profile_hub_screen.dart';
import 'package:strumsight/features/progress/screens/progress_screen.dart';
import 'package:strumsight/features/settings/screens/settings_screen.dart';
import 'package:strumsight/features/songs/screens/setlist_list_screen.dart';
import 'package:strumsight/features/songs/screens/song_list_screen.dart';
import 'package:strumsight/features/streak/screens/streak_screen.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_home_screen.dart';
import 'package:strumsight/features/today/screens/today_hub_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

class _RouterTestApp extends ConsumerWidget {
  const _RouterTestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      theme: SsLightTheme.data(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

Future<GoRouter> _pumpAdaptiveRouter(
  WidgetTester tester, {
  bool adaptiveShellEnabled = true,
  bool practiceEngineV2Enabled = false,
  bool aiTutorEnabled = false,
  Size? size,
  ScreenWakelock? wakelock,
}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  final liveEngine = FakeStrumEngine();
  final tunerEngine = FakeTunerEngine();
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(wakelock: wakelock),
      strumEngineProvider.overrideWithValue(liveEngine),
      tunerEngineProvider.overrideWithValue(tunerEngine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: true,
            labModeAvailable: true,
            practiceEngineV2Enabled: practiceEngineV2Enabled,
            aiTutorEnabled: aiTutorEnabled,
            adaptiveShellEnabled: adaptiveShellEnabled,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
    ],
  );
  final router = container.read(routerProvider);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await liveEngine.dispose();
    await tunerEngine.dispose();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const _RouterTestApp(),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group(
    'A1 — FeatureFlags adaptiveShellEnabled (all six extension points)',
    () {
      test('defaults to false on the bare constructor', () {
        const flags = FeatureFlags(
          accountEnabled: false,
          diagnosticsEnabled: false,
          labModeAvailable: false,
        );
        expect(flags.adaptiveShellEnabled, isFalse);
      });

      test('forEnvironment resolves to true outside production, false in '
          'production (E15-R02, ADR 0467 D1)', () {
        for (final environment in AppEnvironment.values) {
          final flags = FeatureFlags.forEnvironment(
            environment,
            accountEnabled: false,
          );
          expect(
            flags.adaptiveShellEnabled,
            environment != AppEnvironment.production,
            reason: environment == AppEnvironment.production
                ? 'production must default the adaptive shell OFF'
                : '$environment must default the adaptive shell ON',
          );
        }
      });

      test('participates in == and hashCode', () {
        const on = FeatureFlags(
          accountEnabled: false,
          diagnosticsEnabled: false,
          labModeAvailable: false,
          adaptiveShellEnabled: true,
        );
        const off = FeatureFlags(
          accountEnabled: false,
          diagnosticsEnabled: false,
          labModeAvailable: false,
          adaptiveShellEnabled: false,
        );

        expect(on == off, isFalse);
        expect(on.hashCode == off.hashCode, isFalse);
      });

      test('is printed by toString', () {
        const on = FeatureFlags(
          accountEnabled: false,
          diagnosticsEnabled: false,
          labModeAvailable: false,
          adaptiveShellEnabled: true,
        );
        expect(on.toString(), contains('adaptiveShellEnabled: true'));
      });
    },
  );

  group('A1 — adaptive shell route registration (flag ON)', () {
    testWidgets('the five destinations render their legacy adapter screens', (
      tester,
    ) async {
      // D15 fix round — practiceHub and coachHome are gated by their own
      // product rollout flags now, independent of adaptiveShellEnabled; both
      // must be explicitly on for this cell to reach their screens.
      final router = await _pumpAdaptiveRouter(
        tester,
        practiceEngineV2Enabled: true,
        aiTutorEnabled: true,
      );

      router.go(AppRoutes.today);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // E13-R17 — the Today Hub replaces the temporary resource-free
      // ProgressScreen adapter (D14 fix round); it stays resource-free too
      // (A4, ADR 0276): no audio/camera import anywhere in that screen.
      expect(find.byType(TodayHubScreen), findsOneWidget);

      router.go(AppRoutes.practiceHub);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // E13-R17 — the Practice Area Hub replaces the legacy
      // PracticeHubScreen adapter here.
      expect(find.byType(PracticeAreaHubScreen), findsOneWidget);

      router.go(AppRoutes.songs);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SongListScreen), findsOneWidget);

      router.go(AppRoutes.coachHome);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TutorHomeScreen), findsOneWidget);

      router.go(AppRoutes.profileHome);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // E13-R17 — the Profile Hub replaces the legacy SettingsScreen adapter
      // here; `/profile/settings` still renders SettingsScreen unchanged.
      expect(find.byType(ProfileHubScreen), findsOneWidget);
    });

    testWidgets('the eleven target sub-routes render their adapter screens', (
      tester,
    ) async {
      final router = await _pumpAdaptiveRouter(tester);
      final cases = <String, Type>{
        AppRoutes.practiceLive: LiveScreen,
        AppRoutes.practiceAnalyze: AnalyzeScreen,
        AppRoutes.practiceLearn: LessonListScreen,
        AppRoutes.practiceTuner: TunerScreen,
        AppRoutes.practiceMetronome: MetronomeScreen,
        AppRoutes.practiceChords: ChordLibraryScreen,
        AppRoutes.songsSetlists: SetlistListScreen,
        // E13-R28 (§0.0/B2) — the ONE adapter this round replaces: the
        // unified library now owns `/profile/library`. `LibraryScreen`
        // stays wired at the legacy `/library` route below (untouched).
        AppRoutes.profileLibrary: UnifiedLibraryScreen,
        AppRoutes.profileSettings: SettingsScreen,
        AppRoutes.profileProgress: ProgressScreen,
        AppRoutes.profileRewards: StreakScreen,
      };

      for (final entry in cases.entries) {
        router.go(entry.key);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: entry.key);
        expect(
          find.byWidgetPredicate((w) => w.runtimeType == entry.value),
          findsOneWidget,
          reason: '${entry.key} must render a ${entry.value}',
        );
      }
    });

    testWidgets('each destination path is registered exactly once: '
        '/practice resolves to the shelled adapter, not the bare legacy route, '
        'even when practiceEngineV2Enabled is also on', (tester) async {
      final router = await _pumpAdaptiveRouter(
        tester,
        practiceEngineV2Enabled: true,
      );

      router.go(AppRoutes.practiceHub);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(PracticeAreaHubScreen), findsOneWidget);
      // The shelled registration wraps the screen in primary navigation;
      // the excluded bare legacy GoRoute would not.
      expect(
        find.byType(NavigationBar).evaluate().isNotEmpty ||
            find.byType(NavigationRail).evaluate().isNotEmpty,
        isTrue,
        reason:
            'a duplicated, unguarded legacy /practice registration would '
            'shadow the shelled one and drop primary navigation',
      );
    });

    testWidgets(
      'a navigation flag does not bypass another feature rollout flag: '
      '/practice does not render PracticeAreaHubScreen when '
      'practiceEngineV2Enabled is off (review MINOR-1 fix, brief §0.0 D15)',
      (tester) async {
        final router = await _pumpAdaptiveRouter(
          tester,
          practiceEngineV2Enabled: false,
        );

        router.go(AppRoutes.practiceHub);
        await tester.pumpAndSettle();

        expect(find.byType(PracticeAreaHubScreen), findsNothing);
      },
    );

    testWidgets(
      'a navigation flag does not bypass another feature rollout flag: '
      '/coach does not render TutorHomeScreen when aiTutorEnabled is off '
      '(review MINOR-1 fix, brief §0.0 D15)',
      (tester) async {
        final router = await _pumpAdaptiveRouter(tester, aiTutorEnabled: false);

        router.go(AppRoutes.coachHome);
        await tester.pumpAndSettle();

        expect(find.byType(TutorHomeScreen), findsNothing);
      },
    );
  });

  group('A7 — onException falls back to the shell entry point, not always '
      '/live (review MINOR-2 fix)', () {
    testWidgets('flag OFF: an unregistered URL still lands on /live '
        "(today's behaviour, unchanged)", (tester) async {
      final router = await _pumpAdaptiveRouter(
        tester,
        adaptiveShellEnabled: false,
      );

      router.go('/does-not-exist');
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppRoutes.live);
      expect(find.byType(LiveScreen), findsOneWidget);
    });

    testWidgets('flag ON: an unregistered URL lands on /today, with primary '
        'navigation available — not the navigation-less /practice/live '
        'Stage route', (tester) async {
      final router = await _pumpAdaptiveRouter(tester);

      router.go('/does-not-exist');
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppRoutes.today);
      expect(
        find.byType(NavigationBar).evaluate().isNotEmpty ||
            find.byType(NavigationRail).evaluate().isNotEmpty,
        isTrue,
        reason:
            'landing on the Stage route /practice/live would strand '
            'the user with no primary navigation to leave from',
      );
    });

    testWidgets('flag ON + practiceEngineV2Enabled: false: /practice lands on '
        '/today, not /practice/live', (tester) async {
      final router = await _pumpAdaptiveRouter(
        tester,
        practiceEngineV2Enabled: false,
      );

      router.go(AppRoutes.practiceHub);
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppRoutes.today);
    });
  });

  group('A4 — Stage routes hide primary navigation (anti-vacuum, L403)', () {
    test('isStageRoute predicate — the pinned, narrow set only', () {
      expect(isStageRoute(AppRoutes.practiceSession), isTrue);
      expect(isStageRoute(AppRoutes.visionSession), isTrue);
      expect(isStageRoute('/song-trainer/session/abc'), isTrue);
      expect(isStageRoute('/song-trainer/session/abc/extra'), isFalse);
      // D14 fix round — `/practice/live` is now a stage route: it moved to
      // a top-level GoRoute (D14/2), so it no longer needs to keep primary
      // navigation available as the post-onboarding entry point; `/today`
      // (a resource-free adapter, D14/1) took over that role instead.
      expect(isStageRoute(AppRoutes.practiceLive), isTrue);

      // Deliberately NOT stage routes this round (brief §0.0 D13) — hiding
      // navigation here would strand the post-onboarding entry point.
      expect(isStageRoute(AppRoutes.tuner), isFalse);
      expect(isStageRoute(AppRoutes.metronome), isFalse);
      expect(isStageRoute(AppRoutes.today), isFalse);
    });

    testWidgets(
      'SsAdaptiveScaffold primitive — showPrimaryNavigation:false renders '
      'no NavigationBar/Rail; true renders exactly one',
      (tester) async {
        Future<void> pumpAt(String location) => tester.pumpWidget(
          MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => SsAdaptiveScaffold(
                showPrimaryNavigation: !isStageRoute(location),
                selectedIndex: 0,
                onDestinationSelected: (_) {},
                body: const SizedBox.shrink(),
                destinations: const [
                  SsAdaptiveDestination(
                    icon: Icon(Icons.today_outlined),
                    selectedIcon: Icon(Icons.today),
                    label: 'Today',
                  ),
                  SsAdaptiveDestination(
                    icon: Icon(Icons.fitness_center_outlined),
                    selectedIcon: Icon(Icons.fitness_center),
                    label: 'Practice',
                  ),
                ],
              ),
            ),
          ),
        );

        await pumpAt(AppRoutes.practiceSession);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(NavigationRail), findsNothing);

        await pumpAt(AppRoutes.today);
        final navCount =
            find.byType(NavigationBar).evaluate().length +
            find.byType(NavigationRail).evaluate().length;
        expect(navCount, 1);
      },
    );

    testWidgets('AdaptiveHomeShell itself (the production shell widget, not a '
        're-implementation of its wiring) hides navigation at a stage '
        'location and shows exactly one otherwise', (tester) async {
      // A minimal, isolated StatefulShellRoute — NOT the production
      // routerProvider — that builds the real AdaptiveHomeShell class so
      // a regression in home_shell.dart's own showPrimaryNavigation wiring
      // (not just in a test-local copy of the expression) is observable.
      Future<void> pumpShellAt(String initialLocation) async {
        final router = GoRouter(
          initialLocation: initialLocation,
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (context, state, navigationShell) => AdaptiveHomeShell(
                navigationShell: navigationShell,
                location: state.uri.path,
              ),
              branches: [
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: '/probe-non-stage',
                      builder: (_, _) => const SizedBox.shrink(),
                    ),
                  ],
                ),
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: AppRoutes.practiceSession,
                      builder: (_, _) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp.router(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpShellAt('/probe-non-stage');
      final navCount =
          find.byType(NavigationBar).evaluate().length +
          find.byType(NavigationRail).evaluate().length;
      expect(navCount, 1);

      await pumpShellAt(AppRoutes.practiceSession);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
    });
  });

  group('A6 — breakpoint resolver (SsBreakpoints tokens, §6.2)', () {
    test('the six pinned cells resolve to the right mode', () {
      expect(
        SsAdaptiveScaffold.modeForWidth(599),
        SsAdaptiveLayoutMode.compact,
      );
      expect(SsAdaptiveScaffold.modeForWidth(600), SsAdaptiveLayoutMode.medium);
      expect(SsAdaptiveScaffold.modeForWidth(839), SsAdaptiveLayoutMode.medium);
      expect(
        SsAdaptiveScaffold.modeForWidth(840),
        SsAdaptiveLayoutMode.expanded,
      );
      expect(
        SsAdaptiveScaffold.modeForWidth(1199),
        SsAdaptiveLayoutMode.expanded,
      );
      expect(SsAdaptiveScaffold.modeForWidth(1200), SsAdaptiveLayoutMode.wide);
    });

    Widget scaffoldAt(double width) => MaterialApp(
      theme: SsLightTheme.data(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: SsAdaptiveScaffold(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          body: const SizedBox.shrink(),
          destinations: const [
            SsAdaptiveDestination(
              icon: Icon(Icons.today_outlined),
              selectedIcon: Icon(Icons.today),
              label: 'Today',
            ),
            SsAdaptiveDestination(
              icon: Icon(Icons.fitness_center_outlined),
              selectedIcon: Icon(Icons.fitness_center),
              label: 'Practice',
            ),
          ],
        ),
      ),
    );

    testWidgets('compact (599dp): bottom NavigationBar, no rail', (
      tester,
    ) async {
      await tester.pumpWidget(scaffoldAt(599));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('medium (600dp / 839dp): NavigationRail, no bottom bar', (
      tester,
    ) async {
      await tester.pumpWidget(scaffoldAt(600));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      await tester.pumpWidget(scaffoldAt(839));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets(
      'expanded (840dp / 1199dp): extended NavigationRail with labels',
      (tester) async {
        await tester.pumpWidget(scaffoldAt(840));
        final rail840 = tester.widget<NavigationRail>(
          find.byType(NavigationRail),
        );
        expect(rail840.extended, isTrue);

        await tester.pumpWidget(scaffoldAt(1199));
        final rail1199 = tester.widget<NavigationRail>(
          find.byType(NavigationRail),
        );
        expect(rail1199.extended, isTrue);
      },
    );

    testWidgets('wide (1200dp): NavigationRail present', (tester) async {
      await tester.pumpWidget(scaffoldAt(1200));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    test(
      'no magic 600/840/1200 literal in the resolver — it tracks tokens',
      () {
        // The resolver must move with the tokens, not a copy of today's
        // values. A hard-coded literal would keep passing today but silently
        // desync the moment SsBreakpoints changes.
        expect(
          SsAdaptiveScaffold.modeForWidth(SsBreakpoints.compactMax),
          SsAdaptiveLayoutMode.compact,
        );
        expect(
          SsAdaptiveScaffold.modeForWidth(SsBreakpoints.compactMax + 1),
          SsAdaptiveLayoutMode.medium,
        );
        expect(
          SsAdaptiveScaffold.modeForWidth(SsBreakpoints.expandedMin),
          SsAdaptiveLayoutMode.expanded,
        );
        expect(
          SsAdaptiveScaffold.modeForWidth(SsBreakpoints.wideMin),
          SsAdaptiveLayoutMode.wide,
        );
      },
    );
  });

  group('A8 — resource-owning screens release on destination switch '
      '(review MAJOR-1 fix, brief §0.0 D14)', () {
    testWidgets(
      'LEGACY REFERENCE (flag OFF): leaving Live disposes LiveScreen and '
      'releases the screen wakelock',
      (tester) async {
        final wakelock = FakeScreenWakelock();
        final router = await _pumpAdaptiveRouter(
          tester,
          adaptiveShellEnabled: false,
          wakelock: wakelock,
        );

        router.go(AppRoutes.live);
        await tester.pumpAndSettle();
        expect(find.byType(LiveScreen), findsOneWidget);
        expect(wakelock.isHeld, isTrue);

        router.go(AppRoutes.analyze);
        await tester.pumpAndSettle();
        expect(find.byType(LiveScreen, skipOffstage: false), findsNothing);
        expect(wakelock.isHeld, isFalse);
      },
    );

    testWidgets(
      'flag ON: leaving /practice/live (a top-level Stage route, D14/2) '
      'disposes LiveScreen and releases the screen wakelock — 0 offstage '
      'instances, not the pre-fix 2',
      (tester) async {
        final wakelock = FakeScreenWakelock();
        final router = await _pumpAdaptiveRouter(tester, wakelock: wakelock);

        router.go(AppRoutes.practiceLive);
        await tester.pumpAndSettle();
        expect(find.byType(LiveScreen), findsOneWidget);
        expect(wakelock.isHeld, isTrue);

        router.go(AppRoutes.today);
        await tester.pumpAndSettle();
        expect(
          find.byType(LiveScreen, skipOffstage: false),
          findsNothing,
          reason:
              'a StatefulShellRoute branch would keep this mounted '
              'offstage instead of disposing it — the review MAJOR-1 bug',
        );
        expect(wakelock.isHeld, isFalse);
        expect(wakelock.disableCalls, greaterThanOrEqualTo(1));
      },
    );

    testWidgets(
      'flag ON: LiveScreen is not left mounted in any shell branch after '
      'a full destination walk (skipOffstage: false)',
      (tester) async {
        final wakelock = FakeScreenWakelock();
        final router = await _pumpAdaptiveRouter(
          tester,
          practiceEngineV2Enabled: true,
          aiTutorEnabled: true,
          wakelock: wakelock,
        );

        for (final destination in <String>[
          AppRoutes.today,
          AppRoutes.practiceHub,
          AppRoutes.songs,
          AppRoutes.coachHome,
          AppRoutes.profileHome,
        ]) {
          router.go(destination);
          await tester.pumpAndSettle();
        }

        expect(
          find.byType(LiveScreen, skipOffstage: false),
          findsNothing,
          reason:
              'none of the five shell branches renders LiveScreen any '
              'more (D14/1 Today adapter, D14/2 practice/live moved out); '
              'skipOffstage:false also rules out retention in a hidden '
              'branch, not just the currently visible one',
        );
        expect(wakelock.isHeld, isFalse);
      },
    );
  });
}
