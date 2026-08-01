import 'package:meta/meta.dart';

import '../../../../core/music/strum.dart';
import '../model/free_practice_summary.dart';
import '../model/practice_definition.dart';
import '../model/practice_mode.dart';
import '../model/practice_observation.dart';
import '../model/practice_session_state.dart';

const Duration _minimumDuration = Duration.zero;
const int _minimumStrumCountForStability = 4;

/// Pure summarizer that turns a deterministic list of observations + BPM
/// samples + the session state into a [FreePracticeSummary].
///
/// The summary holds **only facts**: counts, ratios, timeline, and tempo
/// stability. It never produces a score, verdict, or pass/fail outcome — the
/// scoring pipeline is the only path that may surface those, and the
/// Free Practice profile is configured to yield `MetricNotApplicable` overall
/// (ADR 0082 §1).
@immutable
final class FreePracticeSummarizer {
  const FreePracticeSummarizer();

  /// Builds the score-free summary of one Free Practice session.
  ///
  /// [observations] must be ordered by `at` ascending (the gateway already
  /// enforces this — see the monotonic pads in `LivePracticeObservationGateway`).
  /// [bpmSamples] is the BPM signal the session chose to surface — it is
  /// forwarded verbatim, and the gateway layer is responsible for the
  /// pre-filtering (Tempo range, etc.).
  /// [activeDuration] is the `playingElapsed` of the session state — the
  /// only kind of time that participates in the summary (ADR 0082 §6).
  FreePracticeSummary summarize({
    required List<PracticeObservation> observations,
    required List<FreePracticeBpmSample> bpmSamples,
    required Duration activeDuration,
    required PracticeDefinition definition,
  }) {
    final countIn = activeDuration < _minimumDuration
        ? _minimumDuration
        : activeDuration;
    final strums = observations.whereType<StrumObservation>().toList(
      growable: false,
    );
    final chords = observations.whereType<ChordObservation>().toList(
      growable: false,
    );

    final directionApplicability = _directionApplicabilityOf(definition);
    final directionRatio = _directionRatio(
      definition: definition,
      strums: strums,
      applicability: directionApplicability,
    );

    final timeline = _chordTimeline(
      chordObservations: chords,
      activeDuration: countIn,
    );
    final timelineDuration = _timelineDuration(timeline);
    final tempoStability = _tempoStability(strumAtTimes: _strumAtTimes(strums));

    return FreePracticeSummary(
      strumCount: strums.length,
      activeDuration: countIn,
      chordTimelineDuration: timelineDuration,
      chordTimeline: timeline,
      bpmSamples: bpmSamples,
      tempoStability: tempoStability,
      directionRatio: directionRatio,
    );
  }

  // --- direction ratio -----------------------------------------------------

  FreePracticeDirectionRatio _directionRatio({
    required PracticeDefinition definition,
    required List<StrumObservation> strums,
    required _DirectionApplicability applicability,
  }) {
    if (applicability == _DirectionApplicability.notApplicable) {
      return const FreePracticeDirectionRatioNotApplicable();
    }
    if (strums.isEmpty) {
      return const FreePracticeDirectionRatioInsufficientData();
    }
    var down = 0;
    var up = 0;
    for (final strum in strums) {
      if (strum.direction == StrumDirection.down) {
        down++;
      } else {
        up++;
      }
    }
    final total = down + up;
    final downRatio = total == 0 ? 0.0 : down / total;
    final upRatio = total == 0 ? 0.0 : up / total;
    return FreePracticeDirectionRatioAvailable(
      downCount: down,
      upCount: up,
      downRatio: downRatio,
      upRatio: upRatio,
    );
  }

  // --- chord timeline ------------------------------------------------------

  List<FreePracticeChordSegment> _chordTimeline({
    required List<ChordObservation> chordObservations,
    required Duration activeDuration,
  }) {
    if (chordObservations.isEmpty) return const <FreePracticeChordSegment>[];
    final segments = <FreePracticeChordSegment>[];
    final ceiling = activeDuration < Duration.zero
        ? Duration.zero
        : activeDuration;
    for (var index = 0; index < chordObservations.length; index++) {
      final current = chordObservations[index];
      final nextAt = index + 1 < chordObservations.length
          ? chordObservations[index + 1].at
          : ceiling;
      final raw = nextAt - current.at;
      final duration = raw < Duration.zero ? Duration.zero : raw;
      segments.add(
        FreePracticeChordSegment(label: current.label, duration: duration),
      );
    }
    return segments;
  }

  Duration _timelineDuration(List<FreePracticeChordSegment> segments) {
    var total = Duration.zero;
    for (final segment in segments) {
      total += segment.duration;
    }
    return total;
  }

  // --- tempo stability (MAD-style) -----------------------------------------

  FreePracticeTempoStability _tempoStability({
    required List<Duration> strumAtTimes,
  }) {
    if (strumAtTimes.length < _minimumStrumCountForStability) {
      return const FreePracticeTempoStabilityInsufficientData();
    }
    final intervals = <Duration>[];
    for (var index = 1; index < strumAtTimes.length; index++) {
      final delta = strumAtTimes[index] - strumAtTimes[index - 1];
      if (delta < Duration.zero) continue;
      intervals.add(delta);
    }
    if (intervals.length < _minimumStrumCountForStability - 1) {
      return const FreePracticeTempoStabilityInsufficientData();
    }
    final sorted = intervals.toList()
      ..sort(
        (left, right) => left.inMicroseconds.compareTo(right.inMicroseconds),
      );
    final median = _medianDuration(sorted);
    final deviations =
        <Duration>[for (final interval in intervals) (interval - median).abs()]
          ..sort(
            (left, right) =>
                left.inMicroseconds.compareTo(right.inMicroseconds),
          );
    final mad = _medianDuration(deviations);
    return FreePracticeTempoStabilityAvailable(mad);
  }

  Duration _medianDuration(List<Duration> sorted) {
    if (sorted.isEmpty) return Duration.zero;
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    final sum =
        sorted[middle - 1].inMicroseconds + sorted[middle].inMicroseconds;
    return Duration(microseconds: sum ~/ 2);
  }

  List<Duration> _strumAtTimes(List<StrumObservation> strums) {
    final at = <Duration>[];
    for (final strum in strums) {
      if (strum.at < Duration.zero) continue;
      at.add(strum.at);
    }
    at.sort(
      (left, right) => left.inMicroseconds.compareTo(right.inMicroseconds),
    );
    return at;
  }
}

/// Optional helper used by callers (e.g. the Free Practice view) that just
/// need the surface vector of `playingElapsed` from a session state — the
/// session-state accessor is documented as the only clock that contributes
/// to the summary (ADR 0082 §6).
Duration freePracticeActiveDuration(PracticeSessionState state) =>
    state.playingElapsed;

_DirectionApplicability _directionApplicabilityOf(
  PracticeDefinition definition,
) {
  // Free Practice always answers the direction axis — every strum observation
  // carries a direction, so the ratio is *applicable* on this run. Other
  // modes declare direction on the definition's events; if no event asks
  // for a direction, the axis is NotApplicable (A1).
  if (definition.mode == PracticeMode.freePractice) {
    return _DirectionApplicability.applicable;
  }
  final hasDirection = definition.events.any(
    (event) => event.direction != null,
  );
  if (hasDirection) return _DirectionApplicability.applicable;
  return _DirectionApplicability.notApplicable;
}

enum _DirectionApplicability { applicable, notApplicable }
