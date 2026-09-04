/// Recognition-annotation contract and two-annotator agreement types
/// (E14-R07, ADR 0359).
///
/// These types model an already-parsed annotation pair — the typed-failure
/// surface (schema version, unknown fields, missing provenance, overlap)
/// lives in `RecognitionAnnotationParser`, not here. Every type here is
/// `dart:io`-free, pure value code (ADR 0359 D1/D6/D7): no file is opened,
/// no other feature is imported, and [AnnotationAgreementCalculator] never
/// reads the clock — the same [RecognitionAnnotationPair] and [toleranceMs]
/// always produce a byte-identical [AgreementReport] (ADR 0359 D5).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:strumsight/core/music/strum.dart';

/// Event kinds a recognition annotation can record.
enum AnnotationEventType { onset, strum }

/// Where an annotated value came from. `auto` never promotes itself to
/// `human` or `reviewed` — that is an explicit human act recorded by
/// re-annotating, not a side effect of reading the file (ADR 0359 D2).
enum AnnotationProvenance { auto, human, reviewed }

/// One point-in-time onset/strum annotation.
final class AnnotationEvent {
  AnnotationEvent({
    required this.id,
    required this.timeMs,
    required this.type,
    required this.provenance,
    this.direction,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (timeMs < 0) {
      throw ArgumentError.value(timeMs, 'timeMs', 'must not be negative');
    }
    if (direction != null && type != AnnotationEventType.strum) {
      throw ArgumentError.value(
        direction,
        'direction',
        'is only valid for strum events',
      );
    }
  }

  final String id;
  final int timeMs;
  final AnnotationEventType type;
  final AnnotationProvenance provenance;
  final StrumDirection? direction;
}

/// One labelled chord interval; `endMs >= startMs` is enforced at
/// construction.
final class AnnotationChordSegment {
  AnnotationChordSegment({
    required this.id,
    required this.startMs,
    required this.endMs,
    required this.label,
    required this.provenance,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (startMs < 0) {
      throw ArgumentError.value(startMs, 'startMs', 'must not be negative');
    }
    if (endMs < startMs) {
      throw ArgumentError.value(
        endMs,
        'endMs',
        'must be >= startMs ($startMs)',
      );
    }
    if (label.trim().isEmpty) {
      throw ArgumentError.value(label, 'label', 'must not be empty');
    }
  }

  final String id;
  final int startMs;
  final int endMs;
  final String label;
  final AnnotationProvenance provenance;
}

/// One annotator's full annotation of a clip.
final class RecognitionAnnotation {
  RecognitionAnnotation({
    required this.annotatorId,
    List<AnnotationEvent> events = const <AnnotationEvent>[],
    List<AnnotationChordSegment> chordSegments =
        const <AnnotationChordSegment>[],
  }) : events = List<AnnotationEvent>.unmodifiable(events),
       chordSegments = List<AnnotationChordSegment>.unmodifiable(
         chordSegments,
       ) {
    if (annotatorId.trim().isEmpty) {
      throw ArgumentError.value(
        annotatorId,
        'annotatorId',
        'must not be empty',
      );
    }
  }

  final String annotatorId;
  final List<AnnotationEvent> events;
  final List<AnnotationChordSegment> chordSegments;
}

/// A fully parsed, two-annotator recognition annotation pair.
final class RecognitionAnnotationPair {
  RecognitionAnnotationPair({
    required this.schemaVersion,
    required this.annotatorA,
    required this.annotatorB,
  });

  /// The only schema version `RecognitionAnnotationParser` currently
  /// accepts.
  static const String supportedSchemaVersion = '1.0';

  final String schemaVersion;
  final RecognitionAnnotation annotatorA;
  final RecognitionAnnotation annotatorB;
}

/// One matched event pair between the two annotators.
final class MatchedAnnotationEventPair {
  const MatchedAnnotationEventPair(this.a, this.b);

  final AnnotationEvent a;
  final AnnotationEvent b;

  int get gapMs => (b.timeMs - a.timeMs).abs();
}

/// One matched chord-segment pair between the two annotators.
final class MatchedAnnotationChordPair {
  const MatchedAnnotationChordPair(this.a, this.b);

  final AnnotationChordSegment a;
  final AnnotationChordSegment b;

  int get gapMs => (b.startMs - a.startMs).abs();
}

/// The measured two-annotator agreement for one [RecognitionAnnotationPair]
/// at one [toleranceMs] (ADR 0359 D4). `matchedEventRatio` and
/// `directionAgreement` are different quantities and must not be confused:
/// the former divides by the larger annotator's event count, the latter by
/// the number of *matched* pairs. Both — and `chordAgreement` — are `null`
/// only when their denominator is zero (nothing to compute a ratio over),
/// never coerced to `0`.
final class AgreementReport {
  const AgreementReport({
    required this.annotatorAId,
    required this.annotatorBId,
    required this.toleranceMs,
    required this.eventCountA,
    required this.eventCountB,
    required this.matchedEventCount,
    required this.matchedEventRatio,
    required this.directionAgreement,
    required this.chordCountA,
    required this.chordCountB,
    required this.matchedChordCount,
    required this.matchedChordRatio,
    required this.chordAgreement,
  });

  final String annotatorAId;
  final String annotatorBId;
  final int toleranceMs;
  final int eventCountA;
  final int eventCountB;
  final int matchedEventCount;
  final double? matchedEventRatio;
  final double? directionAgreement;
  final int chordCountA;
  final int chordCountB;
  final int matchedChordCount;
  final double? matchedChordRatio;
  final double? chordAgreement;

  /// Canonical, alphabetically-keyed JSON — the same report always
  /// serialises to the same map.
  Map<String, Object?> toJson() => <String, Object?>{
    'annotatorAId': annotatorAId,
    'annotatorBId': annotatorBId,
    'chordAgreement': chordAgreement,
    'chordCountA': chordCountA,
    'chordCountB': chordCountB,
    'directionAgreement': directionAgreement,
    'eventCountA': eventCountA,
    'eventCountB': eventCountB,
    'matchedChordCount': matchedChordCount,
    'matchedChordRatio': matchedChordRatio,
    'matchedEventCount': matchedEventCount,
    'matchedEventRatio': matchedEventRatio,
    'toleranceMs': toleranceMs,
  };

  /// A stable, timestamp-free JSON rendering: the same report always
  /// produces byte-identical output.
  String toDeterministicJson() =>
      const JsonEncoder.withIndent('  ').convert(toJson());
}

/// Computes two-annotator agreement over a [RecognitionAnnotationPair]
/// (ADR 0359 D4). [toleranceMs] is a caller parameter — not a baked-in
/// constant — with a documented default of 50 ms; the pairing boundary is
/// inclusive, so a gap exactly equal to [toleranceMs] still pairs and only a
/// strictly larger gap does not.
final class AnnotationAgreementCalculator {
  const AnnotationAgreementCalculator({this.toleranceMs = 50});

  final int toleranceMs;

  AgreementReport compute(RecognitionAnnotationPair pair) {
    final a = pair.annotatorA;
    final b = pair.annotatorB;

    final matchedEvents = _matchEvents(a.events, b.events);
    var directionMatches = 0;
    var directionTotal = 0;
    for (final matched in matchedEvents) {
      if (matched.a.type == AnnotationEventType.strum &&
          matched.b.type == AnnotationEventType.strum) {
        directionTotal++;
        if (matched.a.direction == matched.b.direction) {
          directionMatches++;
        }
      }
    }

    final matchedChords = _matchChordSegments(a.chordSegments, b.chordSegments);
    var chordMatches = 0;
    for (final matched in matchedChords) {
      if (matched.a.label == matched.b.label) chordMatches++;
    }

    final maxEvents = math.max(a.events.length, b.events.length);
    final maxChords = math.max(a.chordSegments.length, b.chordSegments.length);

    return AgreementReport(
      annotatorAId: a.annotatorId,
      annotatorBId: b.annotatorId,
      toleranceMs: toleranceMs,
      eventCountA: a.events.length,
      eventCountB: b.events.length,
      matchedEventCount: matchedEvents.length,
      matchedEventRatio: maxEvents == 0
          ? null
          : matchedEvents.length / maxEvents,
      directionAgreement: directionTotal == 0
          ? null
          : directionMatches / directionTotal,
      chordCountA: a.chordSegments.length,
      chordCountB: b.chordSegments.length,
      matchedChordCount: matchedChords.length,
      matchedChordRatio: maxChords == 0
          ? null
          : matchedChords.length / maxChords,
      chordAgreement: matchedChords.isEmpty
          ? null
          : chordMatches / matchedChords.length,
    );
  }

  /// Deterministic maximum-cardinality one-to-one matching of [left] against
  /// [right], via Kuhn's augmenting-path algorithm (same shape as
  /// `EvaluationRunner.matchEvents` in the Audio Analysis evaluation
  /// harness — the pattern is copied, not imported, per ADR 0359 D6). An
  /// event may only pair with a same-`type` counterpart inside
  /// [toleranceMs]; candidate edges are tried closest-gap-first (index as
  /// tie-breaker) so the result is reproducible across runs.
  List<MatchedAnnotationEventPair> _matchEvents(
    List<AnnotationEvent> left,
    List<AnnotationEvent> right,
  ) {
    final sortedLeft = [...left]..sort((x, y) => x.timeMs.compareTo(y.timeMs));
    final sortedRight = [...right]
      ..sort((x, y) => x.timeMs.compareTo(y.timeMs));

    final candidatesByLeft = List<List<int>>.generate(sortedLeft.length, (i) {
      final leftEvent = sortedLeft[i];
      final withGap =
          <MapEntry<int, int>>[
            for (var j = 0; j < sortedRight.length; j++)
              if (sortedRight[j].type == leftEvent.type &&
                  (sortedRight[j].timeMs - leftEvent.timeMs).abs() <=
                      toleranceMs)
                MapEntry(j, (sortedRight[j].timeMs - leftEvent.timeMs).abs()),
          ]..sort((x, y) {
            final byGap = x.value.compareTo(y.value);
            return byGap != 0 ? byGap : x.key.compareTo(y.key);
          });
      return [for (final entry in withGap) entry.key];
    });

    final matchOfRight = _maxBipartiteMatching(
      leftCount: sortedLeft.length,
      candidatesByLeft: candidatesByLeft,
      rightCount: sortedRight.length,
    );

    final matched = <MatchedAnnotationEventPair>[];
    for (var j = 0; j < sortedRight.length; j++) {
      final i = matchOfRight[j];
      if (i != -1) {
        matched.add(MatchedAnnotationEventPair(sortedLeft[i], sortedRight[j]));
      }
    }
    matched.sort((x, y) => x.a.timeMs.compareTo(y.a.timeMs));
    return matched;
  }

  /// Same matching strategy as [_matchEvents], applied to chord segments by
  /// `startMs` (no `type` filter — there is only one chord lane).
  List<MatchedAnnotationChordPair> _matchChordSegments(
    List<AnnotationChordSegment> left,
    List<AnnotationChordSegment> right,
  ) {
    final sortedLeft = [...left]
      ..sort((x, y) => x.startMs.compareTo(y.startMs));
    final sortedRight = [...right]
      ..sort((x, y) => x.startMs.compareTo(y.startMs));

    final candidatesByLeft = List<List<int>>.generate(sortedLeft.length, (i) {
      final leftSegment = sortedLeft[i];
      final withGap =
          <MapEntry<int, int>>[
            for (var j = 0; j < sortedRight.length; j++)
              if ((sortedRight[j].startMs - leftSegment.startMs).abs() <=
                  toleranceMs)
                MapEntry(
                  j,
                  (sortedRight[j].startMs - leftSegment.startMs).abs(),
                ),
          ]..sort((x, y) {
            final byGap = x.value.compareTo(y.value);
            return byGap != 0 ? byGap : x.key.compareTo(y.key);
          });
      return [for (final entry in withGap) entry.key];
    });

    final matchOfRight = _maxBipartiteMatching(
      leftCount: sortedLeft.length,
      candidatesByLeft: candidatesByLeft,
      rightCount: sortedRight.length,
    );

    final matched = <MatchedAnnotationChordPair>[];
    for (var j = 0; j < sortedRight.length; j++) {
      final i = matchOfRight[j];
      if (i != -1) {
        matched.add(MatchedAnnotationChordPair(sortedLeft[i], sortedRight[j]));
      }
    }
    matched.sort((x, y) => x.a.startMs.compareTo(y.a.startMs));
    return matched;
  }

  /// Kuhn's algorithm: finds a maximum-cardinality one-to-one matching
  /// between `leftCount` left nodes and `rightCount` right nodes, given each
  /// left node's admissible right-node candidates (ordered — ties are broken
  /// by that order). Returns `matchOfRight`, where `matchOfRight[j]` is the
  /// matched left index, or `-1` if unmatched.
  List<int> _maxBipartiteMatching({
    required int leftCount,
    required List<List<int>> candidatesByLeft,
    required int rightCount,
  }) {
    final matchOfRight = List<int>.filled(rightCount, -1);

    bool tryAugment(int leftIndex, List<bool> visited) {
      for (final rightIndex in candidatesByLeft[leftIndex]) {
        if (visited[rightIndex]) continue;
        visited[rightIndex] = true;
        if (matchOfRight[rightIndex] == -1 ||
            tryAugment(matchOfRight[rightIndex], visited)) {
          matchOfRight[rightIndex] = leftIndex;
          return true;
        }
      }
      return false;
    }

    for (var i = 0; i < leftCount; i++) {
      tryAugment(i, List<bool>.filled(rightCount, false));
    }
    return matchOfRight;
  }
}
