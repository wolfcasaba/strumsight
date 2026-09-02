import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/analyze/screens/analyze_screen.dart';
import '../../features/audio_analysis/domain/analysis_document.dart';
import '../../features/audio_analysis/domain/comparison/analysis_comparison.dart';
import '../../features/audio_analysis/presentation/analysis_compare_screen.dart';
import '../../features/audio_analysis/presentation/analysis_metric_detail_screen.dart';
import '../../features/audio_analysis/presentation/analysis_overview_screen.dart';
import '../../features/audio_analysis/presentation/analysis_timeline_screen.dart';
import '../../features/audio_analysis/presentation/controllers/overview_view_model.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/chords/screens/chord_library_screen.dart';
import '../../features/gamification/application/streak_service.dart';
import '../../features/gamification/data/gamification_repository.dart';
import '../../features/gamification/data/gamification_storage_schema.dart';
import '../../features/gamification/data/local_gamification_repository.dart';
import '../../features/gamification/data/migration/legacy_streak_migrator.dart';
import '../../features/gamification/domain/achievements/achievement_progress.dart';
import '../../features/gamification/domain/levels/level_curve.dart';
import '../../features/gamification/domain/levels/level_definition.dart';
import '../../features/gamification/domain/profile/gamification_profile.dart';
import '../../features/gamification/domain/profile/reward_inbox_item.dart';
import '../../features/gamification/domain/streak/streak_state.dart';
import '../../features/gamification/infrastructure/default_achievement_catalog.dart';
import '../../features/gamification/presentation/screens/achievement_detail_screen.dart';
import '../../features/gamification/presentation/screens/achievements_screen.dart';
import '../../features/gamification/presentation/screens/gamification_hub_screen.dart';
import '../../features/gamification/presentation/screens/quests_screen.dart';
import '../../features/gamification/presentation/screens/reward_inbox_screen.dart';
import '../../features/gamification/presentation/screens/streak_detail_screen.dart';
import '../../l10n/app_localizations.dart';
import '../../features/learn/screens/latency_calibration_screen.dart';
import '../../features/learn/screens/lesson_list_screen.dart';
import '../../features/library/public.dart';
import '../../features/library/screens/library_screen.dart';
import '../../features/library/screens/session_detail_screen.dart';
import '../../features/library_v2/domain/library_item.dart';
import '../../features/library_v2/screens/library_item_detail_screen.dart';
import '../../features/library_v2/screens/unified_library_screen.dart';
import '../../features/live/screens/live_screen.dart';
import '../../features/metronome/screens/metronome_screen.dart';
import '../../features/onboarding/onboarding_provider.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/practice/presentation/screens/practice_hub_screen.dart';
import '../../features/practice/presentation/screens/practice_result_screen.dart';
import '../../features/practice/presentation/screens/practice_setup_screen.dart';
import '../../features/practice/presentation/screens/practice_session_screen.dart';
import '../../features/practice_generator/presentation/providers/practice_generator_providers.dart';
import '../../features/practice_generator/presentation/screens/plan_setup_screen.dart';
import '../../features/practice_generator/presentation/screens/today_plan_screen.dart';
import '../../features/practice_hub/screens/practice_area_hub_screen.dart';
import '../../features/profile_hub/screens/profile_hub_screen.dart';
import '../../features/progress/screens/progress_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/today/screens/today_hub_screen.dart';
import '../../features/songs/screens/setlist_list_screen.dart';
import '../../features/songs/screens/song_list_screen.dart';
import '../../features/streak/screens/streak_screen.dart';
import '../../features/song_trainer/public.dart';
import '../../features/song_trainer/application/song_trainer_providers.dart';
import '../../features/song_trainer/application/trainer/song_trainer_result.dart';
import '../../features/song_trainer/presentation/screens/song_editor_screen.dart';
import '../../features/song_trainer/presentation/screens/song_overview_screen.dart';
import '../../features/song_trainer/presentation/screens/song_result_screen.dart';
import '../../features/song_trainer/presentation/screens/song_trainer_screen.dart';
import '../../features/song_trainer/presentation/screens/trainer_setup_screen.dart';
import '../../features/ai_tutor/presentation/screens/tutor_chat_screen.dart';
import '../../features/ai_tutor/presentation/screens/tutor_data_screen.dart';
import '../../features/ai_tutor/presentation/screens/tutor_home_screen.dart';
import '../../features/ai_tutor/presentation/screens/tutor_privacy_screen.dart';
import '../../features/ai_tutor/presentation/screens/tutor_profile_screen.dart';
import '../../features/tuner/screens/tuner_screen.dart';
import '../../features/vision/public.dart';
import '../../core/logging/logger_provider.dart';
import '../../core/storage/storage_providers.dart';
import '../bootstrap/recovery_screen.dart';
import '../config/app_config.dart';
import '../home_shell.dart';
import 'adaptive_shell_routes.dart';
import 'app_route.dart';
import 'route_guards.dart';

final class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

// E08-R30 — named-route handle for the achievement detail screen. Kept
// here (not in [AppRoutes]) because it is only ever referenced from this
// file by the achievements list callback.
const String _achievementDetailName = 'achievement-detail';

// E08-R30 — minimal Riverpod glue for the new gamification routes. These
// providers stay file-private because the gamification feature's own
// `presentation/providers/` directory remains out of scope for this round
// (the registered routes only need a synchronous projection; a future round
// can lift them into the feature once the UI binds additional inputs).
final _gamificationRepositoryProvider = Provider<GamificationRepository>((ref) {
  final repo = LocalGamificationRepository(
    store: ref.watch(keyValueStoreProvider),
    logger: ref.watch(appLoggerProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final _levelCurveProvider = Provider<LevelCurve>((_) {
  return LevelCurve(<LevelDefinition>[
    LevelDefinition(
      number: 1,
      levelThreshold: 0,
      titleKey: 'gamification.level.beginner',
    ),
    LevelDefinition(
      number: 2,
      levelThreshold: 100,
      titleKey: 'gamification.level.explorer',
    ),
    LevelDefinition(
      number: 3,
      levelThreshold: 250,
      titleKey: 'gamification.level.consistent',
    ),
    LevelDefinition(
      number: 4,
      levelThreshold: 500,
      titleKey: 'gamification.level.advanced',
    ),
  ]);
});

final _gamificationProfileProvider = Provider<GamificationProfile>((ref) {
  final repo = ref.watch(_gamificationRepositoryProvider);
  final curve = ref.watch(_levelCurveProvider);
  final read = repo.readProfileSnapshot();
  final totalXp =
      read.status == GamificationReadStatus.available && read.value != null
      ? read.value!.totalXp
      : 0;
  return GamificationProfile(
    schemaVersion: gamificationProfileSchemaVersion,
    totalXp: totalXp,
    progress: curve.progressForTotalXp(totalXp),
  );
});

final _streakStateProvider = Provider<StreakState>((ref) {
  final store = ref.watch(keyValueStoreProvider);
  // TODO(E08-R30): wire `LegacyStreakMigrator.migrate()` writes back to the
  // V2 namespaced envelope once the v22 storage migration clears the legacy
  // key. For now this is a read-only projection of the on-disk state.
  final migrated = LegacyStreakMigrator(store).migrate();
  return migrated ??
      StreakState(
        current: 0,
        longest: 0,
        lastQualifiedDay: -1,
        totalQualifiedDays: 0,
        freezes: 0,
      );
});

final _rewardInboxProvider = Provider<List<GamificationInboxItem>>((ref) {
  final repo = ref.watch(_gamificationRepositoryProvider);
  final read = repo.readInbox();
  if (read.status == GamificationReadStatus.available && read.value != null) {
    return read.value!;
  }
  return const <GamificationInboxItem>[];
});

/// App router: a bottom-nav [ShellRoute] over the five tabs, plus full-screen
/// routes pushed from those destinations.
final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.listen(onboardingSeenProvider, (_, _) => refreshNotifier.refresh());

  // E02-R12: the Practice hub and setup routes are flag-gated. When the
  // flag is off, the routes are not registered, so a `/practice*` URL
  // hits the existing onException below and lands on Live — a
  // measurement, not new behaviour.
  final practiceEnabled = ref
      .read(appConfigProvider)
      .flags
      .practiceEngineV2Enabled;
  final songTrainerEnabled = ref
      .read(appConfigProvider)
      .flags
      .songTrainerV2Enabled;
  final aiTutorEnabled = ref.read(appConfigProvider).flags.aiTutorEnabled;
  // E15-R07 F1 (ADR 0491 D1) — gates the two Practice Generator screens
  // registered below that the composition root can already build from real
  // providers; the other 4 screens transitively depend on two seams
  // (an exercise-candidate resolver, a generation-plan-input builder) that
  // still throw `UnimplementedError` and are deliberately NOT wired here
  // (ADR 0491 D5). NOTE: keep this comment free of the two screens' exact
  // class names — `tool/check_screen_reachability.dart` textually matches
  // class names anywhere in this file (D3 of that tool), so naming them
  // here would falsely count as an un-gated declarative reference and flip
  // their measured `isFlagGated` to false.
  final practiceGeneratorEnabled = ref
      .read(appConfigProvider)
      .flags
      .practiceGeneratorEnabled;
  final visionEnabled = ref.read(appConfigProvider).flags.visionEnabled;
  final visionSetupEnabled = ref
      .read(appConfigProvider)
      .flags
      .visionSetupEnabled;
  final visionGuitarGeometryEnabled = ref
      .read(appConfigProvider)
      .flags
      .visionGuitarGeometryEnabled;
  final audioAnalysisV2Enabled = ref
      .read(appConfigProvider)
      .flags
      .audioAnalysisV2Enabled;
  final analysisComparisonEnabled = ref
      .read(appConfigProvider)
      .flags
      .analysisComparisonEnabled;
  final adaptiveShellEnabled = ref
      .read(appConfigProvider)
      .flags
      .adaptiveShellEnabled;

  // E13-R08 (brief §0.0 D14/4) — the flag BE entry point is `/today`; the
  // KI entry point is unchanged (`/live`). `onboardingRedirect`'s `home`
  // parameter carries the same choice so a seen-onboarding user landing on
  // `/welcome` resolves to the right destination.
  final entryLocation = adaptiveShellEnabled ? AppRoutes.today : AppRoutes.live;

  final router = GoRouter(
    initialLocation: entryLocation,
    refreshListenable: refreshNotifier,
    onException: (_, _, router) => router.go(entryLocation),
    redirect: (_, state) {
      final onboarding = onboardingRedirect(
        seen: ref.read(onboardingSeenProvider),
        location: state.uri.path,
        home: entryLocation,
      );
      if (onboarding != null) return onboarding;
      if (!adaptiveShellEnabled) return null;
      // E13-R08 (ADR 0275 §3, D8) — preserve query + fragment; jumping to a
      // string constant would silently drop them.
      final target = legacyRedirects[state.uri.path];
      if (target == null) return null;
      return state.uri.replace(path: target).toString();
    },
    routes: [
      GoRoute(
        path: AppRoutes.welcome,
        builder: (_, _) => const OnboardingScreen(),
      ),
      // SDD Ch13 Kör 16 (ADR 0281 §3/§6) — the in-app safe-mode surface.
      // `extra` carries the already-redacted problem strings; a direct hit
      // with no `extra` (e.g. a deep link) renders with an empty list rather
      // than crashing.
      GoRoute(
        path: AppRoutes.recovery,
        builder: (_, state) => RecoveryScreen(
          problems: (state.extra as List<String>?) ?? const <String>[],
        ),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            HomeShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: AppRoutes.live, builder: (_, _) => const LiveScreen()),
          GoRoute(
            path: AppRoutes.analyze,
            builder: (_, _) => const AnalyzeScreen(),
          ),
          GoRoute(
            path: AppRoutes.learn,
            builder: (_, _) => const LessonListScreen(),
          ),
          GoRoute(
            path: AppRoutes.library,
            builder: (_, _) => const LibraryScreen(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (_, _) => const SettingsScreen(),
          ),
        ],
      ),
      GoRoute(path: AppRoutes.tuner, builder: (_, _) => const TunerScreen()),
      GoRoute(
        path: AppRoutes.metronome,
        builder: (_, _) => const MetronomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.calibrate,
        builder: (_, _) => const LatencyCalibrationScreen(),
      ),
      GoRoute(path: AppRoutes.streak, builder: (_, _) => const StreakScreen()),
      GoRoute(
        path: AppRoutes.progress,
        builder: (_, _) => const ProgressScreen(),
      ),
      // E13-R08 (D6) — when the adaptive shell owns `/songs` as a
      // destination root below, this legacy registration is excluded to
      // avoid a silently-shadowed duplicate path.
      if (!adaptiveShellEnabled)
        GoRoute(
          path: AppRoutes.songs,
          builder: (_, _) => const SongListScreen(),
        ),
      GoRoute(
        path: AppRoutes.setlists,
        builder: (_, _) => const SetlistListScreen(),
      ),
      GoRoute(
        path: AppRoutes.chords,
        builder: (_, _) => const ChordLibraryScreen(),
      ),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.librarySession,
        redirect: (_, state) =>
            state.extra is AnalyzedSession ? null : AppRoutes.library,
        builder: (_, state) {
          final session = state.extra;
          if (session is AnalyzedSession) {
            return SessionDetailScreen(session: session);
          }
          return const LibraryScreen();
        },
      ),
      // Unified Library session detail (E13-R28, SDD Ch13 UI-41, §0.0/B2).
      // The ONLY route this round adds — the legacy `librarySession` route
      // above is untouched. A `LibraryItem` `extra` of the wrong (or
      // missing) type redirects to the unified list rather than crashing,
      // mirroring the pattern above.
      GoRoute(
        path: AppRoutes.profileLibrarySession,
        redirect: (_, state) =>
            state.extra is LibraryItem ? null : AppRoutes.profileLibrary,
        builder: (_, state) =>
            LibraryItemDetailScreen(item: state.extra as LibraryItem),
      ),
      if (practiceEnabled) ...[
        // E13-R08 (D6) — excluded when the adaptive shell owns `/practice`
        // as a destination root below, to avoid a silently-shadowed
        // duplicate path.
        if (!adaptiveShellEnabled)
          GoRoute(
            path: AppRoutes.practiceHub,
            builder: (_, _) => const PracticeHubScreen(),
          ),
        GoRoute(
          path: AppRoutes.practiceSetup,
          builder: (_, _) => const PracticeSetupScreen(),
        ),
        GoRoute(
          path: AppRoutes.practiceSession,
          builder: (_, _) => const PracticeSessionScreen(),
        ),
        GoRoute(
          path: AppRoutes.practiceResult,
          builder: (_, _) => const PracticeResultFallback(),
        ),
      ],
      // E15-R07 F1 (ADR 0491 D1) — the two MEASURED-constructible Practice
      // Generator screens, each built from the composition root's real
      // providers (`planSetupControllerProvider`, `todayPlanControllerProvider`
      // — `practice_generator_providers.dart`, out of scope for this round).
      // Gated independently of `practiceEnabled` (Practice Engine V2): the
      // Generator is a distinct rollout (ADR 0491 D2).
      if (practiceGeneratorEnabled) ...[
        GoRoute(
          path: AppRoutes.practiceGeneratorSetup,
          builder: (_, _) => Consumer(
            builder: (context, ref, _) => PlanSetupScreen(
              controller: ref.watch(planSetupControllerProvider),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.practiceGeneratorToday,
          builder: (_, _) => Consumer(
            builder: (context, ref, _) => TodayPlanScreen(
              controller: ref.watch(todayPlanControllerProvider),
            ),
          ),
        ),
      ],
      if (songTrainerEnabled) ...[
        GoRoute(
          path: AppRoutes.songTrainerLibrary,
          builder: (_, _) => const SongLibraryScreen(),
        ),
        GoRoute(
          path: AppRoutes.songTrainerImport,
          builder: (_, _) => const SongImportScreen(),
        ),
        GoRoute(
          path: AppRoutes.songTrainerNewEditor,
          builder: (_, _) => const SongEditorScreen.newDocument(),
        ),
        GoRoute(
          path: AppRoutes.songTrainerEditor,
          builder: (_, state) =>
              SongEditorScreen(songId: state.pathParameters['songId']!),
        ),
        GoRoute(
          path: AppRoutes.songTrainerOverview,
          builder: (_, state) =>
              SongOverviewScreen(songId: state.pathParameters['songId']!),
        ),
        GoRoute(
          path: AppRoutes.songTrainerSetup,
          builder: (_, state) =>
              TrainerSetupScreen(songId: state.pathParameters['songId']!),
        ),
        GoRoute(
          path: AppRoutes.songTrainerSession,
          builder: (_, state) => SongTrainerScreen(
            songId: state.pathParameters['songId']!,
            inputs: state.extra! as SongTrainerControllerInputs,
          ),
        ),
        GoRoute(
          path: AppRoutes.songTrainerResult,
          builder: (_, state) =>
              SongResultScreen(result: state.extra! as SongTrainerResult),
        ),
      ],
      // E13-R08 (D14 fix round) — `/practice/live` moved OUT of the shell
      // branches to a top-level route, exactly like the session routes
      // below. `StatefulShellRoute.indexedStack` keeps every visited
      // branch's Navigator alive (needed for A3's tab-state restoration),
      // which means a resource-owning screen placed inside a branch never
      // unmounts on tab switch — the mic stream and screen wakelock stayed
      // live in the background (review MAJOR-1). A top-level `GoRoute`
      // restores the normal mount/dispose semantics: leaving `/practice/live`
      // for any other destination disposes `LiveScreen`. It is registered
      // whenever the adaptive shell is reachable at all (independent of
      // `practiceEnabled` — it is the legacy `/live` redirect target, D5/D6),
      // and it is a Stage route (`isStageRoute`, D14/3): no primary
      // navigation renders on top of it. Unlike the session screens below,
      // `LiveScreen` has no `Scaffold` of its own — it was built to be
      // hosted inside a shell's `Scaffold` (legacy `HomeShell`, or the
      // now-removed shell branch) — so this adapter route supplies one.
      if (adaptiveShellEnabled)
        GoRoute(
          path: AppRoutes.practiceLive,
          builder: (_, _) => const Scaffold(body: LiveScreen()),
        ),
      // E13-R08 (ADR 0275) — the five-area adaptive shell, reachable only
      // when `adaptiveShellEnabled` is on. Every destination and target
      // sub-route renders an EXISTING screen as a legacy adapter (D6/D11);
      // no new screens are introduced here. Declared AFTER the legacy
      // `/practice` and `/songs` conditionals above so that, if either ever
      // lost its `!adaptiveShellEnabled` guard, the legacy (unshelled, no
      // primary navigation) registration would win the first-match — a
      // silent regression the round-8 acceptance matrix (#11) must be able
      // to observe, not one masked by declaration order.
      if (adaptiveShellEnabled)
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => AdaptiveHomeShell(
            navigationShell: navigationShell,
            location: state.uri.path,
            showCoachDestination: aiTutorEnabled,
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                // E13-R17 — the Today Hub (UI-05) replaces the temporary
                // ProgressScreen adapter the E13-R08 D14/1 fix round put here.
                // It stays resource-free, same as its predecessor (A4,
                // ADR 0276): no audio/camera import anywhere in that screen.
                GoRoute(
                  path: AppRoutes.today,
                  builder: (_, _) => const TodayHubScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                // E13-R08 (D15 fix round) — gated by the Practice Engine V2
                // rollout flag, matching the legacy `/practice` registration
                // above; an adaptive-shell navigation flag must not itself
                // grant access to a distinct product rollout. The branch
                // keeps its other sub-routes unconditionally, so it is never
                // left with zero routes.
                // E13-R17 — the Practice Area Hub (UI-06) replaces the
                // legacy PracticeHubScreen adapter here; the bare (non-shell)
                // `/practice` registration above still renders the legacy
                // screen unchanged. Still gated by the Practice Engine V2
                // rollout flag (E13-R08 D15) — a navigation flag must not
                // itself grant access to a distinct product rollout.
                if (practiceEnabled)
                  GoRoute(
                    path: AppRoutes.practiceHub,
                    builder: (_, _) => const PracticeAreaHubScreen(),
                  ),
                GoRoute(
                  path: AppRoutes.practiceAnalyze,
                  builder: (_, _) => const AnalyzeScreen(),
                ),
                GoRoute(
                  path: AppRoutes.practiceLearn,
                  builder: (_, _) => const LessonListScreen(),
                ),
                GoRoute(
                  path: AppRoutes.practiceTuner,
                  builder: (_, _) => const TunerScreen(),
                ),
                GoRoute(
                  path: AppRoutes.practiceMetronome,
                  builder: (_, _) => const MetronomeScreen(),
                ),
                GoRoute(
                  path: AppRoutes.practiceChords,
                  builder: (_, _) => const ChordLibraryScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: AppRoutes.songs,
                  builder: (_, _) => const SongListScreen(),
                ),
                GoRoute(
                  path: AppRoutes.songsSetlists,
                  builder: (_, _) => const SetlistListScreen(),
                ),
              ],
            ),
            // E13-R08 (D15 fix round) — gated by the AI Tutor rollout flag,
            // matching the legacy `/tutor/home` registration below. Unlike
            // Practice, Coach has exactly one route, so guarding only the
            // route (leaving an empty branch) is not an option — the whole
            // branch is conditional, and `showCoachDestination` keeps
            // `AdaptiveHomeShell`'s destination list in the same order.
            if (aiTutorEnabled)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.coachHome,
                    builder: (_, _) => const TutorHomeScreen(),
                  ),
                ],
              ),
            StatefulShellBranch(
              routes: [
                // E13-R17 — the Profile Hub (UI-07) replaces the legacy
                // SettingsScreen adapter here. `/profile/settings` below
                // still renders SettingsScreen unchanged (A5 legacy-route
                // reachability); the hub itself links out to it.
                GoRoute(
                  path: AppRoutes.profileHome,
                  builder: (_, _) => const ProfileHubScreen(),
                ),
                GoRoute(
                  path: AppRoutes.profileLibrary,
                  builder: (_, _) => const UnifiedLibraryScreen(),
                ),
                GoRoute(
                  path: AppRoutes.profileSettings,
                  builder: (_, _) => const SettingsScreen(),
                ),
                GoRoute(
                  path: AppRoutes.profileProgress,
                  builder: (_, _) => const ProgressScreen(),
                ),
                GoRoute(
                  path: AppRoutes.profileRewards,
                  builder: (_, _) => const StreakScreen(),
                ),
              ],
            ),
          ],
        ),
      if (aiTutorEnabled) ...[
        GoRoute(
          path: AppRoutes.tutorHome,
          builder: (_, _) => const TutorHomeScreen(),
        ),
        GoRoute(
          path: AppRoutes.tutorChat,
          builder: (_, _) => const TutorChatScreen(),
        ),
        GoRoute(
          path: AppRoutes.tutorProfile,
          builder: (_, _) => const TutorProfileScreen(),
        ),
        GoRoute(
          path: AppRoutes.tutorPrivacy,
          builder: (_, _) => const TutorPrivacyScreen(),
        ),
        GoRoute(
          path: AppRoutes.tutorData,
          builder: (_, _) => const TutorDataScreen(),
        ),
      ],
      if (visionEnabled && visionSetupEnabled) ...[
        GoRoute(
          path: AppRoutes.visionSetup,
          builder: (_, _) => const VisionSetupScreen(),
        ),
      ],
      if (visionEnabled && visionGuitarGeometryEnabled) ...[
        GoRoute(
          path: AppRoutes.visionGuitarGeometry,
          builder: (_, _) => const GuitarCalibrationScreen(),
        ),
      ],
      if (visionEnabled) ...[
        GoRoute(
          path: AppRoutes.visionSession,
          builder: (_, _) => const VisionSessionScreen(),
        ),
      ],
      if (audioAnalysisV2Enabled) ...[
        GoRoute(
          path: AppRoutes.analysisOverview,
          redirect: (_, state) =>
              state.extra is AnalysisDocument ? null : AppRoutes.live,
          builder: (_, state) {
            final extra = state.extra;
            if (extra is AnalysisDocument) {
              return AnalysisOverviewScreen(document: extra);
            }
            return const AnalysisOverviewScreen();
          },
        ),
        GoRoute(
          path: AppRoutes.analysisMetricDetail,
          redirect: (_, state) {
            final extra = state.extra;
            // Accept a card list (single-metric navigation source), the
            // combined metrics+insights payload (the "Részletek" entry
            // point), or a document (the overview header's legacy entry).
            if (extra is List<OverviewMetricCard> ||
                extra is OverviewDetailsPayload ||
                extra is AnalysisDocument) {
              return null;
            }
            return AppRoutes.live;
          },
          builder: (_, state) {
            final extra = state.extra;
            if (extra is OverviewDetailsPayload) {
              return AnalysisMetricDetailScreen(
                metrics: extra.metrics,
                remainingInsights: extra.remainingInsights,
              );
            }
            if (extra is List<OverviewMetricCard>) {
              return AnalysisMetricDetailScreen(metrics: extra);
            }
            return const AnalysisMetricDetailScreen();
          },
        ),
        GoRoute(
          path: AppRoutes.analysisTimeline,
          redirect: (_, state) =>
              state.extra is AnalysisDocument ? null : AppRoutes.live,
          builder: (_, state) => AnalysisTimelineScreen(
            document: state.extra! as AnalysisDocument,
          ),
        ),
      ],
      if (analysisComparisonEnabled) ...[
        GoRoute(
          path: AppRoutes.analysisCompare,
          redirect: (_, state) =>
              state.extra is AnalysisComparison ? null : AppRoutes.live,
          builder: (_, state) => AnalysisCompareScreen(
            comparison: state.extra! as AnalysisComparison,
          ),
        ),
      ],
      // E08-R30 — Epic 8 gamification routes. The legacy `/streak` and
      // `/progress` deep links above remain live; these are the new
      // canonical V2 destinations.
      GoRoute(
        path: AppRoutes.gamificationHub,
        builder: (_, _) => Consumer(
          builder: (context, ref, _) {
            final profile = ref.watch(_gamificationProfileProvider);
            final streakState = ref.watch(_streakStateProvider);
            final inbox = ref.watch(_rewardInboxProvider);
            final unseenCount = inbox
                .where((GamificationInboxItem item) => !item.isViewed)
                .length;
            return GamificationHubScreen(
              profile: profile,
              activeQuestCount: 0,
              streakCurrentDays: streakState.current,
              masteryUnlockedCount: 0,
              inboxUnseenCount: unseenCount,
              // TODO(E08-R30): level-detail navigation needs a route
              // constant and screen wiring beyond the current scope.
              onOpenLevelDetail: () {},
              onOpenInbox: () => context.push(AppRoutes.rewardInbox),
              onOpenAchievements: () => context.push(AppRoutes.achievements),
              onOpenStreak: () => context.push(AppRoutes.streakDetail),
              onOpenQuests: () => context.push(AppRoutes.quests),
              onOpenMastery: () => context.push(AppRoutes.achievements),
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.achievements,
        builder: (context, _) => AchievementsScreen(
          definitions: defaultAchievementCatalog.definitions,
          // TODO(E08-R30): wire achievement progress through a future
          // AchievementProgressRepository; this round the surface is the
          // curated catalog definitions only.
          progressByAchievement: const <String, AchievementProgress>{},
          onAchievementSelected: (String id) => context.pushNamed(
            _achievementDetailName,
            pathParameters: <String, String>{'achievementId': id},
          ),
        ),
      ),
      GoRoute(
        name: _achievementDetailName,
        path: AppRoutes.achievementDetail,
        builder: (_, state) => AchievementDetailScreen(
          achievementId: state.pathParameters['achievementId']!,
          definitions: defaultAchievementCatalog.definitions,
          progressByAchievement: const <String, AchievementProgress>{},
        ),
      ),
      GoRoute(
        path: AppRoutes.quests,
        builder: (_, _) => Consumer(
          builder: (context, ref, _) {
            final l10n = AppLocalizations.of(context);
            return QuestsScreen(
              dailyChallengeTitle: l10n.challengeDailyTitle,
              dailyChallenge: null,
              dailyChallengeAvailable: false,
              dailyQuests: const <QuestViewProjection>[],
              weeklyQuests: const <QuestViewProjection>[],
              onAction: (_) {
                // TODO(E08-R30): route the typed QuestRouteAction through
                // go_router once the quest-action vocabulary is finalised.
              },
              now: DateTime.now(),
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.streakDetail,
        builder: (_, _) => Consumer(
          builder: (context, ref, _) {
            final streakState = ref.watch(_streakStateProvider);
            return StreakDetailScreen(
              state: streakState,
              // TODO(E08-R30): evaluate today's reason against the live
              // activity stream once that stream is wired to the screen.
              reason: StreakEvaluationReason.qualified,
              weeklyConsistencyDays: 0,
              onRecoveryPressed: () {
                // TODO(E08-R30): the streak-recovery purchase flow has no
                // public repository method yet; the button is rendered but
                // a no-op until the next round.
              },
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.rewardInbox,
        builder: (_, _) => Consumer(
          builder: (context, ref, _) => RewardInboxScreen(
            items: const <RewardInboxItem>[],
            onItemSelected: (_) {
              // TODO(E08-R30): route to the source ledger detail once
              // the reward-detail screen is built.
            },
            onMarkSeen: (_) {
              // TODO(E08-R30): the inbox is backed by the domain
              // [RewardInboxItem] (a projection of ledger entries), not
              // the storage-shaped [GamificationInboxItem] exposed by
              // [GamificationRepository]. Wiring the two is a future
              // round; the screen renders an empty state today.
            },
          ),
        ),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refreshNotifier.dispose();
  });
  return router;
});
