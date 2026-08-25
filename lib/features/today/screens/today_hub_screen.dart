import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/config/app_config.dart';
import '../../../app/routing/app_route.dart';
import '../../../core/design_system/public.dart';
import '../../../l10n/app_localizations.dart';
import '../../progress/public.dart';
import '../../streak/public.dart';
import '../domain/today_plan_snapshot.dart';
import '../providers/today_providers.dart';

/// The Today Hub (UI-05, SDD Ch13 §UI-05) — the daily control center: one
/// clear next action (A1), the plan/streak/goal snapshot, and an offline- or
/// sync-aware banner when the cached plan can't refresh yet (A6, ADR 0277).
///
/// Deliberately resource-free (A4, ADR 0276): this file imports no
/// microphone, camera, or screen-wakelock API — the primary action only
/// *navigates* to Practice; starting a session happens on a Stage screen.
class TodayHubScreen extends ConsumerWidget {
  const TodayHubScreen({super.key, this.now});

  /// Injectable clock for tests; defaults to the real now.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(todayPlanSnapshotProvider);
    final streak = ref.watch(streakProvider);
    final stats = PracticeStats(ref.watch(practiceLogProvider));
    final goalMinutes = ref.watch(dailyGoalProvider);
    final nowDate = now ?? DateTime.now();
    final today = StreakLogic.epochDayOf(nowDate);
    final todaySeconds = ref.watch(dailyGoalActiveSecondsProvider(today));
    final flags = ref.watch(appConfigProvider).flags;

    // A8 — "new user" is derived from REAL zero-state signals only (no
    // session yet, no streak, no plan); never an invented number.
    final isNewUser =
        stats.totalSessions == 0 && streak.current == 0 && !snapshot.hasPlan;

    final hero = _heroContent(l10n, snapshot: snapshot, isNewUser: isNewUser);
    final todayMinutes = todaySeconds ~/ 60;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.todayHubTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            if (snapshot.availability == TodayPlanAvailability.offlineCached)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SsStatusBadge(
                  l10n: l10n,
                  kind: SsStatusBadgeKind.offline,
                ),
              ),
            if (snapshot.availability == TodayPlanAvailability.syncPending)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SsStatusBadge(
                  l10n: l10n,
                  kind: SsStatusBadgeKind.syncPending,
                ),
              ),
            // A1 — the ONLY SsButtonVariant.primary on this screen; every
            // other action below is secondary/tertiary.
            SsCard(
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
                  const SizedBox(height: 16),
                  SsButton(
                    label: hero.ctaLabel,
                    onPressed: () => context.go(AppRoutes.practiceHub),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SsMetricCard(
                    label: l10n.progressStreak,
                    value: streak.current,
                    unit: '',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SsMetricCard(
                    label: l10n.progressDailyGoal,
                    value: todayMinutes,
                    unit: 'min',
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
            SsButton(
              label: l10n.todayHubViewProgressCta,
              variant: SsButtonVariant.secondary,
              onPressed: () => context.go(AppRoutes.profileProgress),
            ),
            const SizedBox(height: 20),
            _VisionCard(
              l10n: l10n,
              visionEnabled: flags.visionEnabled,
              visionSetupEnabled: flags.visionSetupEnabled,
            ),
          ],
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
    return SsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.camera_alt_outlined),
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
            SsButton(
              label: l10n.todayHubVisionCardTitle,
              variant: SsButtonVariant.tertiary,
              onPressed: () => context.go(
                visionSetupEnabled
                    ? AppRoutes.visionSetup
                    : AppRoutes.visionSession,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
