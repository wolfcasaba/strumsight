import 'package:meta/meta.dart';

import '../../../../core/music/strum.dart';
import 'beat_position.dart';
import 'meter.dart';
import 'practice_value_equality.dart';
import 'tempo.dart';

/// A deterministic session timeline compiled from authored practice content.
///
/// List fields are unmodifiable snapshots of the values passed to the
/// constructor.
@immutable
final class CompiledPracticeTarget {
  CompiledPracticeTarget({
    required this.definitionId,
    required this.definitionSnapshotVersion,
    required this.tempo,
    required this.meter,
    required this.countInBars,
    required this.countInDuration,
    required List<CompiledTargetEvent> events,
    required this.musicalDuration,
    required this.ringOutDuration,
    required this.totalDuration,
    required List<Duration> barBoundaries,
    required this.loopCount,
    required this.loopRange,
    required List<ExpectedChordSegment> expectedChordSegments,
    required this.scoringApplicable,
  }) : events = List<CompiledTargetEvent>.unmodifiable(events),
       barBoundaries = List<Duration>.unmodifiable(barBoundaries),
       expectedChordSegments = List<ExpectedChordSegment>.unmodifiable(
         expectedChordSegments,
       );

  final String definitionId;
  final int definitionSnapshotVersion;
  final Tempo tempo;
  final Meter meter;
  final int countInBars;
  final Duration countInDuration;
  final List<CompiledTargetEvent> events;
  final Duration musicalDuration;
  final Duration ringOutDuration;
  final Duration totalDuration;
  final List<Duration> barBoundaries;
  final int loopCount;
  final PracticeLoopRange? loopRange;
  final List<ExpectedChordSegment> expectedChordSegments;
  final bool scoringApplicable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompiledPracticeTarget &&
          other.definitionId == definitionId &&
          other.definitionSnapshotVersion == definitionSnapshotVersion &&
          other.tempo == tempo &&
          other.meter == meter &&
          other.countInBars == countInBars &&
          other.countInDuration == countInDuration &&
          listEquals(other.events, events) &&
          other.musicalDuration == musicalDuration &&
          other.ringOutDuration == ringOutDuration &&
          other.totalDuration == totalDuration &&
          listEquals(other.barBoundaries, barBoundaries) &&
          other.loopCount == loopCount &&
          other.loopRange == loopRange &&
          listEquals(other.expectedChordSegments, expectedChordSegments) &&
          other.scoringApplicable == scoringApplicable;

  @override
  int get hashCode => Object.hash(
    definitionId,
    definitionSnapshotVersion,
    tempo,
    meter,
    countInBars,
    countInDuration,
    listHash(events),
    musicalDuration,
    ringOutDuration,
    totalDuration,
    listHash(barBoundaries),
    loopCount,
    loopRange,
    listHash(expectedChordSegments),
    scoringApplicable,
  );
}

/// One non-marker target event placed on the compiled session timeline.
@immutable
final class CompiledTargetEvent {
  const CompiledTargetEvent({
    required this.sourceEventId,
    required this.loopIndex,
    required this.position,
    required this.time,
    required this.barIndex,
    required this.chord,
    required this.direction,
    required this.accent,
    required this.optional,
  });

  final String sourceEventId;
  final int loopIndex;

  /// Absolute musical position across compiled loops, excluding count-in.
  final BeatPosition position;

  /// Absolute elapsed time from session start, including count-in.
  final Duration time;

  /// Zero-based musical bar index, excluding count-in.
  final int barIndex;

  final String? chord;
  final StrumDirection? direction;
  final bool accent;
  final bool optional;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompiledTargetEvent &&
          other.sourceEventId == sourceEventId &&
          other.loopIndex == loopIndex &&
          other.position == position &&
          other.time == time &&
          other.barIndex == barIndex &&
          other.chord == chord &&
          other.direction == direction &&
          other.accent == accent &&
          other.optional == optional;

  @override
  int get hashCode => Object.hash(
    sourceEventId,
    loopIndex,
    position,
    time,
    barIndex,
    chord,
    direction,
    accent,
    optional,
  );
}

/// One active expected-chord interval on the compiled session timeline.
@immutable
final class ExpectedChordSegment {
  const ExpectedChordSegment({
    required this.chord,
    required this.start,
    required this.end,
  });

  final String chord;
  final Duration start;

  /// Exclusive segment end.
  final Duration end;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpectedChordSegment &&
          other.chord == chord &&
          other.start == start &&
          other.end == end;

  @override
  int get hashCode => Object.hash(chord, start, end);
}

/// A whole-bar source range selected for compilation.
@immutable
final class PracticeLoopRange {
  const PracticeLoopRange({
    required this.startBar,
    required this.endBarExclusive,
  });

  final int startBar;
  final int endBarExclusive;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeLoopRange &&
          other.startBar == startBar &&
          other.endBarExclusive == endBarExclusive;

  @override
  int get hashCode => Object.hash(startBar, endBarExclusive);
}
