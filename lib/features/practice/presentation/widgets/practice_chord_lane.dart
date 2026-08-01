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

  String? _upcomingBar(CompiledPracticeTarget target, Duration playhead) {
    final playheadBar = _barIndexAt(target, playhead);
    if (playheadBar == null) return null;
    for (final segment in target.expectedChordSegments) {
      if (segment.start > playhead) return segment.chord;
    }
    return null;
  }

  static int? _barIndexAt(CompiledPracticeTarget target, Duration t) {
    final boundaries = target.barBoundaries;
    for (var i = 0; i < boundaries.length; i++) {
      if (t < boundaries[i]) return i;
    }
    return boundaries.length;
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
    final color = _outcomeColor(theme);
    final label = chord == null ? placeholder : chord!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        if (chord != null)
          ChordDiagram(label: chord!, size: 64, showLabel: false)
        else
          const SizedBox(height: 64),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: color)),
      ],
    );
  }

  Color _outcomeColor(ThemeData theme) {
    if (chord == null) return theme.colorScheme.outline;
    return switch (outcome) {
      ChordOutcome.correct => Colors.green,
      ChordOutcome.wrong => theme.colorScheme.error,
      ChordOutcome.insufficientData => theme.colorScheme.outline,
      ChordOutcome.notApplicable => theme.colorScheme.outline,
      ChordOutcome.noDetection => theme.colorScheme.outline,
      null => theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface,
    };
  }
}
