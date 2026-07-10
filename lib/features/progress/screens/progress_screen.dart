import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../streak/providers/streak_provider.dart';
import '../../streak/streak_logic.dart';
import '../model/practice_entry.dart';
import '../model/practice_stats.dart';
import '../providers/daily_goal_provider.dart';
import '../providers/practice_log_provider.dart';
import '../widgets/weekly_bars.dart';

/// The Progress dashboard — a Yousician/Simply-Guitar-style practice tracker, but
/// with the metric no competitor has: your **strum-direction accuracy** over time.
/// Everything is derived from the on-device practice log (no account needed).
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key, this.now});

  /// Injectable clock for tests; defaults to the real now.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final stats = PracticeStats(ref.watch(practiceLogProvider));
    final streak = ref.watch(streakProvider);
    final today = StreakLogic.epochDayOf(now ?? DateTime.now());

    return Scaffold(
      appBar: AppBar(title: Text(l10n.progressTitle)),
      body: SafeArea(
        child: stats.totalSessions == 0
            ? _Empty(text: l10n.progressEmpty)
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  _TotalHero(seconds: stats.totalSeconds, l10n: l10n),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _Stat(
                          value: '${stats.daysPracticed}',
                          label: l10n.progressDaysPracticed,
                          icon: Icons.calendar_today_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Stat(
                          value: '${stats.totalSessions}',
                          label: l10n.progressSessions,
                          icon: Icons.play_circle_outline,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Stat(
                          value: '${streak.current}',
                          label: l10n.progressStreak,
                          icon: Icons.local_fire_department,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _DailyGoalCard(
                    todaySeconds: stats.secondsForDay(today),
                    goalMinutes: ref.watch(dailyGoalProvider),
                    l10n: l10n,
                    onEdit: () => _editGoal(context, ref, l10n),
                  ),
                  const SizedBox(height: 26),
                  _SectionLabel(l10n.progressThisWeek),
                  const SizedBox(height: 12),
                  WeeklyBars(days: stats.lastDays(today)),
                  const SizedBox(height: 26),
                  _StrumAccuracyCard(stats: stats, l10n: l10n),
                  const SizedBox(height: 26),
                  _SectionLabel(l10n.progressBySource),
                  const SizedBox(height: 12),
                  _SourceBreakdown(stats: stats, l10n: l10n),
                ],
              ),
      ),
    );
  }
}

class _TotalHero extends StatelessWidget {
  const _TotalHero({required this.seconds, required this.l10n});
  final int seconds;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          formatPractice(seconds, l10n),
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w800,
            fontSize: 44,
            color: AppColors.primary,
          ),
        ),
        Text(l10n.progressTotalPractice,
            style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

/// Pick a new daily goal from a preset sheet.
Future<void> _editGoal(
    BuildContext context, WidgetRef ref, AppLocalizations l10n) async {
  final current = ref.read(dailyGoalProvider);
  final picked = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.progressSetGoal,
                style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w800,
                    fontSize: 18)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final m in DailyGoalController.presets)
                  ChoiceChip(
                    label: Text(l10n.progressGoalOption(m)),
                    selected: m == current,
                    onSelected: (_) => Navigator.of(context).pop(m),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (picked != null) {
    await ref.read(dailyGoalProvider.notifier).setGoal(picked);
  }
}

/// Compact practice-time label: "1h 20m" / "20m" / "45s" via localized keys.
String formatPractice(int seconds, AppLocalizations l10n) {
  if (seconds < 60) return l10n.progressSeconds(seconds);
  final totalMin = seconds ~/ 60;
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  if (h > 0) return l10n.progressHoursMinutes(h, m);
  return l10n.progressMinutes(m);
}

class _DailyGoalCard extends StatelessWidget {
  const _DailyGoalCard({
    required this.todaySeconds,
    required this.goalMinutes,
    required this.l10n,
    required this.onEdit,
  });

  final int todaySeconds;
  final int goalMinutes;
  final AppLocalizations l10n;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final goalSeconds = goalMinutes * 60;
    final todayMin = todaySeconds ~/ 60;
    final progress =
        goalSeconds <= 0 ? 0.0 : (todaySeconds / goalSeconds).clamp(0.0, 1.0);
    final met = todaySeconds >= goalSeconds;
    final remaining = ((goalSeconds - todaySeconds) / 60).ceil();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: (met ? AppColors.confidenceHigh : AppColors.primary)
                .withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 5,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation(
                        met ? AppColors.confidenceHigh : AppColors.primary),
                  ),
                ),
                Icon(met ? Icons.check : Icons.bolt,
                    size: 20,
                    color: met ? AppColors.confidenceHigh : AppColors.primary),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.progressDailyGoal,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(l10n.progressGoalProgress(todayMin, goalMinutes),
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(
                  met
                      ? l10n.progressGoalMet
                      : l10n.progressGoalRemaining(remaining),
                  style: TextStyle(
                    color: met ? AppColors.confidenceHigh : AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: l10n.progressSetGoal,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

class _StrumAccuracyCard extends StatelessWidget {
  const _StrumAccuracyCard({required this.stats, required this.l10n});
  final PracticeStats stats;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final avg = stats.averageDirectionAccuracy;
    final best = stats.bestDirectionAccuracy;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.16),
            AppColors.confidenceHigh.withValues(alpha: 0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_vert, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.progressStrumAccuracyTitle,
                    style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(l10n.progressStrumAccuracyHint,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          if (avg == null)
            Text(l10n.progressNoScores,
                style: TextStyle(
                    color: Theme.of(context).hintColor,
                    fontStyle: FontStyle.italic))
          else
            Row(
              children: [
                Expanded(
                  child: _AccStat(
                    percent: avg,
                    label: l10n.progressAverage,
                  ),
                ),
                Expanded(
                  child: _AccStat(
                    percent: best ?? avg,
                    label: l10n.progressBest,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AccStat extends StatelessWidget {
  const _AccStat({required this.percent, required this.label});
  final double percent; // 0..1
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '${(percent * 100).round()}%',
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w800,
            fontSize: 30,
            color: AppColors.confidenceHigh,
          ),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _SourceBreakdown extends StatelessWidget {
  const _SourceBreakdown({required this.stats, required this.l10n});
  final PracticeStats stats;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, IconData, int)>[
      (l10n.navLive, Icons.graphic_eq, stats.sessionsFrom(PracticeSource.live)),
      (l10n.navLearn, Icons.school_outlined,
          stats.sessionsFrom(PracticeSource.learn)),
      (l10n.navAnalyze, Icons.multitrack_audio,
          stats.sessionsFrom(PracticeSource.analyze)),
    ];
    return Column(
      children: [
        for (final (label, icon, count) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(label)),
                Text('$count',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 12,
        letterSpacing: 1.2,
        color: AppColors.primary,
      ),
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
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
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
          Text(label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_outlined,
                size: 56, color: AppColors.primary.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
