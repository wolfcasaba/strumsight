import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../streak/daily_challenge.dart';
import '../../streak/streak_logic.dart';
import '../providers/lesson_progress_provider.dart';
import '../model/lesson.dart';
import 'learn_screen.dart';

/// The "learn" home: today's challenge as a playable lesson, then the built-in
/// curriculum grouped by difficulty, each tier gated by progress (pass a lesson
/// to unlock the next). Stars reflect your best accuracy (RAG chunk 014).
class LessonListScreen extends ConsumerWidget {
  const LessonListScreen({super.key, this.now});

  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final today = StreakLogic.epochDayOf(now ?? DateTime.now());
    final daily = Lessons.fromDailyChallenge(DailyChallenge.forDay(today));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.learnTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _label(l10n.learnTodaysChallenge),
            _LessonTile(lesson: daily, unlocked: true, stars: 0),
            for (final tier in Difficulty.values) ...[
              const SizedBox(height: 18),
              _label(_tierName(l10n, tier)),
              for (final lesson in Lessons.byDifficulty(tier))
                _LessonTile(
                  lesson: lesson,
                  unlocked: ref
                      .watch(lessonProgressProvider.notifier)
                      .isUnlocked(lesson),
                  stars: ref.watch(lessonProgressProvider.notifier)
                      .stars(lesson.id),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static String _tierName(AppLocalizations l10n, Difficulty d) => switch (d) {
        Difficulty.beginner => l10n.learnBeginner,
        Difficulty.intermediate => l10n.learnIntermediate,
        Difficulty.advanced => l10n.learnAdvanced,
      };

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1.2,
            color: AppColors.primary,
          ),
        ),
      );
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({
    required this.lesson,
    required this.unlocked,
    required this.stars,
  });

  final Lesson lesson;
  final bool unlocked;
  final int stars;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chords = lesson.chordSequence.join(' · ');
    final subtitle = [
      if (chords.isNotEmpty) chords,
      '${lesson.bpm.round()} BPM',
      '${lesson.events.length} ${l10n.learnStrokes}',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        enabled: unlocked,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: (unlocked ? AppColors.primary : AppColors.confidenceLow)
              .withValues(alpha: 0.15),
          child: Icon(unlocked ? Icons.play_arrow : Icons.lock,
              color: unlocked ? AppColors.primary : AppColors.confidenceLow),
        ),
        title: Text(lesson.name,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontFamily: 'Montserrat')),
        subtitle: Text(subtitle),
        trailing: unlocked && stars > 0 ? _Stars(stars: stars) : null,
        onTap: unlocked
            ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LearnScreen(lesson: lesson),
                  ),
                )
            : () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.learnLocked)),
                ),
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.stars});
  final int stars;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Icon(
              i < stars ? Icons.star : Icons.star_border,
              size: 18,
              color: AppColors.secondary,
            ),
        ],
      );
}
