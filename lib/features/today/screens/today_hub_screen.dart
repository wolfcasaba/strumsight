import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/config/app_config.dart';
import '../../../app/routing/app_route.dart';
import '../../../core/design_system/public.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../curriculum/public.dart' show curriculumMissionName;
import '../../progress/public.dart';
import '../../streak/public.dart';
import '../../strum_challenge/public.dart' show strumChallengeBestProvider;
import '../domain/today_plan_snapshot.dart';
import '../providers/today_providers.dart';

/// The Today Hub (UI-05, SDD Ch13 §UI-05) — the daily control center: one
/// clear next action (A1), the plan/streak/goal snapshot, and an offline- or
/// sync-aware banner when the cached plan can't refresh yet (A6, ADR 0277).
///
/// Deliberately resource-free (A4, ADR 0276): this file imports no
/// microphone, camera, or screen-wakelock API — the primary action only
/// *navigates* to Practice; starting a session happens on a Stage screen.
///
/// Styled with plain Material widgets + [AppColors] (the same convention
/// `ProgressScreen`/`SettingsScreen` use) rather than the `core/design_system`
/// component library: those widgets require `SsDarkTheme`/`SsLightTheme` to
/// be the app's active `ThemeData`, which the running app does not yet wire
/// up (`StrumSightApp` still applies `AppTheme`) — using them here would
/// crash on first frame. The two design-system pieces used below
/// ([SsStaggeredEntrance], [SsScoreRingReveal]) are theme-agnostic by
/// contract (they read no theme extension), so they are safe here.
class TodayHubScreen extends ConsumerWidget {
  const TodayHubScreen({super.key, this.now});

  /// Injectable clock for tests; defaults to the real now.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(todayPlanSnapshotProvider);
    final streak = ref.watch(streakProvider);
    final stats = ref.watch(practiceStatsProvider);
    final goalMinutes = ref.watch(dailyGoalProvider);
    final nowDate = now ?? DateTime.now();
    final today = StreakLogic.epochDayOf(nowDate);
    final todaySeconds = ref.watch(dailyGoalActiveSecondsProvider(today));
    final flags = ref.watch(appConfigProvider).flags;

    // A8 — "new user" is derived from REAL zero-state signals only, never an
    // invented number.
    //
    // `!snapshot.hasPlan` was one of those signals and is no longer a signal at
    // all: the plan now comes from the SHIPPED course, so everyone has one from
    // their first launch. Keeping it in the conjunction would have made the
    // zero-state greeting unreachable — the hub would have told someone who has
    // never played to "continue".
    //
    // What still says "new": the learner's own history, plus whether the PLAN shows
    // prior activity. Work already counted today is history; so is a plan that
    // arrived from a sync, which can only exist once something was set up. A plan
    // that is merely present is not.
    final planShowsHistory =
        snapshot.completedTaskCount > 0 ||
        snapshot.availability == TodayPlanAvailability.offlineCached ||
        snapshot.availability == TodayPlanAvailability.syncPending;
    final isNewUser =
        stats.totalSessions == 0 && streak.current == 0 && !planShowsHistory;

    final hero = _heroContent(l10n, snapshot: snapshot, isNewUser: isNewUser);
    // The primary button continues THAT rung when the plan names one. A button
    // labelled "continue" that goes somewhere else is the hub lying about what it
    // just offered.
    final primaryDestination = snapshot.recommendedMissionId == null
        ? AppRoutes.practiceHub
        : AppRoutes.curriculumLadder;
    final todayMinutes = todaySeconds ~/ 60;
    // The daily-goal ring (Ch18 spec §1): fills to today's minutes over the
    // goal; a zero goal is an explicit "not applicable", never a fake 0 %.
    final goalRing = SsScoreRingReveal(
      state: goalMinutes > 0
          ? SsScoreRingState.measured
          : SsScoreRingState.notApplicable,
      ratio: goalMinutes > 0 ? todayMinutes / goalMinutes : null,
      size: 56,
      semanticLabel: l10n.progressGoalProgress(todayMinutes, goalMinutes),
    );

    // Ch18 spec §1: the cards enter one after another (fade + short rise),
    // one finite gesture under half a second; reduced motion shows all at once.
    final sections = <Widget>[
      if (snapshot.availability == TodayPlanAvailability.offlineCached)
        _StatusBanner(
          icon: Icons.cloud_off_outlined,
          label: l10n.dsStatusBadgeOffline,
        ),
      if (snapshot.availability == TodayPlanAvailability.syncPending)
        _StatusBanner(
          icon: Icons.sync_outlined,
          label: l10n.dsStatusBadgeSyncPending,
        ),
      // A1 — the ONLY primary (filled) button on this screen; every
      // other action below is outlined/text-styled.
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  goalRing,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hero.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          hero.message,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('today-hub-primary-cta'),
                onPressed: () => context.go(primaryDestination),
                child: Text(hero.ctaLabel),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: _Metric(
              label: l10n.progressStreak,
              value: '${streak.current}',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Metric(
              label: l10n.progressDailyGoal,
              value: l10n.progressGoalOption(todayMinutes),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        l10n.progressGoalProgress(todayMinutes, goalMinutes),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 20),
      OutlinedButton(
        onPressed: () => context.push(AppRoutes.profileProgress),
        child: Text(l10n.todayHubViewProgressCta),
      ),
      const SizedBox(height: 20),
      // E18-R23 — a 60 másodperces pengetés-kihívás belépője és az
      // „Alapból privát" ígéret kártyája (a kutatás 2. és 5. ajánlása).
      const _StrumChallengeCard(),
      const SizedBox(height: 20),
      const _PrivacyPromiseCard(),
      // A card whose only content is "not available in this build" is
      // an advertisement for a feature the learner cannot use — it is
      // not rendered at all while the Vision capability is off. The
      // disabled-reason copy stays on the card for the flag-on-but-
      // setup-off case (A7).
      if (flags.visionEnabled) ...[
        const SizedBox(height: 20),
        _VisionCard(
          l10n: l10n,
          visionEnabled: flags.visionEnabled,
          visionSetupEnabled: flags.visionSetupEnabled,
        ),
      ],
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.todayHubTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [SsStaggeredEntrance(children: sections)],
        ),
      ),
    );
  }

  _HeroContent _heroContent(
    AppLocalizations l10n, {
    required TodayPlanSnapshot snapshot,
    required bool isNewUser,
  }) {
    if (isNewUser) {
      return _HeroContent(
        title: l10n.todayHubNewUserTitle,
        message: l10n.todayHubNewUserMessage,
        ctaLabel: l10n.todayHubStartFirstPracticeCta,
      );
    }
    if (snapshot.isDayCompleted) {
      // §5.2 — a completed day shows a recap, not guilt: the primary
      // action stays present, just re-labelled toward "more", not "start".
      return _HeroContent(
        title: l10n.todayHubDayCompletedTitle,
        message: l10n.todayHubDayCompletedMessage,
        ctaLabel: l10n.todayHubPracticeMoreCta,
      );
    }
    final missionId = snapshot.recommendedMissionId;
    if (missionId != null) {
      // The rung's NAME, resolved here because this is where the localisations
      // are: the projection deliberately carries the id, so a plan source can
      // never put untranslated prose in front of a learner.
      return _HeroContent(
        title: l10n.todayHubTitle,
        message: l10n.todayHubNextStep(curriculumMissionName(l10n, missionId)),
        ctaLabel: l10n.todayHubContinueCta,
      );
    }
    if (snapshot.hasPlan) {
      return _HeroContent(
        title: l10n.todayHubTitle,
        message: snapshot.recommendedTaskLabel ?? l10n.todayHubNoPlanMessage,
        ctaLabel: l10n.todayHubContinueCta,
      );
    }
    return _HeroContent(
      title: l10n.todayHubTitle,
      message: l10n.todayHubNoPlanMessage,
      ctaLabel: l10n.todayHubStartPracticeCta,
    );
  }
}

final class _HeroContent {
  const _HeroContent({
    required this.title,
    required this.message,
    required this.ctaLabel,
  });

  final String title;
  final String message;
  final String ctaLabel;
}

/// ADR 0277 §2 — offline is not error-styled: a small inline banner, the
/// rest of the (cached) content stays fully visible beneath it.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).hintColor),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// The daily 60-second strum challenge (2026-09-15): the pattern, today's best
/// (or that there is none yet) and a Start that only NAVIGATES (A4) — the
/// microphone is acquired on the Stage route it opens, never here. Outlined,
/// not filled: the hero above keeps the screen's single primary action (A1).
class _StrumChallengeCard extends ConsumerWidget {
  const _StrumChallengeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final best = ref.watch(strumChallengeBestProvider);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timer_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.strumChallengeTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.strumChallengeCardBody,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              best == null
                  ? l10n.strumChallengeNoAttemptYet
                  : l10n.strumChallengeBestToday(best.bestScore),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const ValueKey('today-hub-strum-challenge-cta'),
              onPressed: () => context.go(AppRoutes.strumChallenge),
              child: Text(l10n.strumChallengeStart),
            ),
          ],
        ),
      ),
    );
  }
}

/// The privacy promise (2026-09-15): four plain facts a guitarist can check
/// against the app — no account, offline, no ads/subscription, audio stays
/// on the phone. Deliberately quiet (secondary text, no button): it informs,
/// it does not sell. Every line is a `Row` with a `Flexible` text so the
/// card wraps instead of overflowing at large text scales.
class _PrivacyPromiseCard extends StatelessWidget {
  const _PrivacyPromiseCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lines = [
      l10n.todayHubPrivacyNoAccount,
      l10n.todayHubPrivacyOffline,
      l10n.todayHubPrivacyNoAds,
      l10n.todayHubPrivacyAudioLocal,
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.todayHubPrivacyTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check,
                      size: 16,
                      color: Theme.of(context).hintColor,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        line,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A7 — the disabled state names the reason instead of vanishing or being an
/// unexplained dead tap target (§5.6). Never starts the camera itself (A4):
/// enabled taps only *navigate* to the Vision setup/session route.
class _VisionCard extends StatelessWidget {
  const _VisionCard({
    required this.l10n,
    required this.visionEnabled,
    required this.visionSetupEnabled,
  });

  final AppLocalizations l10n;
  final bool visionEnabled;
  final bool visionSetupEnabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.camera_alt_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.todayHubVisionCardTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              visionEnabled
                  ? l10n.todayHubVisionCardMessage
                  : l10n.todayHubVisionUnavailableReason,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (visionEnabled) ...[
              const SizedBox(height: 12),
              TextButton(
                // `push`, not `go`: the Vision screens carry no back
                // affordance of their own, so replacing the stack would
                // strand the user there (anti-vacuum, L403).
                onPressed: () => context.push(
                  visionSetupEnabled
                      ? AppRoutes.visionSetup
                      : AppRoutes.visionSession,
                ),
                child: Text(l10n.todayHubVisionCardTitle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
