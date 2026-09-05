import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/logging/logger_provider.dart';
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
import '../../features/gamification/public.dart';
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
import '../../features/practice/public.dart' show practiceCatalogProvider;
import '../../features/practice_generator/presentation/providers/practice_generator_providers.dart';
import '../../features/practice_generator/presentation/screens/plan_setup_screen.dart';
import '../../features/practice_generator/presentation/screens/today_plan_screen.dart';
import '../../features/practice_hub/screens/practice_area_hub_screen.dart';
import '../../features/profile_hub/screens/profile_hub_screen.dart';
import '../../features/progress/screens/progress_screen.dart';
import '../../features/progress_v2/public.dart';
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
import '../bootstrap/recovery_screen.dart';
import '../config/app_config.dart';
import '../home_shell.dart';
import 'adaptive_shell_routes.dart';
import 'app_route.dart';
import 'route_guards.dart';
import 'package:strumsight/features/community/public.dart';

final class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

// E08-R30 — named-route handle for the achievement detail screen. Kept
// here (not in [AppRoutes]) because it is only ever referenced from this
// file by the achievements list callback.
const String _achievementDetailName = 'achievement-detail';

/// Review B1 — `achievementProgressProvider` is a `FutureProvider`, so its
/// `AsyncValue.value` is `null` on BOTH loading and error, which previously
/// collapsed to the SAME `?? const {}` fallback as a genuinely measured
/// empty achievement set (a transient dobás would then look permanently
/// like "no badges unlocked"). This routes the three states through
/// `.when` instead: loading gets its own indicator (never the "0 badges"
/// screen), error is logged and falls back to empty (the screen has no
/// richer error contract to degrade to — tilos zona), and only the `data`
/// branch is the actual measured projection.
Widget _achievementsAsyncBuilder({
  required WidgetRef ref,
  required Widget Function(Map<String, AchievementProgress> progress) onData,
}) {
  final progressAsync = ref.watch(achievementProgressProvider);
  return progressAsync.when(
    loading: () =>
        const Scaffold(body: Center(child: CircularProgressIndicator())),
    error: (error, stackTrace) {
      ref
          .read(appLoggerProvider)
          .error(
            'gamification.achievement_progress.load_failed',
            error: error,
            stackTrace: stackTrace,
          );
      return onData(const <String, AchievementProgress>{});
    },
    data: onData,
  );
}

/// Review B3 — resolves each item's `titleKey`/`bodyKey` to an EXISTING ARB
/// string via [AppLocalizations], since `RewardInboxScreen` renders both
/// fields raw (no lookup of its own — a pre-existing, tilos-zona screen
/// pattern) and `gamification_providers.dart` has no `BuildContext` to
/// resolve them itself. `RewardKind.challengeCompleted`/`.levelUp` are
/// unreachable from the provider's `_rewardKindFor` this round, but the
/// switch stays exhaustive.
List<RewardInboxItem> _localizedRewardInboxItems(
  Iterable<RewardInboxItem> items,
  AppLocalizations l10n,
) => [
  for (final item in items)
    RewardInboxItem(
      id: item.id,
      addedAt: item.addedAt,
      seen: item.seen,
      event: RewardEvent(
        id: item.event.id,
        kind: item.event.kind,
        titleKey: _rewardTitleFor(item.event.kind, l10n),
        bodyKey: l10n.questRewardAlreadyCredited,
        earnedXp: item.event.earnedXp,
        earnedAt: item.event.earnedAt,
        sourceLedgerId: item.event.sourceLedgerId,
        crossedLevelNumbers: item.event.crossedLevelNumbers,
      ),
    ),
];

String _rewardTitleFor(RewardKind kind, AppLocalizations l10n) =>
    switch (kind) {
      RewardKind.masteryMilestone => l10n.feedCardAchievementUnlocked,
      RewardKind.questCompleted => l10n.questCompletedBadge,
      RewardKind.challengeCompleted =>
        l10n.communityNotificationChallengeCompletedTitle,
      RewardKind.levelUp => l10n.gamificationHubSkillSectionTitle,
      RewardKind.dailyReward => l10n.practiceResultRewardTitle,
    };

/// E16-R02 (ADR 0500 §5.8) — [ProgressDashboardScreen.onOpenSkillDetail]
/// hands back a milestone id, but the skill-detail route's `:skillId`
/// segment is a `MasterySkill.code` (a milestone's *skill*, not its id) —
/// this resolves one to the other. Returns `null` for an id the catalog no
/// longer carries, which the caller must not navigate on.
MasteryMilestone? _masteryMilestoneById(String milestoneId) {
  for (final milestone in masteryMilestoneCatalogV1) {
    if (milestone.id == milestoneId) return milestone;
  }
  return null;
}

/// E16-R02 (ADR 0500 §5.8) — whether [skillId] (a `MasterySkill.code`) has a
/// v1 milestone at all. `tempoStability` has none (§5.4); an unknown string
/// has none either. Both cases redirect to [AppRoutes.profileProgress]
/// rather than 404ing.
bool _hasMasteryMilestoneForSkill(String? skillId) =>
    skillId != null &&
    masteryMilestoneCatalogV1.any(
      (milestone) => milestone.skill.code == skillId,
    );

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
  // E17 (Ch17 teljes bekötés) — a 13 community képernyő a `communityEnabled`
  // kapu alatt regisztrálódik. Kapu KI: az útvonalak NEM léteznek, tehát egy
  // `/community*` cím az alábbi `onException`-re fut és a belépési pontra
  // esik vissza — ugyanaz a mintázat, amit a Practice és a Vision kapuja
  // használ, és a szerver-oldali ADR 0497 D1 („a route nincs regisztrálva,
  // nem futásidejű 403") kliens-oldali párja.
  final communityEnabled = ref.read(appConfigProvider).flags.communityEnabled;
  final adaptiveShellEnabled = ref
      .read(appConfigProvider)
      .flags
      .adaptiveShellEnabled;

  // E13-R08 (brief §0.0 D14/4) — the flag BE entry point is `/today`; the
  // KI entry point is unchanged (`/live`). `onboardingRedirect`'s `home`
  // parameter carries the same choice so a seen-onboarding user landing on
  // `/welcome` resolves to the right destination. ADR 0508 D1 — the mapping
  // itself lives in `entryLocationFor`, the ONE source the onboarding flow's
  // completion navigation also calls.
  final entryLocation = entryLocationFor(adaptiveShellEnabled);

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
      // Progress V2 skill detail (E16-R02, SDD UI-50, ADR 0500 §5.8). Not a
      // shell destination — pushed on top, like [profileLibrarySession]
      // above. An unknown/unmapped `:skillId` redirects to the overview
      // rather than 404ing (§5.8) — `tempoStability` has no v1 milestone
      // (§5.4), so it redirects too.
      // Review MAJOR-1 (shell-OFF): the redirect target this route names,
      // `AppRoutes.profileProgress`, only exists inside the
      // `if (adaptiveShellEnabled)` branch below. Left unconditional, an
      // unknown `skillId` under shell-OFF would hit that missing route and
      // fall through `onException` to the generic `/live` entry — and a
      // VALID `skillId` would leak `SkillDetailScreen` through a deep link
      // into a build where the whole progress_v2 surface is off. Routing
      // shell-OFF traffic to the always-registered legacy `/progress`
      // (line ~300) instead keeps both cases landing somewhere deliberate.
      GoRoute(
        path: AppRoutes.profileProgressSkill,
        redirect: (_, state) {
          if (!adaptiveShellEnabled) return AppRoutes.progress;
          return _hasMasteryMilestoneForSkill(state.pathParameters['skillId'])
              ? null
              : AppRoutes.profileProgress;
        },
        builder: (_, state) => Consumer(
          builder: (context, ref, _) {
            final l10n = AppLocalizations.of(context);
            final projection = buildSkillDetailProjection(
              skillCode: state.pathParameters['skillId']!,
              milestoneCatalog: masteryMilestoneCatalogV1,
              practiceHistory: ref.watch(progressPracticeHistoryProvider),
              practiceCatalog: ref.watch(practiceCatalogProvider),
              now: ref.watch(progressNowProvider),
              localize: (key) => progressV2LocalizedText(l10n, key),
            )!;
            return SkillDetailScreen(
              projection: projection,
              onOpenEvidence: (route, sessionId) =>
                  context.push(route.replaceFirst(':sessionId', sessionId)),
              onStartRecommendedPractice: () =>
                  context.push(AppRoutes.practiceHub),
            );
          },
        ),
      ),
      if (communityEnabled) ...[
        // A belépési szűrő. Ő maga is a 13 elérhetetlen képernyő közt volt —
        // a feature kapuja sem volt elérhető.
        GoRoute(
          path: AppRoutes.community,
          builder: (_, _) => const CommunityGateScreen(),
        ),
        GoRoute(
          path: AppRoutes.communityFeed,
          builder: (_, _) => const FollowingFeedScreen(),
        ),
        GoRoute(
          path: AppRoutes.communityCompose,
          builder: (_, _) => const PostComposerScreen(),
        ),
        GoRoute(
          path: AppRoutes.communityComments,
          builder: (_, state) => CommentsScreen(
            postId: ContentId(state.pathParameters['postId']!),
          ),
        ),
        GoRoute(
          path: AppRoutes.communityBookmarks,
          builder: (_, _) => const BookmarksScreen(),
        ),
        GoRoute(
          path: AppRoutes.communityNotifications,
          builder: (_, _) => const CommunityNotificationsScreen(),
        ),
        GoRoute(
          path: AppRoutes.communitySearch,
          builder: (_, _) => const CommunitySearchScreen(),
        ),
        // A követők és a követettek KÉT útvonal, egy képernyővel: a lista
        // iránya nem query-paraméter, mert egy elhagyott paraméter némán a
        // másik listát mutatná.
        GoRoute(
          path: AppRoutes.communityFollowers,
          builder: (_, state) => FollowersScreen(
            profileId: PublicUserId(state.pathParameters['profileId']!),
            mode: FollowersMode.followers,
          ),
        ),
        GoRoute(
          path: AppRoutes.communityFollowing,
          builder: (_, state) => FollowersScreen(
            profileId: PublicUserId(state.pathParameters['profileId']!),
            mode: FollowersMode.following,
          ),
        ),
        GoRoute(
          path: AppRoutes.communityChallenges,
          builder: (_, _) => const CommunityChallengesScreen(),
        ),
        GoRoute(
          path: AppRoutes.communityLeaderboard,
          builder: (_, state) => LeaderboardScreen(
            challengeId: ContentId(state.pathParameters['challengeId']!),
          ),
        ),
        GoRoute(
          path: AppRoutes.communitySafety,
          builder: (_, _) => const SafetyRelationshipsScreen(),
        ),
        GoRoute(
          path: AppRoutes.communityClubs,
          builder: (_, _) => const ClubListScreen(),
        ),
        GoRoute(
          path: AppRoutes.communityClubDetail,
          builder: (_, state) => ClubDetailScreen(
            clubId: ContentId(state.pathParameters['clubId']!),
          ),
        ),
      ],
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
                // E16-R02 (ADR 0500) — replaces the legacy `ProgressScreen`
                // adapter with the real Progress V2 dashboard, built from
                // the measured mastery catalog + practice history (§5.1).
                // The legacy `ProgressScreen` itself stays wired, unchanged,
                // at the bare `/progress` route above (A5).
                GoRoute(
                  path: AppRoutes.profileProgress,
                  builder: (_, _) => Consumer(
                    builder: (context, ref, _) {
                      final l10n = AppLocalizations.of(context);
                      final projection = buildProgressOverviewProjection(
                        milestoneCatalog: masteryMilestoneCatalogV1,
                        practiceHistory: ref.watch(
                          progressPracticeHistoryProvider,
                        ),
                        practiceCatalog: ref.watch(practiceCatalogProvider),
                        now: ref.watch(progressNowProvider),
                        isOffline: progressV2IsOffline,
                        localize: (key) => progressV2LocalizedText(l10n, key),
                      );
                      return ProgressDashboardScreen(
                        projection: projection,
                        onOpenSkillDetail: (milestoneId) {
                          final milestone = _masteryMilestoneById(milestoneId);
                          if (milestone == null) return;
                          context.push(
                            AppRoutes.profileProgressSkill.replaceFirst(
                              ':skillId',
                              milestone.skill.code,
                            ),
                          );
                        },
                        onGetStarted: () => context.push(AppRoutes.practiceHub),
                      );
                    },
                  ),
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
      // canonical V2 destinations. E16-R01 (ADR 0496) moved the composition
      // — repository/curve/profile/streak/inbox/achievement projections —
      // into the feature's own `gamification_providers.dart`; this block
      // only reads those public providers.
      GoRoute(
        path: AppRoutes.gamificationHub,
        builder: (_, _) => Consumer(
          builder: (context, ref, _) {
            final profile = ref.watch(gamificationProfileProvider);
            final streakState = ref.watch(streakStateProvider);
            final activeQuests = ref.watch(activeQuestCountProvider);
            final masteryUnlocked = ref.watch(masteryUnlockedCountProvider);
            final unseenCount = ref.watch(inboxUnseenCountProvider);
            return GamificationHubScreen(
              profile: profile,
              activeQuestCount: activeQuests.value,
              streakCurrentDays: streakState.current,
              masteryUnlockedCount: masteryUnlocked.value,
              inboxUnseenCount: unseenCount,
              onOpenLevelDetail: () => context.push(AppRoutes.levelDetail),
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
        path: AppRoutes.levelDetail,
        builder: (_, _) => Consumer(
          builder: (context, ref, _) {
            final l10n = AppLocalizations.of(context);
            final profile = ref.watch(gamificationProfileProvider);
            // BACKLOG (`docs/ui/legacy-backlog.md`, E16-R01 entry 5):
            // `.value` is passed through unconditionally because
            // `LevelDetailScreen` has no absence contract for this required
            // parameter (review M1) — `.available` stays unread until a
            // future round adds one.
            final latestSessionXp = ref.watch(latestSessionXpProvider).value;
            return LevelDetailScreen(
              profile: profile,
              latestSessionXp: latestSessionXp,
              components: buildR06XpComponents(l10n: l10n, xp: latestSessionXp),
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.achievements,
        builder: (_, _) => Consumer(
          builder: (context, ref, _) => _achievementsAsyncBuilder(
            ref: ref,
            onData: (progressByAchievement) => AchievementsScreen(
              definitions: defaultAchievementCatalog.definitions,
              progressByAchievement: progressByAchievement,
              onAchievementSelected: (String id) => context.pushNamed(
                _achievementDetailName,
                pathParameters: <String, String>{'achievementId': id},
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        name: _achievementDetailName,
        path: AppRoutes.achievementDetail,
        builder: (_, state) => Consumer(
          builder: (context, ref, _) => _achievementsAsyncBuilder(
            ref: ref,
            onData: (progressByAchievement) => AchievementDetailScreen(
              achievementId: state.pathParameters['achievementId']!,
              definitions: defaultAchievementCatalog.definitions,
              progressByAchievement: progressByAchievement,
            ),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.quests,
        builder: (_, _) => Consumer(
          builder: (context, ref, _) {
            final l10n = AppLocalizations.of(context);
            final questBoard = ref.watch(questBoardProvider);
            return QuestsScreen(
              dailyChallengeTitle: l10n.challengeDailyTitle,
              dailyChallenge: questBoard.dailyChallenge,
              dailyChallengeAvailable: questBoard.dailyChallengeAvailable,
              dailyQuests: questBoard.dailyQuests,
              weeklyQuests: questBoard.weeklyQuests,
              onAction: (QuestRouteAction action) {
                switch (action) {
                  case QuestStartPracticeAction():
                    context.push(AppRoutes.practiceHub);
                  case QuestContinuePracticeAction():
                    context.push(AppRoutes.practiceHub);
                  case QuestTryLiveAction():
                    context.push(AppRoutes.live);
                  case QuestUnavailableAction():
                    // The card itself disables the CTA whenever content is
                    // unavailable, so this case fires only from a direct
                    // test call, never a live tap — intentionally a no-op.
                    break;
                }
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
            final evaluation = ref.watch(streakEvaluationProvider);
            final weeklyConsistencyDays = ref.watch(
              weeklyConsistencyDaysProvider,
            );
            return StreakDetailScreen(
              state: evaluation.state,
              reason: evaluation.reason,
              weeklyConsistencyDays: weeklyConsistencyDays.value,
              onRecoveryPressed: () {
                // BACKLOG (`docs/ui/legacy-backlog.md`, E16-R01 entry 2):
                // no repository method exists to purchase/apply a streak
                // recovery, and `StreakDetailScreen` has no "recovery
                // unavailable" contract to fall back to (screens are this
                // round's tilos zona) — the button stays rendered but inert.
              },
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.rewardInbox,
        builder: (_, _) => Consumer(
          builder: (context, ref, _) {
            final l10n = AppLocalizations.of(context);
            return RewardInboxScreen(
              items: _localizedRewardInboxItems(
                ref.watch(rewardInboxItemsProvider),
                l10n,
              ),
              onItemSelected: (_) {
                // BACKLOG (`docs/ui/legacy-backlog.md`, E16-R01 entry 3): no
                // reward-detail screen exists on the tree to navigate to —
                // building one is new scope, not a bekötés.
              },
              onMarkSeen: (RewardInboxItem item) {
                // Review m2: the screen's `onMarkSeen` contract is `void`
                // (tilos zona), so this Future cannot be awaited by the
                // caller — `unawaited` + `catchError` at least turns a
                // silently-dropped write failure into a logged one instead
                // of an unhandled async error.
                unawaited(
                  markGamificationInboxItemSeen(
                    current: ref.read(gamificationInboxProvider),
                    repository: ref.read(gamificationRepositoryProvider),
                    id: item.id,
                    onWritten: () => ref.invalidate(gamificationInboxProvider),
                    onReplaced: (report) {
                      if (report.trimmedCount > 0) {
                        ref
                            .read(appLoggerProvider)
                            .warning(
                              'gamification.reward_inbox.trimmed',
                              fields: {'trimmedCount': report.trimmedCount},
                            );
                      }
                    },
                  ).catchError((Object error, StackTrace stackTrace) {
                    ref
                        .read(appLoggerProvider)
                        .error(
                          'gamification.reward_inbox.mark_seen_failed',
                          error: error,
                          stackTrace: stackTrace,
                        );
                  }),
                );
              },
            );
          },
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
