import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../streak/daily_challenge.dart';
import '../../streak/streak_logic.dart';
import '../model/lesson.dart';
import 'learn_screen.dart';

/// The "learn" home: today's challenge as a playable lesson + the built-in
/// starter lessons. Tapping opens the play-along [LearnScreen].
class LessonListScreen extends StatelessWidget {
  const LessonListScreen({super.key, this.now});

  /// Injectable clock for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final today = StreakLogic.epochDayOf(now ?? DateTime.now());
    final daily = Lessons.fromDailyChallenge(DailyChallenge.forDay(today));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.learnTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _sectionLabel(l10n.learnTodaysChallenge),
            _LessonTile(lesson: daily, highlight: true),
            const SizedBox(height: 20),
            _sectionLabel(l10n.learnLessons),
            for (final lesson in Lessons.all)
              _LessonTile(lesson: lesson),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
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
  const _LessonTile({required this.lesson, this.highlight = false});

  final Lesson lesson;
  final bool highlight;

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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: highlight
            ? const BorderSide(color: AppColors.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
          child: const Icon(Icons.play_arrow, color: AppColors.primary),
        ),
        title: Text(lesson.name,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontFamily: 'Montserrat')),
        subtitle: Text(subtitle),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LearnScreen(lesson: lesson),
          ),
        ),
      ),
    );
  }
}
