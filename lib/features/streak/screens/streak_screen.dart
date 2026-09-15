import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_route.dart';
import '../../../core/design_system/public.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../learn/public.dart';
import '../../../core/music/strum.dart';
import '../daily_challenge.dart';
import '../../progress/public.dart';
import '../../share/public.dart';
import '../providers/streak_provider.dart';
import '../streak_logic.dart';

/// The practice-streak home: current/longest/freezes, a "keep it alive" nudge,
/// and today's deterministic strum-pattern challenge (RAG chunk 013).
///
/// Ch18 spec §11: the hero flame is an [SsFlame] L that ignites on entry,
/// a 7/30/100-day streak shows a milestone pill under it, and the sections
/// enter staggered (one [SsStaggeredEntrance], six groups → 500 ms, under
/// the celebration cap). The full milestone scene (`SsCelebrationScene`
/// through the coordinator, ADR 0389) is R03's; this screen never plays a
/// scene of its own.
class StreakScreen extends ConsumerWidget {
  const StreakScreen({super.key, this.now});

  /// Injectable clock for tests; defaults to the real now.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final streak = ref.watch(streakProvider);
    final stats = PracticeStats(ref.watch(practiceLogProvider));
    final today = StreakLogic.epochDayOf(now ?? DateTime.now());
    final thisWeek = WeeklyRecap.fromEntries(stats.entries, today: today);
    final lastWeek = WeeklyRecap.fromEntries(stats.entries, today: today - 7);
    final challenge = DailyChallenge.forDay(today);
    final done = StreakLogic.practicedToday(streak, today);
    final atRisk = StreakLogic.atRisk(streak, today);
    final broken = StreakLogic.isBroken(streak, today);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.streakTitle),
        actions: [
          IconButton(
            tooltip: l10n.progressOpen,
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => context.go(AppRoutes.progress),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            SsStaggeredEntrance(
              children: [
                _Hero(
                  count: streak.current,
                  label: l10n.streakDays(streak.current),
                  milestone: SsFlame.milestoneFor(streak.current),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Stat(
                          value: '${streak.longest}',
                          label: l10n.streakLongest,
                          icon: Icons.emoji_events_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Stat(
                          value: '${streak.freezes}',
                          label: l10n.streakFreezes,
                          icon: Icons.ac_unit,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _StatusBanner(
                    text: done
                        ? l10n.streakDoneToday
                        : broken
                        ? l10n.streakBroken
                        : atRisk
                        ? l10n.streakAtRisk
                        : l10n.streakStart,
                    positive: done,
                  ),
                ),
                // Skill reframe (chunk 013 #2 TODO, r152 — Simply's evidence:
                // a growing-skill narrative retains more durably than pure
                // loss-aversion): the flame is what you PROTECT, this is what
                // you BUILT. Hidden until there is any practice to show.
                if (stats.totalSessions > 0)
                  _SkillSection(
                    stats: stats,
                    thisWeek: thisWeek,
                    lastWeek: lastWeek,
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    Text(
                      l10n.challengeTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 1.2,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ChallengeCard(challenge: challenge),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LearnScreen(
                            lesson: Lessons.fromDailyChallenge(challenge),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow, size: 20),
                      label: Text(l10n.challengePlayAlong),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => context.go(AppRoutes.live),
                      child: Text(l10n.challengeTryInLive),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Your skill" — strums played, this week's minutes and the ↓/↑ accuracy
/// trend (chunk 013 #2 skill reframe). One entrance group of the screen.
class _SkillSection extends StatelessWidget {
  const _SkillSection({
    required this.stats,
    required this.thisWeek,
    required this.lastWeek,
  });

  final PracticeStats stats;
  final WeeklyRecap thisWeek;
  final WeeklyRecap lastWeek;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text(
          l10n.streakSkillTitle.toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1.2,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Stat(
                value: '${stats.totalStrokes}',
                label: l10n.streakSkillStrums,
                icon: Icons.music_note_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Stat(
                value: '${thisWeek.minutes} min',
                label: l10n.streakSkillWeekMinutes,
                icon: Icons.timer_outlined,
              ),
            ),
            if (thisWeek.averageAccuracy != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: _Stat(
                  value: _accuracyTrend(thisWeek, lastWeek),
                  label: l10n.streakSkillAccuracy,
                  icon: Icons.trending_up,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.streakSkillGrowing,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

/// "87% ▲" when both weeks scored runs; plain "87%" for the first week.
String _accuracyTrend(WeeklyRecap thisWeek, WeeklyRecap lastWeek) {
  final cur = thisWeek.averageAccuracy!;
  final prev = lastWeek.averageAccuracy;
  final pct = '${(cur * 100).round()}%';
  if (prev == null) return pct;
  final d = cur - prev;
  if (d.abs() < 0.005) return pct;
  return d > 0 ? '$pct ▲' : '$pct ▼';
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.count,
    required this.label,
    required this.milestone,
  });
  final int count;
  final String label;

  /// The milestone [count] sits on (7/30/100), or null.
  final int? milestone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active = count > 0;
    return Column(
      children: [
        SsFlame(
          lit: active,
          color: AppColors.primary,
          size: SsFlameSize.large,
          igniteOnMount: true,
          ignition: count,
        ),
        const SizedBox(height: 4),
        Text(
          '$count',
          style: TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w800,
            fontSize: 48,
            color: active ? AppColors.primary : const Color(0xFF6E7480),
          ),
        ),
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        if (milestone != null) ...[
          const SizedBox(height: 8),
          _MilestonePill(
            key: const Key('streak-milestone-pill'),
            text: l10n.streakMilestone(milestone!),
          ),
        ],
      ],
    );
  }
}

/// The 7/30/100-day marker (spec §11.3) — a copper pill under the count.
/// Static: the hero flame's ignite is the motion of this moment.
class _MilestonePill extends StatelessWidget {
  const _MilestonePill({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontFamily: 'Montserrat',
        fontWeight: FontWeight.w800,
        fontSize: 13,
        color: AppColors.primary,
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.icon});
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.text, required this.positive});
  final String text;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = positive ? AppColors.confidenceHigh : AppColors.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({required this.challenge});
  final DailyChallenge challenge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            challenge.name,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in challenge.pattern)
                Icon(
                  d == StrumDirection.down
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                  size: 30,
                  color: d == StrumDirection.down
                      ? AppColors.primary
                      : AppColors.confidenceHigh,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
