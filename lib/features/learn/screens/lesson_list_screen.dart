import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/config/app_config.dart';
import '../../../app/routing/app_route.dart';
import '../../../core/design_system/public.dart';
import '../../../l10n/app_localizations.dart';
import '../../streak/public.dart';
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final today = StreakLogic.epochDayOf(now ?? DateTime.now());
    final daily = Lessons.fromDailyChallenge(DailyChallenge.forDay(today));
    final flags = ref.watch(appConfigProvider).flags;
    // Watch the STATE (not just the notifier) so a pass recorded behind a
    // pushed route re-renders the unlock states and the Continue card.
    ref.watch(lessonProgressProvider);
    final progress = ref.watch(lessonProgressProvider.notifier);
    final continueLesson = progress.recommendedNext();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.learnTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.library_music_outlined),
            tooltip: l10n.songsTitle,
            onPressed: () => context.push(AppRoutes.songs),
          ),
          IconButton(
            icon: const Icon(Icons.grid_view),
            tooltip: l10n.chordLibraryTitle,
            onPressed: () => context.push(AppRoutes.chords),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (flags.practiceEngineV2Enabled) ...[
              _V2EntryCard(
                key: const Key('learn-entry-practice-hub'),
                icon: Icons.play_circle_outline,
                title: l10n.practiceHubTitle,
                onTap: () => context.push(AppRoutes.practiceHub),
              ),
              const SizedBox(height: 12),
            ],
            if (flags.songTrainerV2Enabled) ...[
              _V2EntryCard(
                key: const Key('learn-entry-song-trainer'),
                icon: Icons.library_music_outlined,
                title: l10n.songTrainerTitle,
                onTap: () => context.push(AppRoutes.songTrainerLibrary),
              ),
              const SizedBox(height: 12),
            ],
            // Where to pick up (round 93): the first unlocked, not-yet-passed
            // lesson, one tap away. Hidden once the whole curriculum is passed.
            if (continueLesson != null) ...[
              _ContinueCard(lesson: continueLesson),
              const SizedBox(height: 18),
            ],
            _label(colors, l10n.learnTodaysChallenge),
            _LessonTile(lesson: daily, unlocked: true, stars: 0),
            for (final tier in Difficulty.values) ...[
              const SizedBox(height: 18),
              _label(colors, _tierName(l10n, tier)),
              ..._tierTiles(tier, progress),
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

  /// Tiles for one tier, each carrying the PREVIOUS lesson in the tier so a
  /// locked tile can always name what unlocks it (ADR 0282 §3/A3) — never a
  /// bare "locked" dead end.
  List<Widget> _tierTiles(Difficulty tier, LessonProgressController progress) {
    final lessons = Lessons.byDifficulty(tier);
    return [
      for (var i = 0; i < lessons.length; i++)
        _LessonTile(
          lesson: lessons[i],
          unlocked: progress.isUnlocked(lessons[i]),
          stars: progress.stars(lessons[i].id),
          unlockedBy: i > 0 ? lessons[i - 1] : null,
        ),
    ];
  }

  Widget _label(SsColorScheme colors, String text) => Padding(
    padding: const EdgeInsets.only(
      left: SsSpacing.space1,
      bottom: SsSpacing.space2,
      top: SsSpacing.space1,
    ),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 12,
        letterSpacing: 1.2,
        color: colors.brand,
      ),
    ),
  );
}

class _V2EntryCard extends StatelessWidget {
  const _V2EntryCard({
    required super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Card(
      color: colors.surface,
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SsSpacing.space4,
          vertical: SsSpacing.space2,
        ),
        leading: CircleAvatar(
          backgroundColor: colors.brand.withValues(alpha: 0.14),
          child: Icon(icon, color: colors.brand),
        ),
        title: Text(title, style: typography.titleMedium),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// The hero "pick up where you left off" card — filled with the brand colour
/// so it reads as THE action on the screen.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Card(
      color: colors.brand.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SsRadius.sm),
        side: BorderSide(color: colors.brand.withValues(alpha: 0.5)),
      ),
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SsSpacing.space4,
          vertical: SsSpacing.space2,
        ),
        leading: CircleAvatar(
          backgroundColor: colors.brand,
          child: Icon(Icons.play_arrow, color: colors.onBrand),
        ),
        title: Text(
          l10n.learnContinue,
          style: typography.labelLarge.copyWith(color: colors.brand),
        ),
        subtitle: Text(
          lesson.name,
          style: typography.titleMedium.copyWith(color: colors.textPrimary),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => LearnScreen(lesson: lesson)),
        ),
      ),
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({
    required this.lesson,
    required this.unlocked,
    required this.stars,
    this.unlockedBy,
  });

  final Lesson lesson;
  final bool unlocked;
  final int stars;

  /// The lesson that must be passed to unlock this one (null for the first
  /// lesson of a tier — always unlocked). Names the lock's reason instead of
  /// a bare "locked" dead end (ADR 0282 §3).
  final Lesson? unlockedBy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final chords = lesson.chordSequence.join(' · ');
    final subtitle = (!unlocked && unlockedBy != null)
        ? l10n.learnLockedReason(unlockedBy!.name)
        : [
            if (chords.isNotEmpty) chords,
            '${lesson.bpm.round()} BPM',
            '${lesson.events.length} ${l10n.learnStrokes}',
          ].join(' · ');
    return Card(
      key: ValueKey('lesson-tile-${lesson.id}'),
      color: colors.surface,
      margin: const EdgeInsets.only(bottom: SsSpacing.space3),
      child: ListTile(
        enabled: unlocked,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SsSpacing.space4,
          vertical: SsSpacing.space2,
        ),
        leading: CircleAvatar(
          backgroundColor: (unlocked ? colors.brand : colors.confidenceLow)
              .withValues(alpha: 0.15),
          child: Icon(
            unlocked ? Icons.play_arrow : Icons.lock,
            color: unlocked ? colors.brand : colors.confidenceLow,
          ),
        ),
        title: Text(lesson.name, style: typography.titleMedium),
        subtitle: Text(
          subtitle,
          style: typography.bodyMedium.copyWith(color: colors.textSecondary),
        ),
        trailing: unlocked && stars > 0 ? _Stars(stars: stars) : null,
        // `enabled: false` already disables the tap gesture entirely — the
        // lock reason is stated in [subtitle] instead, ALWAYS visible rather
        // than hidden behind a tap that a disabled tile can never receive
        // (ADR 0282 §3).
        onTap: unlocked
            ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LearnScreen(lesson: lesson),
                ),
              )
            : null,
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.stars});
  final int stars;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Icon(
            i < stars ? Icons.star : Icons.star_border,
            size: 18,
            color: colors.info,
          ),
      ],
    );
  }
}
