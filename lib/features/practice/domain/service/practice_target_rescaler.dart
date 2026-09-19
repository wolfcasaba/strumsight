import 'package:meta/meta.dart';

import '../model/compiled_practice_target.dart';
import '../model/tempo.dart';

/// The outcome of re-timing one compiled target onto a new tempo.
@immutable
final class RescaledPracticeTarget {
  const RescaledPracticeTarget({
    required this.target,
    required this.pivot,
    required this.position,
  });

  /// The re-timed timeline. Event identity, order, bar index and musical
  /// position are untouched — only the wall-clock placements move.
  final CompiledPracticeTarget target;

  /// The bar boundary the rescale is anchored to.
  final Duration pivot;

  /// The image of the requested position on [target]'s timeline.
  final Duration position;
}

/// Re-times an already compiled target onto [tempo] without recompiling it
/// from the definition.
///
/// A mid-session tempo change may not move the part of the timeline the
/// session has already played: verdicts recorded so far were judged against
/// those placements, and the chord scorer re-reads `target.time` on every
/// scoring pass. The rescale is therefore the affine map about a PIVOT — the
/// bar boundary at or before [position], which is exactly the anchor
/// `ResumePractice` re-enters the timeline on:
///
/// ```text
/// ratio  = target.tempo / tempo          (time scales as the inverse of BPM)
/// map(t) = t                             for t <= pivot   (history — frozen)
/// map(t) = pivot + (t - pivot) * ratio   for t >  pivot   (re-timed)
/// ```
///
/// The map is continuous at the pivot and strictly increasing for a positive
/// ratio, so the compiled event order (and the matcher's binary search over
/// it) survives the rescale. `countInDuration`, `musicalDuration`,
/// `ringOutDuration` and `totalDuration` are derived from the same map, so
/// `countIn + musical + ringOut == total` still holds exactly.
///
/// [tempo] must be a validated [Tempo] (see [Tempo.validate]); the caller —
/// the practice reducer — rejects the input before it reaches this function.
RescaledPracticeTarget rescalePracticeTarget({
  required CompiledPracticeTarget target,
  required Tempo tempo,
  required Duration position,
}) {
  final pivot = _barBoundaryAtOrBefore(target.barBoundaries, position);
  final ratio = target.tempo.bpm / tempo.bpm;
  Duration map(Duration time) =>
      time <= pivot ? time : pivot + (time - pivot) * ratio;
  final countInEnd = map(target.countInDuration);
  final musicalEnd = map(target.countInDuration + target.musicalDuration);
  final sessionEnd = map(target.totalDuration);
  return RescaledPracticeTarget(
    target: CompiledPracticeTarget(
      definitionId: target.definitionId,
      definitionSnapshotVersion: target.definitionSnapshotVersion,
      tempo: tempo,
      meter: target.meter,
      countInBars: target.countInBars,
      countInDuration: countInEnd,
      events: <CompiledTargetEvent>[
        for (final event in target.events)
          CompiledTargetEvent(
            sourceEventId: event.sourceEventId,
            loopIndex: event.loopIndex,
            position: event.position,
            time: map(event.time),
            barIndex: event.barIndex,
            chord: event.chord,
            direction: event.direction,
            accent: event.accent,
            optional: event.optional,
          ),
      ],
      musicalDuration: musicalEnd - countInEnd,
      ringOutDuration: sessionEnd - musicalEnd,
      totalDuration: sessionEnd,
      barBoundaries: <Duration>[
        for (final boundary in target.barBoundaries) map(boundary),
      ],
      loopCount: target.loopCount,
      loopRange: target.loopRange,
      expectedChordSegments: <ExpectedChordSegment>[
        for (final segment in target.expectedChordSegments)
          ExpectedChordSegment(
            chord: segment.chord,
            start: map(segment.start),
            end: map(segment.end),
          ),
      ],
      scoringApplicable: target.scoringApplicable,
    ),
    pivot: pivot,
    position: map(position),
  );
}

Duration _barBoundaryAtOrBefore(List<Duration> boundaries, Duration time) {
  var result = Duration.zero;
  for (final boundary in boundaries) {
    if (boundary > time) break;
    result = boundary;
  }
  return result;
}
