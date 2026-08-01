import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/empty_state.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/model/practice_history_entry.dart';
import '../../domain/model/practice_insight.dart';
import '../../domain/model/practice_metric_snapshot.dart';
import '../../domain/model/practice_mode.dart';
import '../widgets/score_breakdown.dart';
import '../widgets/timing_bias_chart.dart';

/// The mode-specific Practice result screen (ADR 0084 §Döntés 1, 10, 11).
///
/// Every dimension is rendered iff:
///   * it is **applicable** to the entry's mode (otherwise the dimension
///     is omitted entirely — `findsNothing` — never rendered as 0%);
///   * the entry recorded an [PracticeMetricDimensionAvailable] for it
///     (otherwise a localised "not enough data" string is shown).
class PracticeResultScreen extends ConsumerWidget {
  const PracticeResultScreen({required this.entry, super.key});

  final PracticeHistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mode = _modeFor(entry.modeCode);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.practiceResultTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Header(entry: entry),
            const SizedBox(height: 16),
            if (mode == PracticeMode.freePractice)
              _FreePracticeLayout(entry: entry)
            else
              _ScoredLayout(entry: entry, mode: mode),
            const SizedBox(height: 16),
            _InsightSection(entry: entry),
          ],
        ),
      ),
    );
  }

  PracticeMode _modeFor(String code) {
    for (final mode in PracticeMode.values) {
      if (mode.code == code) return mode;
    }
    return PracticeMode.strumPattern;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.entry});
  final PracticeHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.displayTitle.isEmpty
              ? l10n.practiceResultTitle
              : entry.displayTitle,
          style: textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          _finishReasonLabel(l10n, entry.finishReasonCode),
          style: textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _ScoredLayout extends StatelessWidget {
  const _ScoredLayout({required this.entry, required this.mode});
  final PracticeHistoryEntry entry;
  final PracticeMode mode;

  @override
  Widget build(BuildContext context) {
    final snapshot = entry.finalMetricSnapshot;
    final l10n = AppLocalizations.of(context);

    final breakdown = ScoreBreakdown(
      dimensions: <ScoreBreakdownRow>[
        if (PracticeMetricKind.overall.isApplicableTo(mode))
          (
            label: PracticeMetricKind.overall.label(l10n),
            dimension: snapshot.overall,
          ),
        if (PracticeMetricKind.completion.isApplicableTo(mode))
          (
            label: PracticeMetricKind.completion.label(l10n),
            dimension: snapshot.completion,
          ),
        if (PracticeMetricKind.rhythm.isApplicableTo(mode))
          (
            label: PracticeMetricKind.rhythm.label(l10n),
            dimension: snapshot.rhythm,
          ),
        if (PracticeMetricKind.direction.isApplicableTo(mode))
          (
            label: PracticeMetricKind.direction.label(l10n),
            dimension: snapshot.direction,
          ),
        if (PracticeMetricKind.chord.isApplicableTo(mode))
          (
            label: PracticeMetricKind.chord.label(l10n),
            dimension: snapshot.chord,
          ),
        if (PracticeMetricKind.chordPair.isApplicableTo(mode))
          (label: PracticeMetricKind.chordPair.label(l10n), dimension: null),
        // Speed Builder result tile: dead-code branch removed (brief m3).
        // The real wiring lives one layer down — the controller owns
        // `SpeedBuilderState` and the controller is out of scope for
        // R18; until then this screen has no Speed Builder row to show.
        // Re-introduce once the controller exposes the active state
        // through `entry` (R19 follow-up, see the brief's §3 followups).
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        breakdown,
        const SizedBox(height: 16),
        TimingBiasChart(
          detailAttempts: entry.detailAttempts,
          timingBias: entry.timingBias,
        ),
      ],
    );
  }
}

class _FreePracticeLayout extends StatelessWidget {
  const _FreePracticeLayout({required this.entry});
  final PracticeHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Free Practice is intentionally score-free (ADR 0082 §1).
    // The result screen surfaces only the facts the engine already exposes
    // in the per-session summary — no accuracy, no combo, no pass/fail.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FactTile(
          label: l10n.practiceFreePracticeActiveDuration,
          value: _durationLabel(entry.activeDuration),
        ),
        _FactTile(
          label: l10n.practiceFreePracticeStrumCount,
          value: '${entry.attemptsCount}',
        ),
      ],
    );
  }
}

class _InsightSection extends StatelessWidget {
  const _InsightSection({required this.entry});
  final PracticeHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Without the live coach context, the result screen reads the entry's
    // already-persisted coachingSummary as the human-readable hints. The
    // codes are localisable here so a future i18n round can map them.
    if (entry.coachingSummary.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.practiceResultCoachingTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final code in entry.coachingSummary) _InsightRow(code: code),
          ],
        ),
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text('• ${_label(code)}'),
    );
  }

  String _label(String code) {
    if (PracticeInsightCode.values.contains(code)) {
      return _humanise(code);
    }
    return code;
  }

  String _humanise(String code) {
    final tail = code.split('.').last;
    return tail.replaceAll('_', ' ');
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

String _finishReasonLabel(AppLocalizations l10n, String code) {
  switch (code) {
    case 'completedAllTargets':
      return l10n.practiceSessionStatusCompleted;
    case 'userFinished':
      return l10n.practiceResultFinishUserFinished;
    case 'cancelled':
      return l10n.practiceSessionStatusCancelled;
    case 'timedOut':
      return l10n.practiceResultFinishTimedOut;
    case 'interrupted':
      return l10n.practiceResultFinishInterrupted;
    case 'failed':
      return l10n.practiceSessionStatusFailed;
  }
  return code;
}

String _durationLabel(Duration d) {
  final seconds = d.inSeconds;
  if (seconds < 60) return '${d.inSeconds}s';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (rest == 0) return '${minutes}m';
  return '${minutes}m ${rest}s';
}

/// Mode-keyed metric visibility (A1 — single source of truth).
class PracticeMetricKind {
  const PracticeMetricKind._(this._name);

  final String _name;

  static const overall = PracticeMetricKind._('overall');
  static const completion = PracticeMetricKind._('completion');
  static const rhythm = PracticeMetricKind._('rhythm');
  static const direction = PracticeMetricKind._('direction');
  static const chord = PracticeMetricKind._('chord');
  static const chordPair = PracticeMetricKind._('chordPair');

  bool isApplicableTo(PracticeMode mode) {
    return switch (this) {
      _ when identical(this, overall) => mode != PracticeMode.freePractice,
      _ when identical(this, completion) => mode != PracticeMode.freePractice,
      _ when identical(this, rhythm) => mode != PracticeMode.freePractice,
      _ when identical(this, direction) => switch (mode) {
        PracticeMode.strumPattern => true,
        PracticeMode.chordProgression => true,
        PracticeMode.chordChanges => false,
        PracticeMode.rhythmOnly => false,
        PracticeMode.freePractice => false,
      },
      _ when identical(this, chord) => switch (mode) {
        PracticeMode.strumPattern => false,
        PracticeMode.chordProgression => true,
        PracticeMode.chordChanges => true,
        PracticeMode.rhythmOnly => false,
        PracticeMode.freePractice => false,
      },
      _ when identical(this, chordPair) => mode == PracticeMode.chordChanges,
      _ => false,
    };
  }

  String label(AppLocalizations l10n) {
    return switch (this) {
      _ when identical(this, overall) => l10n.practiceResultOverall,
      _ when identical(this, completion) => l10n.practiceResultCompletion,
      _ when identical(this, rhythm) => l10n.practiceResultRhythm,
      _ when identical(this, direction) => l10n.practiceResultDirection,
      _ when identical(this, chord) => l10n.practiceResultChord,
      _ when identical(this, chordPair) => l10n.practiceResultChordPair,
      _ => _name,
    };
  }
}

/// Convenience used by the practice hub to land on this screen from a
/// navigation sink. Public, so the screen can be tested directly.
class PracticeResultFallback extends StatelessWidget {
  const PracticeResultFallback({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.practiceResultTitle)),
      body: EmptyState(
        icon: Icons.bar_chart,
        title: l10n.practiceResultUnavailableTitle,
        subtitle: l10n.practiceResultUnavailableBody,
      ),
    );
  }
}
