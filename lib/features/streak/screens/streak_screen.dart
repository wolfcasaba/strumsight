import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../live/model/strum.dart';
import '../daily_challenge.dart';
import '../providers/streak_provider.dart';
import '../streak_logic.dart';

/// The practice-streak home: current/longest/freezes, a "keep it alive" nudge,
/// and today's deterministic strum-pattern challenge (RAG chunk 013).
class StreakScreen extends ConsumerWidget {
  const StreakScreen({super.key, this.now});

  /// Injectable clock for tests; defaults to the real now.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final streak = ref.watch(streakProvider);
    final today = StreakLogic.epochDayOf(now ?? DateTime.now());
    final challenge = DailyChallenge.forDay(today);
    final done = StreakLogic.practicedToday(streak, today);
    final atRisk = StreakLogic.atRisk(streak, today);
    final broken = StreakLogic.isBroken(streak, today);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.streakTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            _Hero(count: streak.current, label: l10n.streakDays(streak.current)),
            const SizedBox(height: 16),
            Row(
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
            const SizedBox(height: 16),
            _StatusBanner(
              text: done
                  ? l10n.streakDoneToday
                  : broken
                      ? l10n.streakBroken
                      : atRisk
                          ? l10n.streakAtRisk
                          : l10n.streakStart,
              positive: done,
            ),
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
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.go('/live'),
              icon: const Icon(Icons.play_arrow, size: 20),
              label: Text(l10n.challengeTryInLive),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.count, required this.label});
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return Column(
      children: [
        Icon(
          Icons.local_fire_department,
          size: 72,
          color: active ? AppColors.primary : const Color(0xFF6E7480),
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
      ],
    );
  }
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w800,
                  fontSize: 22)),
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
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
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
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(challenge.name,
              style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w800,
                  fontSize: 20)),
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
