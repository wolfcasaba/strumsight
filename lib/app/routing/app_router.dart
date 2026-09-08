import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/foundation/app_result.dart';
import '../../core/logging/logger_provider.dart';
import '../../features/analyze/screens/analyze_screen.dart';
import '../../features/audio_analysis/application/analysis_providers.dart';
import '../../features/audio_analysis/application/capture_seed.dart';
import '../../features/audio_analysis/application/compare_analyses_use_case.dart';
import '../../features/audio_analysis/application/import_audio_file_use_case.dart';
import '../../features/audio_analysis/domain/analysis_document.dart';
import '../../features/audio_analysis/domain/analysis_input.dart';
import '../../features/audio_analysis/domain/analysis_mode.dart';
import '../../features/audio_analysis/domain/analysis_summary.dart';
import '../../features/audio_analysis/presentation/capture/analysis_compare_picker.dart';
import '../../features/audio_analysis/presentation/capture/analysis_home_screen.dart';
import '../../features/audio_analysis/presentation/capture/analysis_import_messages.dart';
import '../../features/audio_analysis/presentation/capture/analysis_processing_screen.dart';
import '../../features/audio_analysis/presentation/capture/analysis_recording_screen.dart';
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
import '../../features/library_v2/providers/library_v2_providers.dart';
import '../../features/library_v2/screens/library_item_detail_screen.dart';
import '../../features/library_v2/screens/unified_library_screen.dart';
import '../../features/live/screens/live_screen.dart';
import '../../features/metronome/screens/metronome_screen.dart';
import '../../features/onboarding/onboarding_provider.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/practice/presentation/practice_result_route.dart';
import '../../features/practice/presentation/screens/practice_hub_screen.dart';
import '../../features/practice/presentation/screens/practice_setup_screen.dart';
import '../../features/practice/presentation/screens/practice_session_screen.dart';
import '../../features/practice/public.dart'
    show practiceCatalogProvider, practiceCategoryFromCode;
import '../../features/practice_generator/application/usecase/revise_practice_plan.dart'
    show PlanRevisionProposal;
import '../../features/practice_generator/application/controller/today_plan_controller.dart'
    show TodayPlanRouteRequest;
import '../../features/practice_generator/presentation/plan_generation_launch.dart';
import '../../features/practice_generator/presentation/plan_preview_args.dart';
import '../../features/practice_generator/presentation/providers/practice_generator_providers.dart';
import '../../features/practice_generator/presentation/screens/plan_change_review_screen.dart';
import '../../features/practice_generator/presentation/screens/plan_preview_screen.dart';
import '../../features/practice_generator/presentation/screens/plan_privacy_screen.dart';
import '../../features/practice_generator/presentation/screens/weekly_plan_screen.dart';
import '../../features/practice_generator/presentation/screens/plan_setup_screen.dart';
import '../../features/practice_generator/presentation/screens/today_plan_screen.dart';
import '../../features/practice_generator/presentation/today_plan_actions.dart';
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
import '../../features/song_trainer/domain/models/song_setlist.dart';
import '../../features/song_trainer/presentation/screens/setlist_list_screen_v2.dart';
import '../../features/song_trainer/presentation/screens/setlist_session_route.dart';
import '../../features/song_trainer/presentation/screens/setlist_session_screen.dart';
import '../../features/song_trainer/presentation/screens/song_editor_screen.dart';
import '../../features/song_trainer/presentation/screens/song_overview_screen.dart';
import '../../features/song_trainer/presentation/screens/song_result_route.dart';
import '../../features/song_trainer/presentation/screens/song_trainer_screen.dart';
import '../../features/song_trainer/presentation/screens/trainer_setup_screen.dart';
import '../../features/song_trainer/presentation/song_trainer_launch.dart';
import '../../features/ai_tutor/presentation/practice_plan_preview_route.dart';
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

/// R18 (audit M5) — opens one unified-library session detail from a Progress
/// V2 evidence row.
///
/// [AppRoutes.profileLibrarySession]'s redirect requires an `extra` of type
/// [LibraryItem]; a push without one silently lands on the library LIST,
/// which is the wrong page dressed up as a working link. This resolves the
/// item out of the already-aggregated library and passes it as `extra`. When
/// it cannot be resolved the miss is SPOKEN (a snackbar) instead of
/// navigating somewhere the row did not name.
///
/// R34 (audit MI-C) — the aggregation's THREE states are now three answers.
/// The caller used to hand over `libraryItems.value`, which is `null` both
/// while the unified library is still being read AND when the read failed;
/// every one of those taps was answered with "this session is no longer
/// available", i.e. the app claimed a session was GONE while it was still
/// loading. A load in flight is not a miss, and telling the user to wait is
/// the only honest thing to say about it.
void _openLibrarySession(
  BuildContext context, {
  required AppLocalizations l10n,
  required AsyncValue<List<LibraryItem>> items,
  required String route,
  required String sessionId,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final resolved = items.value;
  if (resolved == null) {
    // No data yet. `hasError` separates "the library could not be read"
    // (a real unavailability) from "not finished yet" (a wait).
    messenger.showSnackBar(
      SnackBar(
        key: Key(
          items.hasError
              ? 'progress-evidence-unavailable'
              : 'progress-evidence-loading',
        ),
        content: Text(
          items.hasError
              ? l10n.progressEvidenceUnavailable
              : l10n.progressEvidenceLoading,
        ),
      ),
    );
    return;
  }
  LibraryItem? match;
  for (final item in resolved) {
    if (item.id == sessionId) {
      match = item;
      break;
    }
  }
  if (match == null) {
    messenger.showSnackBar(
      SnackBar(
        key: const Key('progress-evidence-unavailable'),
        content: Text(l10n.progressEvidenceUnavailable),
      ),
    );
    return;
  }
  context.push(route.replaceFirst(':sessionId', sessionId), extra: match);
}

/// R26 (audit MI4) — the "Import file" CTA's real flow.
///
/// The CTA used to say, honestly, that no import flow existed. It does now:
/// the picker hands back bytes, the WAV boundary decoder (`E06-R05`, already
/// tested) turns them into validated PCM, and that PCM starts the IDENTICAL
/// `AnalysisController.analyze` run a microphone capture starts — same
/// isolate, same 20 stages, same processing screen. The pipeline never
/// learns where the samples came from beyond the input's own enum.
///
/// A container this build cannot decode is still SPOKEN, not swallowed:
/// `analysisImportMessage` names the actual reason (unsupported container,
/// too large, too short, too long, unreadable), so the user knows what to
/// fix instead of facing a button that appears to do nothing.
Future<void> _startAnalysisImport(BuildContext context, WidgetRef ref) async {
  final outcome = await ref.read(importAudioFileUseCaseProvider)();
  // The picker is a full-screen platform surface: the user can leave this
  // route while it is open. Everything after this point touches `ref` and
  // `context`, both of which are invalid once that happens.
  if (!context.mounted) return;
  if (outcome case AudioFileImportReady(:final audio)) {
    ref
        .read(analysisCaptureOriginProvider.notifier)
        .markStarted(AnalysisInputSource.importedFile);
    unawaited(
      ref
          .read(analysisControllerProvider.notifier)
          .analyze(
            captureSeedDocument(
              runId: 'import-${DateTime.now().microsecondsSinceEpoch}',
              audio: audio,
              createdAt: DateTime.now(),
              mode: AnalysisMode.importedRecording,
            ),
            audio: ValidatedPcmAnalysisInput(input: audio),
          ),
    );
    // `push`, NEM `go` (R17-minta): a kezdőlapot maga is `push` nyitotta az
    // Elemzés fülről, és egy `go` az egész stacket lecserélné — a
    // feldolgozó képernyőről nem lenne visszaút sehová.
    context.push(AppRoutes.analysisProcessing);
    return;
  }
  final message = analysisImportMessage(AppLocalizations.of(context), outcome);
  // A cancelled picker says nothing — dismissing a chooser is not an error.
  if (message == null) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// R32 (re-audit #2) — opens ONE saved analysis from the "recent" list.
///
/// The card used to `push` [AppRoutes.analysisTimeline] with the SUMMARY as
/// `extra`, but that route's redirect accepts an [AnalysisDocument] and
/// nothing else: every tap on a recent analysis was redirected to `/live`,
/// so the list has never opened anything. A summary is an index row — it
/// carries a title, a date and a hash, never the timeline — so the document
/// has to be READ BACK by id (R26 made sure fresh runs are written there in
/// the first place).
///
/// The read is spoken in both directions: a progress snackbar while the
/// document is decoded, and a NAMED failure when the id is gone or the file
/// is corrupt. A miss must not navigate: landing on `/live` would be the
/// wrong page dressed up as a working link (the `_openLibrarySession`
/// precedent above).
Future<void> _openRecentAnalysis(
  BuildContext context,
  WidgetRef ref,
  AnalysisSummary summary,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      key: const Key('analysis-home-open-progress'),
      content: Text(l10n.analysisHomeOpeningAnalysis),
    ),
  );
  final result = await ref
      .read(analysisRepositoryProvider)
      .getById(summary.documentId);
  // The read is a file decode: the user can leave this route while it runs,
  // and everything below touches `context`.
  if (!context.mounted) return;
  messenger.hideCurrentSnackBar();
  switch (result) {
    case Success<AnalysisDocument>(:final value):
      // `push`, NEM `go` (R30): a napló a kezdőlap FÖLÉ kerül, tehát a
      // saját vissza-nyila és a rendszer-vissza is ide vezet vissza.
      context.push(AppRoutes.analysisTimeline, extra: value);
    case Failure<AnalysisDocument>():
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.analysisHomeOpenFailed)),
      );
  }
}

/// R34 (audit M11) — the analysis COMPARISON's only entry point.
///
/// Measured before this round: `CompareAnalysesUseCase` — the single
/// producer of an `AnalysisComparison` — had ZERO `lib/` callers, and
/// `AppRoutes.analysisCompare` had zero navigations, while
/// `analysisComparisonEnabled` was ON in the shipped development build. The
/// whole feature (use case, compatibility evaluator, screen, ARB copy) was
/// finished and unreachable.
///
/// The flow mirrors [_openRecentAnalysis] exactly: pick, read the SAVED
/// documents back by id (a summary carries no metrics at all), and push
/// only on a complete pair. A failed read is NAMED and navigates nowhere —
/// the compare route's own redirect would otherwise bounce the user to
/// `/live` for a reason they could not see.
Future<void> _openAnalysisCompare(
  BuildContext context,
  WidgetRef ref,
  List<AnalysisSummary> summaries,
) async {
  final l10n = AppLocalizations.of(context);
  final pair = await showAnalysisComparePicker(context, summaries: summaries);
  // The sheet is a route: the user can leave the Analyze home while it is
  // open, and everything below touches `context`.
  if (pair == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      key: const Key('analysis-compare-progress'),
      content: Text(l10n.analysisCompareLoading),
    ),
  );
  final repository = ref.read(analysisRepositoryProvider);
  final before = await repository.getById(pair.before.documentId);
  final after = await repository.getById(pair.after.documentId);
  if (!context.mounted) return;
  messenger.hideCurrentSnackBar();
  final beforeDocument = switch (before) {
    Success<AnalysisDocument>(:final value) => value,
    Failure<AnalysisDocument>() => null,
  };
  final afterDocument = switch (after) {
    Success<AnalysisDocument>(:final value) => value,
    Failure<AnalysisDocument>() => null,
  };
  if (beforeDocument == null || afterDocument == null) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.analysisCompareLoadFailed)),
    );
    return;
  }
  final comparison = const CompareAnalysesUseCase()(
    before: beforeDocument,
    after: afterDocument,
  );
  // `push`, NEM `go` (R30): the comparison lands ON TOP of the Analyze
  // home, so the ordinary pop is the way back.
  context.push(AppRoutes.analysisCompare, extra: comparison);
}

/// R30 (re-audit #2 B2) — leaves one step of the Analysis V2 capture chain.
///
/// Every step of that chain is now `push`ed, so the previous one is still
/// underneath and popping is exactly what "cancel" / "start over" mean.
/// [fallback] covers the one case a pop cannot: a step reached with nothing
/// under it (a deep link, a redirect target). A bare `maybePop` there would
/// be a silent no-op — the dead-control class this round closes.
void _leaveAnalysisStep(BuildContext context, String fallback) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
    return;
  }
  GoRouter.maybeOf(context)?.go(fallback);
}

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
  // A community AL-zászlói. A képernyők doc-kommentjei eddig azt ÁLLÍTOTTÁK,
  // hogy egy kikapcsolt al-zászló mellett a route sincs regisztrálva — a
  // tábla viszont mindhármat pusztán `communityEnabled` alatt hozta létre
  // (MÉRT hiba, 2026-09-06 review, MINOR-6). Az állítás itt válik igazzá:
  // az író-felület, a klubok és a ranglista saját kapuval regisztrálódik.
  final communityWritesEnabled = ref
      .read(appConfigProvider)
      .flags
      .communityWritesEnabled;
  final communityClubsEnabled = ref
      .read(appConfigProvider)
      .flags
      .communityClubsEnabled;
  final communityLeaderboardEnabled = ref
      .read(appConfigProvider)
      .flags
      .communityLeaderboardEnabled;
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
      // Setlist V2 (R10, audit §5.2). Until now `SetlistListScreenV2` and
      // `SetlistSessionScreen` had no route and no construction site
      // anywhere in `lib/` — measured `unreachable` by
      // `tool/check_screen_reachability.dart`. Tapping a setlist opens the
      // ordered session; the session's per-item runner launches the real
      // Song Trainer session for each item and waits for it, which is what
      // makes the setlist advance item by item.
      GoRoute(
        path: AppRoutes.setlistsV2,
        builder: (_, _) => Consumer(
          builder: (context, ref, _) => SetlistListScreenV2(
            controller: ref.watch(setlistControllerProvider),
            clock: DateTime.now,
            onOpenSetlist: (setlist) => openSetlistSession(context, setlist),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.setlistSession,
        redirect: (_, state) =>
            state.extra is SongSetlist ? null : AppRoutes.setlistsV2,
        builder: (_, state) => Consumer(
          builder: (context, ref, _) => SetlistSessionScreen(
            setlist: state.extra! as SongSetlist,
            // Practice is the only mode the shipped app can honestly run:
            // every song session the trainer offers is the scored one.
            mode: SetlistSessionMode.practice,
            availability: (item) => item.initialAvailability,
            performanceRunner: unavailableSetlistPerformanceRunner,
            createPracticeRunner: () => setlistItemRunner(context, ref),
          ),
        ),
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
            // R18 (audit M5) — the unified library's items, WATCHED here so
            // the aggregation starts loading while the user reads the skill
            // detail. MÉRT hiba: the evidence rows used to push
            // `/profile/library/session/:sessionId` with NO `extra`, and that
            // route's own redirect requires `state.extra is LibraryItem` —
            // so every evidence tap silently landed on the library LIST
            // instead of the session it named.
            final libraryItems = ref.watch(libraryV2ItemsProvider);
            return SkillDetailScreen(
              projection: projection,
              onOpenEvidence: (route, sessionId) => _openLibrarySession(
                context,
                l10n: l10n,
                items: libraryItems,
                route: route,
                sessionId: sessionId,
              ),
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
        if (communityWritesEnabled)
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
        if (communityLeaderboardEnabled)
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
        if (communityClubsEnabled) ...[
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
        // R18 (audit B2) — the catalog LIST, registered regardless of the
        // shell flag. Measured defect: with the shell on, `/practice` renders
        // the Practice AREA hub, whose only definition-carrying control is
        // the recommended CTA (`catalog.first`); the registration above is
        // `!adaptiveShellEnabled`-only, so nine of the ten built-in practices
        // had NO on-screen entry point in the shipped build. Declared here
        // (before the shell below) so it stays a top-level, pushable route:
        // the hub `push`es it and the user pops straight back.
        GoRoute(
          path: AppRoutes.practiceCatalog,
          builder: (_, state) => PracticeHubScreen(
            category: practiceCategoryFromCode(
              state.uri.queryParameters['category'],
            ),
          ),
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
          builder: (_, _) => const PracticeResultRoute(),
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
            builder: (context, ref, _) {
              // Javító sáv 2026-09-06 (R4): watched, not read — the
              // generation use case is autoDispose and must outlive the
              // wizard's last step (its own doc-comment's rule).
              final startGeneration = ref.watch(startPlanGenerationProvider);
              return PlanSetupScreen(
                controller: ref.watch(planSetupControllerProvider),
                onFinished: (request) => launchPlanGeneration(
                  context,
                  ref,
                  startGeneration,
                  request,
                ),
              );
            },
          ),
        ),
        GoRoute(
          path: AppRoutes.practiceGeneratorToday,
          // Javító sáv 2026-09-06 (R4): the screen used to be built WITHOUT
          // the plan (always "no active plan") and WITHOUT callbacks (every
          // action button disabled). R10 (2026-09-07) binds `swap` too —
          // `ActivePlanController.swap` now rewrites today's first pending
          // block to a same-skill catalog alternative.
          builder: (_, state) => Consumer(
            builder: (context, ref, _) {
              // R18 (audit M6) — `.value` alone made BOTH loading and error
              // read as `null`, and `null` is this screen's measured "no
              // active plan" state. A user whose stored plan failed to load
              // was told they have no plan at all. The three states are
              // distinct here now.
              final planAsync = ref.watch(activePracticePlanProvider);
              return planAsync.when(
                loading: () => _RouteLoadingScaffold(
                  key: const Key('today-plan-route-loading'),
                  exitLocation: entryLocation,
                ),
                error: (_, _) => _RouteErrorScaffold(
                  key: const Key('today-plan-route-error'),
                  exitLocation: entryLocation,
                  onRetry: () => ref.invalidate(activePracticePlanProvider),
                ),
                data: (plan) => TodayPlanScreen(
                  controller: ref.watch(todayPlanControllerProvider),
                  plan: plan,
                  launchRequest: TodayPlanRouteRequest.tryParse(state.extra),
                  isTodayRouteEnabled: true,
                  onStart: (block) => openPracticeForBlock(context, block),
                  onSwap: (_) =>
                      runTodayPlanAction(context, ref, TodayPlanAction.swap),
                  onSkip: (_) =>
                      runTodayPlanAction(context, ref, TodayPlanAction.skip),
                  onShorten: () =>
                      runTodayPlanAction(context, ref, TodayPlanAction.shorten),
                  onPause: () =>
                      runTodayPlanAction(context, ref, TodayPlanAction.pause),
                ),
              );
            },
          ),
        ),
        GoRoute(
          path: AppRoutes.practiceGeneratorWeekly,
          builder: (_, _) => Consumer(
            builder: (context, ref, _) {
              final plan = ref.watch(activePracticePlanProvider);
              // A `plan` a képernyő szerződésében NULLAZHATÓ, és a `null`
              // ott a „még nincs terv" állapot — nem hiányzó adat.
              // R18 (audit M6): éppen EZÉRT nem mehet be a `.value` nyersen.
              // A betöltés és a hiba is `null`-lá lapult, tehát a képernyő
              // mindkettőt „nincs terved"-ként mondta ki. A `null` csak a
              // `data` ágon jelenthet hiányzó tervet.
              return plan.when(
                loading: () => _RouteLoadingScaffold(
                  key: const Key('weekly-plan-route-loading'),
                  exitLocation: entryLocation,
                ),
                error: (_, _) => _RouteErrorScaffold(
                  key: const Key('weekly-plan-route-error'),
                  exitLocation: entryLocation,
                  onRetry: () => ref.invalidate(activePracticePlanProvider),
                ),
                data: (value) => WeeklyPlanScreen(
                  plan: value,
                  today: ref.watch(practiceGeneratorTodayProvider)(),
                ),
              );
            },
          ),
        ),
        GoRoute(
          path: AppRoutes.practiceGeneratorPrivacy,
          builder: (_, _) => Consumer(
            builder: (context, ref, _) => PlanPrivacyScreen(
              deleteUseCase: ref.watch(deletePracticePlanningDataProvider),
              exportUseCase: ref.watch(exportPracticePlanningDataProvider),
            ),
          ),
        ),
        // Az előnézet és a változás-áttekintés a generálási folyamat
        // LÉPÉSEI: a megjelenítendő tervet, illetve javaslatot a hívó adja
        // át. `extra` nélkül nincs mit mutatni — ilyenkor a mai tervre
        // esünk vissza, nem rajzolunk kitalált tervet. Ugyanaz a
        // redirect-őr, amit az elemzés-áttekintés használ.
        GoRoute(
          path: AppRoutes.practiceGeneratorPreview,
          redirect: (_, state) => state.extra is PracticePlanPreviewArgs
              ? null
              : AppRoutes.practiceGeneratorToday,
          builder: (_, state) => Consumer(
            builder: (context, ref, _) {
              final args = state.extra! as PracticePlanPreviewArgs;
              return PlanPreviewScreen(
                controller: ref.watch(planPreviewControllerFactoryProvider)(
                  initialPlan: args.plan,
                  validationContext: args.validationContext,
                ),
              );
            },
          ),
        ),
        GoRoute(
          path: AppRoutes.practiceGeneratorChangeReview,
          redirect: (_, state) => state.extra is PlanRevisionProposal
              ? null
              : AppRoutes.practiceGeneratorToday,
          builder: (_, state) => Builder(
            builder: (context) => PlanChangeReviewScreen(
              proposal: state.extra! as PlanRevisionProposal,
              // Mindkét ág a mai tervre visz vissza. A javaslat
              // ELFOGADÁSA a `RevisePracticePlan` dolga, és azt a hívó
              // folyamat végzi el — a route nem ír tervet, mert akkor a
              // döntés két helyen születne.
              onAccepted: () => context.go(AppRoutes.practiceGeneratorToday),
              onRejected: () => context.go(AppRoutes.practiceGeneratorToday),
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
          // Javító sáv 2026-09-06 (R3): Start had no handler here — the
          // completed config went nowhere and the session route was never
          // pushed. `launchSongTrainerSession` builds the inputs and pushes.
          builder: (_, state) => Consumer(
            builder: (context, ref, _) => TrainerSetupScreen(
              songId: state.pathParameters['songId']!,
              onComplete: (config) =>
                  launchSongTrainerSession(context, ref, config),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.songTrainerSession,
          builder: (_, state) => SongTrainerScreen(
            songId: state.pathParameters['songId']!,
            inputs: state.extra! as SongTrainerControllerInputs,
            autoStart: true,
          ),
        ),
        GoRoute(
          path: AppRoutes.songTrainerResult,
          // Javító sáv 2026-09-06 (R8): the screen used to be built with the
          // result alone, which left both of its CTAs permanently disabled.
          // `SongTrainerResultRoute` supplies the retry / next handlers and
          // the stored per-measure progress projection.
          builder: (_, state) => SongTrainerResultRoute(
            args: SongTrainerResultArgs.from(state.extra),
          ),
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
                // R30 (re-audit #2 M4) — the tile that opens this route
                // PUSHES it, but the screen builds no `Scaffold` of its own
                // and the adaptive shell supplies none with an app bar: the
                // pushed page carried no visible way back at all (only the
                // system gesture). Same adapter idea as `/practice/live`
                // above — a route-level `Scaffold` for a screen that brings
                // none — plus the exit this one needs. The bar repeats the
                // screen's own headline on purpose: that headline lives
                // outside this round's files, and a titleless bar would
                // render as an empty strip whenever this route is the
                // branch's own first page.
                GoRoute(
                  path: AppRoutes.practiceAnalyze,
                  builder: (_, _) => Builder(
                    builder: (context) => Scaffold(
                      appBar: AppBar(
                        // The router's own pop-ability, not the branch
                        // navigator's: this route lives INSIDE a shell
                        // branch, and a pushed branch route is a second
                        // shell instance whose inner navigator holds a
                        // single page — an implied leading would be absent
                        // there, and a plain back control would pop a
                        // navigator with nothing on it. No leading at all
                        // when the route is the branch's own first page,
                        // so no dead control is ever drawn.
                        leading: context.canPop()
                            ? BackButton(onPressed: () => context.pop())
                            : null,
                        title: Text(AppLocalizations.of(context).navAnalyze),
                      ),
                      body: const AnalyzeScreen(),
                    ),
                  ),
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
        GoRoute(
          path: AppRoutes.tutorPlanPreview,
          builder: (_, _) => const PracticePlanPreviewRoute(),
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
        // A felvételi folyamat (2026-09-05). A három képernyő azért volt
        // elérhetetlen, mert HÁROM darab hiányzott alóla: a vezérlőnek nem
        // volt providere, a felvevőnek sem, és az `AnalyzeAudioUseCase`
        // ÜRES mintákat adott tovább — bekötve tehát csendet elemzett volna.
        GoRoute(
          path: AppRoutes.analysisCapture,
          builder: (_, _) => Consumer(
            builder: (context, ref, _) {
              final recent = ref.watch(analysisRecentSummariesProvider);
              // R18 (audit M6) — a `recent.value ?? const []` a provider
              // SZÁNDÉKOS hibaágát (`analysis_providers.dart`: a `Failure`
              // dob, hogy a hiba megkülönböztethető maradjon) pontosan azzá
              // az üres listává lapította, amit a képernyő „nincs korábbi
              // elemzés"-ként mond ki. A három állapot innentől három
              // különböző felület.
              return recent.when(
                loading: () => _RouteLoadingScaffold(
                  key: const Key('analysis-home-route-loading'),
                  exitLocation: entryLocation,
                ),
                error: (_, _) => _RouteErrorScaffold(
                  key: const Key('analysis-home-route-error'),
                  exitLocation: entryLocation,
                  onRetry: () =>
                      ref.invalidate(analysisRecentSummariesProvider),
                ),
                data: (summaries) => AnalysisHomeScreen(
                  recentAnalyses: summaries,
                  // R30 (re-audit #2 B2) — `push`, NEM `go`: minden lépés a
                  // kezdőlap FÖLÉ kerül, tehát a rendszer-vissza és az
                  // érkező keret saját vissza-nyila is ide vezet vissza. A
                  // `go` a stacket eldobta, és az érkező képernyőn
                  // `canPop == false` maradt — kijárat nélkül.
                  onStartRecording: () =>
                      context.push(AppRoutes.analysisRecord),
                  // R26 (audit MI4) — a CTA VALÓDI importot nyit. A
                  // korábbi őszinte hiány-üzenet helyére a folyamat lépett;
                  // a „nem tudom dekódolni" eset megmaradt, de már a
                  // konkrét okot mondja ki (`analysis_import_messages.dart`).
                  onImportFile: () =>
                      unawaited(_startAnalysisImport(context, ref)),
                  // R32 (re-audit #2) — a kártya a MENTETT DOKUMENTUMOT
                  // nyitja meg; az összefoglaló önmagában a `/live`-ra
                  // dobta a felhasználót (`_openRecentAnalysis`).
                  onOpenAnalysis: (summary) =>
                      unawaited(_openRecentAnalysis(context, ref, summary)),
                  // R34 (audit M11) — the comparison's entry point, gated
                  // on its OWN flag. `null` when the flag is off, and the
                  // screen then renders no action at all: a "Compare"
                  // control in front of a route that is not registered
                  // would be the dead-control class this bar closes.
                  onCompareAnalyses: analysisComparisonEnabled
                      ? () => unawaited(
                          _openAnalysisCompare(context, ref, summaries),
                        )
                      : null,
                ),
              );
            },
          ),
        ),
        GoRoute(
          path: AppRoutes.analysisRecord,
          builder: (_, _) => Consumer(
            builder: (context, ref, _) {
              // `watch`, nem `read`: az autoDispose felvevőt a widget
              // életciklusa tartja életben, és a képernyő elhagyásakor
              // eldobódik — a következő felvétel FRISS példányt kap. Egy
              // `read` azonnal eldobná, egy nem-autoDispose provider pedig
              // a képernyő által már lezárt felvevőt adná vissza másodszor.
              final recorder = ref.watch(analysisCaptureRecorderProvider);
              return AnalysisRecordingScreen(
                recorder: recorder,
                onCancel: () =>
                    _leaveAnalysisStep(context, AppRoutes.analysisCapture),
                onFinished: (run, samples) {
                  final pcm = PcmAnalysisInput(
                    samples: samples,
                    sampleRate: run.sampleRate,
                    channelCount: 1,
                    source: AnalysisInputSource.microphone,
                  );
                  ref
                      .read(analysisCaptureOriginProvider.notifier)
                      .markStarted(AnalysisInputSource.microphone);
                  unawaited(
                    ref
                        .read(analysisControllerProvider.notifier)
                        .analyze(
                          captureSeedDocument(
                            runId: run.id,
                            audio: pcm,
                            createdAt: DateTime.now(),
                          ),
                          audio: ValidatedPcmAnalysisInput(input: pcm),
                        ),
                  );
                  context.push(AppRoutes.analysisProcessing);
                },
              );
            },
          ),
        ),
        GoRoute(
          path: AppRoutes.analysisProcessing,
          builder: (_, _) => Consumer(
            builder: (context, ref, _) {
              // R26 — a MENTÉS a vezérlőben történik
              // (`AnalysisController._persistOnce`), nem itt: ez az útvonal
              // csak addig lát, amíg fel van építve, az import viszont
              // elindítja a futást és a következő képkockán navigál. Ami
              // ide tartozik, az a HIBA kimondása — egy elnyelt írási hiba
              // azt a látszatot keltené, hogy az elemzés megmaradt, pedig a
              // „legutóbbi elemzések" listába sosem kerülne be.
              ref.listen(analysisPersistenceStatusProvider, (_, failure) {
                if (failure == null) return;
                final l10n = AppLocalizations.of(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.analysisSaveFailed)),
                );
              });
              final state = ref.watch(analysisControllerProvider);
              final imported =
                  ref.watch(analysisCaptureOriginProvider) ==
                  AnalysisInputSource.importedFile;
              return AnalysisProcessingScreen(
                state: state,
                onCancel: () => unawaited(
                  ref.read(analysisControllerProvider.notifier).cancel(),
                ),
                // Egy importált futás után a felvevő képernyő HAZUDNA a
                // bemenetről; a „kezdés elölről" oda visz vissza, ahonnan
                // ez a futás indult.
                // R30 — a lépés a felvevő (mikrofon) vagy a kezdőlap
                // (import) FÖLÖTT áll, tehát a „kezdés elölről" ugyanoda
                // POPPOL vissza, ahonnan ez a futás indult; a `go`-s cím
                // csak akkor kell, ha nincs mit poppolni (mély link).
                onRestart: () => _leaveAnalysisStep(
                  context,
                  imported
                      ? AppRoutes.analysisCapture
                      : AppRoutes.analysisRecord,
                ),
                onViewResult: (document) =>
                    context.push(AppRoutes.analysisOverview, extra: document),
              );
            },
          ),
        ),
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
              // R22 (audit MI1): the CTA's own copy is "Start a recovery
              // practice" (`streakV2RecoveryCta`), and the ONLY recovery
              // concept this domain has is `StreakEvaluationRequest`'s
              // `recoveryEligible` — a lower qualification threshold for a
              // practice session, never a purchasable token or a grace-day
              // claim. So the honest behaviour is the one the label
              // promises: take the user to the practice hub where such a
              // session starts. Same precedent as `QuestStartPracticeAction`
              // above.
              //
              // R34 — the CTA now also CREDITS the recovery it promises.
              // R22's "no state is mutated here" no longer holds, and that
              // is the point: it held only because no repository could
              // grant a recovery. Still nothing touches the ledger, the
              // freeze count or the streak state — a recovery is a lower
              // BAR for the next session, never a day the learner did not
              // practise.
              // `StreakRecoveryGrantStore.grant` persists a SINGLE-USE
              // lower qualification threshold for the next session
              // (`docs/ui/legacy-backlog.md` §6.2); the grant is only spent
              // by a day that has a canonical activity, so tapping the CTA
              // and then not practising cannot burn it. Navigation is
              // unchanged — the hub is still where such a session starts.
              onRecoveryPressed: () {
                unawaited(
                  ref
                      .read(streakRecoveryGrantStoreProvider)
                      .grant(ref.read(todayEpochDayProvider)),
                );
                context.push(AppRoutes.practiceHub);
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
              // R22 (audit MI2): opening a row shows the already-built
              // `RewardSummarySheet` — a bottom sheet, not a new route, so
              // no matrix fixture or §3.2 row is needed. The sheet renders a
              // drained `CelebrationSummary`, so the single tapped item is
              // wrapped into a one-event summary; `addedAt` is used for both
              // window bounds because a postaláda row IS the whole batch.
              // The item is the already-localized one (see
              // `_localizedRewardInboxItems`), so the sheet's raw
              // `titleKey`/`bodyKey` render as real copy.
              onItemSelected: (RewardInboxItem item) {
                final preferences = ref.read(gamificationPreferencesProvider);
                unawaited(
                  RewardSummarySheet.show<void>(
                    context,
                    summary: CelebrationSummary(
                      events: <RewardEvent>[item.event],
                      totalXp: item.event.earnedXp,
                      startedAt: item.addedAt,
                      endedAt: item.addedAt,
                    ),
                    feedback: gamificationFeedbackFor(preferences),
                    reduceMotion: preferences.reduceMotion,
                  ),
                );
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

/// R18 (audit M6) — the loading frame a route shows while the data it is
/// composed from is still being read.
///
/// MÉRT hiba: three route builders read `AsyncValue.value` directly, so
/// loading AND error both collapsed into the SAME `null`/empty-list value
/// the screens below render as a measured "you have nothing here" state.
/// A spinner is not a richer contract — it is the ABSENCE of the claim.
class _RouteLoadingScaffold extends StatelessWidget {
  const _RouteLoadingScaffold({required this.exitLocation, super.key});

  /// Where the frame's back control goes when there is nothing to pop.
  final String exitLocation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: _RouteFrameBackButton(exitLocation)),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

/// R30 (re-audit #2 B3/3) — the way out of a router-owned frame.
///
/// The two router-owned frames in this file replace a whole screen — while
/// its data is loading, or after that read failed. Neither carried an
/// `AppBar`, so a frame reached with `go` (a redirect target, a deep link)
/// showed a spinner or an error with NO control on it at all: the system
/// back left the app. This one pops when there is a stack and otherwise
/// returns to the shell entry point, so it is never a silent no-op.
class _RouteFrameBackButton extends StatelessWidget {
  const _RouteFrameBackButton(this.exitLocation);

  final String exitLocation;

  @override
  Widget build(BuildContext context) {
    return BackButton(
      key: const Key('route-frame-back'),
      onPressed: () {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
          return;
        }
        GoRouter.maybeOf(context)?.go(exitLocation);
      },
    );
  }
}

/// R18 (audit M6) — the failure frame for the same three routes.
///
/// Shape borrowed from `club_detail_screen.dart`'s `_ClubFeedErrorCard`
/// (icon + message + retry), rebuilt locally rather than imported: that one
/// is a private widget of a Community screen, and the router must not reach
/// into a feature's presentation internals.
class _RouteErrorScaffold extends StatelessWidget {
  const _RouteErrorScaffold({
    required this.onRetry,
    required this.exitLocation,
    super.key,
  });

  final VoidCallback onRetry;

  /// Where the frame's back control goes when there is nothing to pop.
  final String exitLocation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(leading: _RouteFrameBackButton(exitLocation)),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                Text(l10n.shellDataErrorMessage, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  child: Text(l10n.shellDataRetry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
