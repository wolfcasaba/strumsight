import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../chords/public.dart';
import '../../domain/model/chord_pair_stats.dart';
import '../../domain/model/compiled_practice_target.dart';
import '../widgets/chord_change_breakdown.dart';

/// Mode view for chord-change practice.
class ChordChangeView extends StatelessWidget {
  const ChordChangeView({
    required this.target,
    required this.playhead,
    required this.width,
    this.latestChange,
    this.analysis,
    this.showChordHint = true,
    this.onCurrentChordTap,
    this.onNextChordTap,
    super.key,
  });

  final CompiledPracticeTarget target;
  final Duration playhead;
  final double width;
  final ChordChangeMeasurement? latestChange;
  final ChordChangeAnalysis? analysis;
  final bool showChordHint;
  final VoidCallback? onCurrentChordTap;
  final VoidCallback? onNextChordTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentChord = showChordHint ? _currentChord(target, playhead) : null;
    final nextChord = showChordHint ? _nextChord(target, playhead) : null;
    final stats = analysis?.pairStats ?? const <ChordPairStats>[];
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _ChordCard(
                  title: l10n.practiceChordChangeCurrent,
                  chord: currentChord,
                  hintPlaceholder: l10n.practiceChordHintNone,
                  semanticsPrefix: l10n.practiceChordChangeCurrent,
                  onTap: onCurrentChordTap,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ChordCard(
                  title: l10n.practiceChordChangeNext,
                  chord: nextChord,
                  hintPlaceholder: l10n.practiceChordHintNone,
                  semanticsPrefix: l10n.practiceChordChangeNext,
                  onTap: onNextChordTap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ChangeFeedback(change: latestChange),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 12),
            ChordChangeBreakdown(
              pairStats: stats,
              slowestPair: analysis?.slowestPair,
            ),
          ],
        ],
      ),
    );
  }
}

class _ChordCard extends StatelessWidget {
  const _ChordCard({
    required this.title,
    required this.chord,
    required this.hintPlaceholder,
    required this.semanticsPrefix,
    this.onTap,
  });

  final String title;
  final String? chord;
  final String hintPlaceholder;
  final String semanticsPrefix;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final displayed = chord ?? hintPlaceholder;
    return Semantics(
      container: true,
      button: onTap != null,
      label: '$semanticsPrefix: $displayed',
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              if (chord != null)
                ChordDiagram(label: chord!, size: 72, showLabel: false)
              else
                const SizedBox(height: 75),
              const SizedBox(height: 4),
              Text(
                displayed,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangeFeedback extends StatelessWidget {
  const _ChangeFeedback({this.change});

  final ChordChangeMeasurement? change;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final change = this.change;
    final style = _style(theme, change?.outcome);
    final label = change == null
        ? l10n.practiceChordChangeWaiting
        : _outcomeLabel(l10n, change.outcome);
    return Semantics(
      container: true,
      label: label,
      child: Card(
        color: style.color,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(style.icon, color: style.foreground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: style.foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (change?.recognizedChangeDelay != null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.practiceChordChangeDelay(
                    change!.recognizedChangeDelay!.inMilliseconds,
                  ),
                  style: TextStyle(color: style.foreground),
                ),
              ],
              if (change?.stableDuration != null) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.practiceChordChangeStability(
                    change!.stableDuration!.inMilliseconds,
                  ),
                  style: TextStyle(color: style.foreground),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _outcomeLabel(AppLocalizations l10n, ChordChangeOutcome outcome) =>
    switch (outcome) {
      ChordChangeOutcome.correct => l10n.practiceChordChangeCorrect,
      ChordChangeOutcome.wrongChord => l10n.practiceChordChangeWrongChord,
      ChordChangeOutcome.noDetection => l10n.practiceChordChangeNoDetection,
      ChordChangeOutcome.unstable => l10n.practiceChordChangeUnstable,
      ChordChangeOutcome.insufficientSignal =>
        l10n.practiceChordChangeInsufficientSignal,
    };

_ChangeStyle _style(ThemeData theme, ChordChangeOutcome? outcome) =>
    switch (outcome) {
      null => _ChangeStyle(
        color: theme.colorScheme.surfaceContainerHighest,
        foreground: theme.colorScheme.onSurfaceVariant,
        icon: Icons.hourglass_empty,
      ),
      ChordChangeOutcome.correct => const _ChangeStyle(
        color: Color(0xFFE8F5E9),
        foreground: Color(0xFF1B5E20),
        icon: Icons.check_circle,
      ),
      ChordChangeOutcome.wrongChord => _ChangeStyle(
        color: theme.colorScheme.errorContainer,
        foreground: theme.colorScheme.onErrorContainer,
        icon: Icons.error,
      ),
      ChordChangeOutcome.noDetection => _ChangeStyle(
        color: theme.colorScheme.surfaceContainerHighest,
        foreground: theme.colorScheme.onSurfaceVariant,
        icon: Icons.hearing_disabled,
      ),
      ChordChangeOutcome.unstable => _ChangeStyle(
        color: theme.colorScheme.secondaryContainer,
        foreground: theme.colorScheme.onSecondaryContainer,
        icon: Icons.timelapse,
      ),
      ChordChangeOutcome.insufficientSignal => _ChangeStyle(
        color: theme.colorScheme.surfaceContainerHighest,
        foreground: theme.colorScheme.onSurfaceVariant,
        icon: Icons.signal_cellular_nodata,
      ),
    };

class _ChangeStyle {
  const _ChangeStyle({
    required this.color,
    required this.foreground,
    required this.icon,
  });

  final Color color;
  final Color foreground;
  final IconData icon;
}

String? _currentChord(CompiledPracticeTarget target, Duration playhead) {
  for (final segment in target.expectedChordSegments) {
    if (playhead >= segment.start && playhead < segment.end) {
      return segment.chord;
    }
  }
  return null;
}

String? _nextChord(CompiledPracticeTarget target, Duration playhead) {
  for (final segment in target.expectedChordSegments) {
    if (segment.start > playhead) return segment.chord;
  }
  return null;
}
