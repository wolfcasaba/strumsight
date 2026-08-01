import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/free_practice_summary.dart';

/// Mode view for Free Practice. Surfaces the *fact-only* summary produced
/// by [FreePracticeSummarizer]: strum count, down/up ratio, chord timeline,
/// BPM samples, and tempo stability.
///
/// The view explicitly **does not** render a score, accuracy, or pass/fail
/// verdict. An `InsufficientData` fact is rendered with a localized "not
/// enough data yet" label, *never* as a 0 or `—` in score form (ADR 0082 §8).
class FreePracticeView extends StatelessWidget {
  const FreePracticeView({
    required this.summary,
    required this.width,
    super.key,
  });

  final FreePracticeSummary? summary;
  final double width;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final summary = this.summary;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (summary == null || summary.strumCount == 0)
            _NoSignalCard(l10n: l10n, theme: theme)
          else ...[
            _CountsCard(summary: summary, l10n: l10n, theme: theme),
            const SizedBox(height: 12),
            _DirectionCard(summary: summary, l10n: l10n, theme: theme),
            const SizedBox(height: 12),
            _TempoStabilityCard(summary: summary, l10n: l10n, theme: theme),
            const SizedBox(height: 12),
            _ChordTimelineCard(summary: summary, l10n: l10n, theme: theme),
            const SizedBox(height: 12),
            _BpmSamplesCard(summary: summary, l10n: l10n, theme: theme),
          ],
        ],
      ),
    );
  }
}

class _NoSignalCard extends StatelessWidget {
  const _NoSignalCard({required this.l10n, required this.theme});

  final AppLocalizations l10n;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: l10n.practiceFreePracticeNoSignalSemantics,
      child: Card(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.practiceFreePracticeNoSignalTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.practiceFreePracticeNoSignalBody,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountsCard extends StatelessWidget {
  const _CountsCard({
    required this.summary,
    required this.l10n,
    required this.theme,
  });

  final FreePracticeSummary summary;
  final AppLocalizations l10n;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return _FactCard(
      title: l10n.practiceFreePracticeCountsTitle,
      semanticsLabel: l10n.practiceFreePracticeCountsSemantics,
      l10n: l10n,
      theme: theme,
      children: [
        _FactRow(
          label: l10n.practiceFreePracticeStrumCount,
          value: '${summary.strumCount}',
          l10n: l10n,
          theme: theme,
        ),
        _FactRow(
          label: l10n.practiceFreePracticeActiveDuration,
          value: _formatDuration(summary.activeDuration),
          l10n: l10n,
          theme: theme,
        ),
      ],
    );
  }
}

class _DirectionCard extends StatelessWidget {
  const _DirectionCard({
    required this.summary,
    required this.l10n,
    required this.theme,
  });

  final FreePracticeSummary summary;
  final AppLocalizations l10n;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final ratio = summary.directionRatio;
    final nodes = <Widget>[];
    switch (ratio) {
      case FreePracticeDirectionRatioNotApplicable():
        nodes.add(
          _FactRow(
            label: l10n.practiceFreePracticeDirectionRatio,
            value: l10n.practiceFreePracticeDirectionNotApplicable,
            l10n: l10n,
            theme: theme,
            semanticsLabel:
                l10n.practiceFreePracticeDirectionNotApplicableSemantics,
          ),
        );
      case FreePracticeDirectionRatioInsufficientData():
        nodes.add(
          _FactRow(
            label: l10n.practiceFreePracticeDirectionRatio,
            value: l10n.practiceFreePracticeInsufficientData,
            l10n: l10n,
            theme: theme,
            semanticsLabel:
                l10n.practiceFreePracticeDirectionInsufficientSemantics,
          ),
        );
      case FreePracticeDirectionRatioAvailable():
        nodes.add(
          _FactRow(
            label: l10n.practiceFreePracticeDownCount,
            value: '${ratio.downCount}',
            l10n: l10n,
            theme: theme,
          ),
        );
        nodes.add(
          _FactRow(
            label: l10n.practiceFreePracticeUpCount,
            value: '${ratio.upCount}',
            l10n: l10n,
            theme: theme,
          ),
        );
        nodes.add(
          _FactRow(
            label: l10n.practiceFreePracticeDownRatio,
            value: l10n.practiceFreePracticePercent(ratio.downRatio * 100),
            l10n: l10n,
            theme: theme,
          ),
        );
        nodes.add(
          _FactRow(
            label: l10n.practiceFreePracticeUpRatio,
            value: l10n.practiceFreePracticePercent(ratio.upRatio * 100),
            l10n: l10n,
            theme: theme,
          ),
        );
    }
    return _FactCard(
      title: l10n.practiceFreePracticeDirectionTitle,
      semanticsLabel: l10n.practiceFreePracticeDirectionSemantics,
      l10n: l10n,
      theme: theme,
      children: nodes,
    );
  }
}

class _TempoStabilityCard extends StatelessWidget {
  const _TempoStabilityCard({
    required this.summary,
    required this.l10n,
    required this.theme,
  });

  final FreePracticeSummary summary;
  final AppLocalizations l10n;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final stability = summary.tempoStability;
    final nodes = <Widget>[];
    switch (stability) {
      case FreePracticeTempoStabilityInsufficientData():
        nodes.add(
          _FactRow(
            label: l10n.practiceFreePracticeTempoStability,
            value: l10n.practiceFreePracticeInsufficientData,
            l10n: l10n,
            theme: theme,
            semanticsLabel:
                l10n.practiceFreePracticeTempoStabilityInsufficientSemantics,
          ),
        );
      case FreePracticeTempoStabilityAvailable():
        nodes.add(
          _FactRow(
            label: l10n.practiceFreePracticeTempoStability,
            value: l10n.practiceFreePracticeMilliseconds(
              stability.deviation.inMilliseconds,
            ),
            l10n: l10n,
            theme: theme,
          ),
        );
    }
    return _FactCard(
      title: l10n.practiceFreePracticeTempoStabilityTitle,
      semanticsLabel: l10n.practiceFreePracticeTempoStabilitySemantics,
      l10n: l10n,
      theme: theme,
      children: nodes,
    );
  }
}

class _ChordTimelineCard extends StatelessWidget {
  const _ChordTimelineCard({
    required this.summary,
    required this.l10n,
    required this.theme,
  });

  final FreePracticeSummary summary;
  final AppLocalizations l10n;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final nodes = <Widget>[];
    if (summary.chordTimeline.isEmpty) {
      nodes.add(
        _FactRow(
          label: l10n.practiceFreePracticeChordTimeline,
          value: l10n.practiceFreePracticeInsufficientData,
          l10n: l10n,
          theme: theme,
          semanticsLabel:
              l10n.practiceFreePracticeChordTimelineInsufficientSemantics,
        ),
      );
    } else {
      for (final segment in summary.chordTimeline) {
        final label = segment.label ?? l10n.practiceFreePracticeChordNone;
        nodes.add(
          _FactRow(
            label: label,
            value: _formatDuration(segment.duration),
            l10n: l10n,
            theme: theme,
            semanticsLabel: l10n.practiceFreePracticeChordSegmentSemantics(
              label,
              _formatDuration(segment.duration),
            ),
          ),
        );
      }
    }
    return _FactCard(
      title: l10n.practiceFreePracticeChordTimelineTitle,
      semanticsLabel: l10n.practiceFreePracticeChordTimelineSemantics,
      l10n: l10n,
      theme: theme,
      children: nodes,
    );
  }
}

class _BpmSamplesCard extends StatelessWidget {
  const _BpmSamplesCard({
    required this.summary,
    required this.l10n,
    required this.theme,
  });

  final FreePracticeSummary summary;
  final AppLocalizations l10n;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final nodes = <Widget>[];
    if (summary.bpmSamples.isEmpty) {
      nodes.add(
        _FactRow(
          label: l10n.practiceFreePracticeBpmSamples,
          value: l10n.practiceFreePracticeInsufficientData,
          l10n: l10n,
          theme: theme,
          semanticsLabel:
              l10n.practiceFreePracticeBpmSamplesInsufficientSemantics,
        ),
      );
    } else {
      for (final sample in summary.bpmSamples) {
        nodes.add(
          _FactRow(
            label: l10n.practiceFreePracticeBpmSample(
              sample.bpm.toStringAsFixed(1),
              _formatDuration(sample.at),
            ),
            value: '',
            l10n: l10n,
            theme: theme,
          ),
        );
      }
    }
    return _FactCard(
      title: l10n.practiceFreePracticeBpmSamplesTitle,
      semanticsLabel: l10n.practiceFreePracticeBpmSamplesSemantics,
      l10n: l10n,
      theme: theme,
      children: nodes,
    );
  }
}

class _FactCard extends StatelessWidget {
  const _FactCard({
    required this.title,
    required this.semanticsLabel,
    required this.l10n,
    required this.theme,
    required this.children,
  });

  final String title;
  final String semanticsLabel;
  final AppLocalizations l10n;
  final ThemeData theme;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.label,
    required this.value,
    required this.l10n,
    required this.theme,
    this.semanticsLabel,
  });

  final String label;
  final String value;
  final AppLocalizations l10n;
  final ThemeData theme;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final merged = value.isEmpty ? label : '$label: $value';
    final semantics = semanticsLabel ?? merged;
    final bodyStyle = theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Semantics(
        container: true,
        label: semantics,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: bodyStyle, softWrap: true)),
            if (value.isNotEmpty) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  value,
                  style: bodyStyle,
                  textAlign: TextAlign.end,
                  softWrap: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final seconds = duration.inMilliseconds / 1000.0;
  return '${seconds.toStringAsFixed(2)} s';
}
