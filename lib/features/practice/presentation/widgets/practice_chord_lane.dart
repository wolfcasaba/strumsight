import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../chords/public.dart';
import '../../domain/model/compiled_practice_target.dart';
import '../../domain/model/practice_verdict.dart';

/// Renders the current chord + the next chord + the upcoming bar chord,
/// each with a [ChordDiagram]. The hint must NOT linger after the session
/// ends — when [showHint] is false the lane falls back to the localised
/// "no chord" placeholder.
class PracticeChordLane extends StatelessWidget {
  const PracticeChordLane({
    required this.target,
    required this.playhead,
    required this.verdict,
    required this.showHint,
    super.key,
  });

  final CompiledPracticeTarget target;
  final Duration playhead;
  final PracticeVerdict? verdict;
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final segments = target.expectedChordSegments;
    final current = _chordAt(segments, playhead);
    final next = _nextChord(segments, playhead);
    final upcomingBar = _upcomingBar(target, playhead);
    final hintPlaceholder = l10n.practiceChordHintNone;
    final outcome = verdict?.chordOutcome;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.practiceChordLaneLabel,
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _Cell(
                    title: l10n.practiceChordLaneCurrent,
                    chord: showHint ? (current ?? hintPlaceholder) : null,
                    outcome: outcome,
                    placeholder: hintPlaceholder,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Cell(
                    title: l10n.practiceChordLaneNext,
                    chord: showHint ? next : null,
                    placeholder: hintPlaceholder,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Cell(
                    title: l10n.practiceChordLaneUpcomingBar,
                    chord: showHint ? upcomingBar : null,
                    placeholder: hintPlaceholder,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String? _chordAt(List<ExpectedChordSegment> segments, Duration t) {
    for (final segment in segments) {
      if (t >= segment.start && t < segment.end) return segment.chord;
    }
    return null;
  }

  static String? _nextChord(List<ExpectedChordSegment> segments, Duration t) {
    for (final segment in segments) {
      if (segment.start > t) return segment.chord;
    }
    return null;
  }

  /// The chord of the **next** bar — by definition the chord starting at
  /// the first [CompiledPracticeTarget.barBoundaries] entry strictly after
  /// the playhead (the next downbeat). Distinct from [_nextChord], which is
  /// just the first future segment in the timeline and may share the
  /// current bar.
  static String? _upcomingBar(
    CompiledPracticeTarget target,
    Duration playhead,
  ) {
    final boundaries = target.barBoundaries;
    if (boundaries.isEmpty) return null;
    Duration? nextBarStart;
    for (final boundary in boundaries) {
      if (boundary > playhead) {
        nextBarStart = boundary;
        break;
      }
    }
    nextBarStart ??= boundaries.last;
    for (final segment in target.expectedChordSegments) {
      if (segment.start == nextBarStart) return segment.chord;
    }
    return null;
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.title,
    required this.chord,
    required this.placeholder,
    this.outcome,
  });

  final String title;
  final String? chord;
  final String placeholder;
  final ChordOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final style = _outcomeStyle(theme);
    final label = chord == null ? placeholder : chord!;
    final showOutcomeBadge = chord != null && outcome != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        if (chord != null)
          ChordDiagram(label: chord!, size: 56, showLabel: false)
        else
          const SizedBox(height: 56),
        const SizedBox(height: 4),
        if (showOutcomeBadge)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Icon(style.icon, size: 14, color: style.color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    style.label(l10n),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: style.color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: style.color,
            fontWeight: style.bold ? FontWeight.w600 : null,
          ),
        ),
      ],
    );
  }

  _OutcomeStyle _outcomeStyle(ThemeData theme) {
    if (chord == null || outcome == null) {
      return _OutcomeStyle(
        color: theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface,
        icon: Icons.music_note,
        label: (_) => '',
        bold: false,
      );
    }
    return switch (outcome!) {
      ChordOutcome.correct => _OutcomeStyle(
        color: Colors.green,
        icon: Icons.check_circle,
        label: (l10n) => l10n.practiceChordLaneOutcomeCorrect,
        bold: true,
      ),
      ChordOutcome.wrong => _OutcomeStyle(
        color: theme.colorScheme.error,
        icon: Icons.error,
        label: (l10n) => l10n.practiceChordLaneOutcomeWrong,
        bold: true,
      ),
      // Both "non-applicable" outcomes use NEUTRAL colours (no error red,
      // no success green) so the user does not read either as feedback
      // about their playing. They are visually distinct so the screen
      // reader and the eye can tell them apart at a glance.
      ChordOutcome.insufficientData => _OutcomeStyle(
        color: theme.colorScheme.outline,
        icon: Icons.help_outline,
        label: (l10n) => l10n.practiceChordLaneOutcomeInsufficientData,
        bold: false,
      ),
      ChordOutcome.notApplicable => _OutcomeStyle(
        color: theme.colorScheme.onSurfaceVariant,
        icon: Icons.remove_circle_outline,
        label: (l10n) => l10n.practiceChordLaneOutcomeNotApplicable,
        bold: false,
      ),
      ChordOutcome.noDetection => _OutcomeStyle(
        color: theme.colorScheme.outline,
        icon: Icons.hearing_disabled,
        label: (l10n) => l10n.practiceChordLaneOutcomeNoDetection,
        bold: false,
      ),
    };
  }
}

class _OutcomeStyle {
  const _OutcomeStyle({
    required this.color,
    required this.icon,
    required this.label,
    required this.bold,
  });
  final Color color;
  final IconData icon;
  final String Function(AppLocalizations l10n) label;
  final bool bold;
}
