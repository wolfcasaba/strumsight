import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/config/app_config.dart';
import '../../../app/routing/app_route.dart';
import '../../../core/theme/app_colors.dart';
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
///
/// Styled with plain Material widgets + [AppColors] (the same convention
/// `ProgressScreen`/`SettingsScreen` use) rather than the `core/design_system`
/// component library: those widgets require `SsDarkTheme`/`SsLightTheme` to
/// be the app's active `ThemeData`, which the running app does not yet wire
/// up (`StrumSightApp` still applies `AppTheme`) — using them here would
/// crash on first frame.
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
                    FilledButton(
                      key: const ValueKey('today-hub-primary-cta'),
                      onPressed: () => context.go(AppRoutes.practiceHub),
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
                    value: '$todayMinutes min',
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
              onPressed: () => context.go(AppRoutes.profileProgress),
              child: Text(l10n.todayHubViewProgressCta),
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
                onPressed: () => context.go(
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
