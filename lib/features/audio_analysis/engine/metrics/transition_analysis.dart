import '../../domain/analysis_event.dart';
import '../../domain/analysis_segment.dart';

/// How far BEFORE a chord change the technique-proxy window starts (OD-02).
const Duration transitionWindowBefore = Duration(milliseconds: 150);

/// How far AFTER a chord change the technique-proxy window ends (OD-02).
///
/// The window is deliberately asymmetric — noise AFTER a change is the
/// characteristic signal, so the post-change span is wider than the
/// pre-change span.
const Duration transitionWindowAfter = Duration(milliseconds: 250);

/// Minimum recurrences of the SAME chord-pair transition to trust its
/// proxies (OD-03). Inclusive: exactly this many recurrences is sufficient.
const int minimumTransitionRepetitions = 4;

/// One observed chord-label change, derived from two adjacent [ChordSegment]s.
final class ChordTransition {
  ChordTransition({
    required this.time,
    required this.fromLabel,
    required this.toLabel,
  }) {
    if (time.isNegative) throw ArgumentError.value(time, 'time');
    if (fromLabel.trim().isEmpty) {
      throw ArgumentError.value(fromLabel, 'fromLabel');
    }
    if (toLabel.trim().isEmpty) throw ArgumentError.value(toLabel, 'toLabel');
  }

  final Duration time;
  final String fromLabel;
  final String toLabel;

  /// Groups repeated occurrences of the same chord-to-chord move (OD-03).
  String get pairKey => '$fromLabel>$toLabel';
}

/// The `[-150 ms, +250 ms]` window around one [ChordTransition] (OD-02).
/// Both boundaries are inclusive.
final class TransitionWindow {
  TransitionWindow(this.transition)
    : start = transition.time - transitionWindowBefore,
      end = transition.time + transitionWindowAfter;

  final ChordTransition transition;
  final Duration start;
  final Duration end;

  bool contains(Duration time) => time >= start && time <= end;
}

/// Builds one [ChordTransition] per adjacent label change, ordered by start
/// time. Adjacent segments sharing the same label never produce a transition.
List<ChordTransition> buildChordTransitions(List<ChordSegment> segments) {
  final ordered = List<ChordSegment>.of(segments)
    ..sort((a, b) => a.start.compareTo(b.start));
  final transitions = <ChordTransition>[];
  for (var index = 1; index < ordered.length; index += 1) {
    final previous = ordered[index - 1];
    final current = ordered[index];
    if (previous.label == current.label) continue;
    transitions.add(
      ChordTransition(
        time: current.start,
        fromLabel: previous.label,
        toLabel: current.label,
      ),
    );
  }
  return List<ChordTransition>.unmodifiable(transitions);
}

/// How many times each chord-pair move (OD-03 `pairKey`) recurs in
/// [transitions].
Map<String, int> countTransitionRepetitions(List<ChordTransition> transitions) {
  final counts = <String, int>{};
  for (final transition in transitions) {
    counts[transition.pairKey] = (counts[transition.pairKey] ?? 0) + 1;
  }
  return Map<String, int>.unmodifiable(counts);
}

/// The largest repetition count among [transitions]' chord-pairs, or 0 for
/// an empty list. Used as the single OD-03 gate value for a clip.
int maxTransitionRepetition(List<ChordTransition> transitions) {
  final counts = countTransitionRepetitions(transitions).values;
  return counts.isEmpty ? 0 : counts.reduce((a, b) => a > b ? a : b);
}

/// [onsets] whose time falls within [window], inclusive at both ends.
List<OnsetEvent> onsetsInWindow(
  TransitionWindow window,
  List<OnsetEvent> onsets,
) => List<OnsetEvent>.unmodifiable(
  onsets.where((onset) => window.contains(onset.time)),
);
