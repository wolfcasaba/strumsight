/// Computes the nine SDD Audio Analysis metrics (§29.6-29.8) plus a
/// tempo-band / signal-quality / mode slice breakdown for a parsed
/// evaluation manifest (E06-R29, ADR 0249).
library;

import 'dart:math' as math;

import '../../domain/evaluation/evaluation_report.dart';
import '../../domain/evaluation/ground_truth.dart';
import 'calibration_fitter.dart';

const Set<EvalEventType> _onsetLikeTypes = <EvalEventType>{
  EvalEventType.onset,
  EvalEventType.strum,
  EvalEventType.chordChange,
  EvalEventType.noteOnset,
};

/// One matched expected/detected event pair, with the time gap between
/// them in milliseconds.
final class MatchedEventPair {
  const MatchedEventPair(this.expected, this.detected);

  final EvalEvent expected;
  final EvalEvent detected;

  int get gapMs => (detected.timeMs - expected.timeMs).abs();
}

/// The result of matching one case's (or manifest's) expected events
/// against its detected events within a time tolerance.
final class EventMatchResult {
  const EventMatchResult({
    required this.precisionRecallF1,
    required this.matchedPairs,
  });

  final PrecisionRecallF1 precisionRecallF1;
  final List<MatchedEventPair> matchedPairs;
}

final class EvaluationRunner {
  const EvaluationRunner({
    this.onsetToleranceMs = 50,
    this.beatToleranceMs = 70,
    this.pitchToleranceMs = 50,
    this.chordFrameStepMs = 20,
    this.chordSegmentMinOverlapRatio = 0.5,
    CalibrationFitter? calibrationFitter,
  }) : _calibrationFitter = calibrationFitter ?? const CalibrationFitter();

  final int onsetToleranceMs;
  final int beatToleranceMs;
  final int pitchToleranceMs;
  final int chordFrameStepMs;
  final double chordSegmentMinOverlapRatio;
  final CalibrationFitter _calibrationFitter;

  EvaluationReport run(GroundTruthManifest manifest) {
    final overall = _metricsFor(manifest.cases);
    final slices = <MetricSlice>[
      for (final band in TempoBand.values)
        if (_sliceMetrics(manifest.cases, (c) => c.tempoBand == band)
            case final metrics?)
          MetricSlice(key: 'tempoBand:${band.name}', metrics: metrics),
      for (final tier in SignalQualityTier.values)
        if (_sliceMetrics(manifest.cases, (c) => c.signalQualityTier == tier)
            case final metrics?)
          MetricSlice(key: 'signalQualityTier:${tier.name}', metrics: metrics),
      for (final mode in EvalMode.values)
        if (_sliceMetrics(manifest.cases, (c) => c.mode == mode)
            case final metrics?)
          MetricSlice(key: 'mode:${mode.name}', metrics: metrics),
    ];
    return EvaluationReport(
      manifestSchemaVersion: manifest.schemaVersion,
      caseCount: manifest.cases.length,
      overall: overall,
      slices: slices,
    );
  }

  EvaluationMetrics? _sliceMetrics(
    List<GroundTruthCase> cases,
    bool Function(GroundTruthCase) predicate,
  ) {
    final subset = cases.where(predicate).toList(growable: false);
    if (subset.isEmpty) return null;
    return _metricsFor(subset);
  }

  EvaluationMetrics _metricsFor(List<GroundTruthCase> cases) {
    var onsetTp = 0, onsetFp = 0, onsetFn = 0;
    final allMatchedPairs = <MatchedEventPair>[];
    var chordFrameCorrect = 0, chordFrameTotal = 0;
    var chordSegmentMatched = 0, chordSegmentTotal = 0;
    var strumCorrect = 0, strumTotal = 0;
    final bpmErrors = <double>[];
    var beatMatched = 0, beatTotal = 0;
    final pitchCentsErrors = <double>[];
    final confidenceObservations = <ConfidenceObservation>[];

    for (final ground in cases) {
      final expectedOnsetEvents = ground.expected.events
          .where((e) => _onsetLikeTypes.contains(e.type))
          .toList(growable: false);
      final detectedOnsetEvents = ground.detected.events
          .where((e) => _onsetLikeTypes.contains(e.type))
          .toList(growable: false);
      final match = matchEvents(
        expectedOnsetEvents,
        detectedOnsetEvents,
        onsetToleranceMs,
      );
      onsetTp += match.precisionRecallF1.truePositives;
      onsetFp += match.precisionRecallF1.falsePositives;
      onsetFn += match.precisionRecallF1.falseNegatives;
      allMatchedPairs.addAll(match.matchedPairs);

      for (final pair in match.matchedPairs) {
        if (pair.expected.type == EvalEventType.strum &&
            pair.detected.direction != null) {
          strumTotal++;
          if (pair.expected.direction == pair.detected.direction) {
            strumCorrect++;
          }
        }
      }

      final chordFrames = _chordFrameCounts(
        ground.expected.chordSegments,
        ground.detected.chordSegments,
      );
      chordFrameCorrect += chordFrames.$1;
      chordFrameTotal += chordFrames.$2;

      final chordSegments = _chordSegmentCounts(
        ground.expected.chordSegments,
        ground.detected.chordSegments,
      );
      chordSegmentMatched += chordSegments.$1;
      chordSegmentTotal += chordSegments.$2;

      final expectedBpm = ground.expected.tempoBpm;
      final detectedBpm = ground.detected.tempoBpm;
      if (expectedBpm != null && detectedBpm != null && expectedBpm != 0) {
        bpmErrors.add((detectedBpm - expectedBpm).abs() / expectedBpm * 100);
      }

      final beatMatch = matchTimes(
        ground.expected.beatsMs,
        ground.detected.beatsMs,
        beatToleranceMs,
      );
      beatMatched += beatMatch.$1;
      beatTotal += ground.expected.beatsMs.length;

      pitchCentsErrors.addAll(
        _pitchCentsErrors(
          ground.expected.pitchPoints,
          ground.detected.pitchPoints,
        ),
      );

      confidenceObservations.addAll(ground.confidenceObservations);
    }

    final onsetPrecision = (onsetTp + onsetFp) == 0
        ? null
        : onsetTp / (onsetTp + onsetFp);
    final onsetRecall = (onsetTp + onsetFn) == 0
        ? null
        : onsetTp / (onsetTp + onsetFn);
    final onsetF1 = _f1(onsetPrecision, onsetRecall);

    final timestampMaeMs = allMatchedPairs.isEmpty
        ? null
        : allMatchedPairs.fold<double>(0, (acc, p) => acc + p.gapMs) /
              allMatchedPairs.length;

    final calibrationFit = _calibrationFitter.fit(confidenceObservations);

    return EvaluationMetrics(
      caseCount: cases.length,
      onset: PrecisionRecallF1(
        precision: onsetPrecision,
        recall: onsetRecall,
        f1: onsetF1,
        truePositives: onsetTp,
        falsePositives: onsetFp,
        falseNegatives: onsetFn,
      ),
      timestampMaeMs: timestampMaeMs,
      chordFrameAccuracy: chordFrameTotal == 0
          ? null
          : chordFrameCorrect / chordFrameTotal,
      chordSegmentAccuracy: chordSegmentTotal == 0
          ? null
          : chordSegmentMatched / chordSegmentTotal,
      strumDirectionAccuracy: strumTotal == 0
          ? null
          : strumCorrect / strumTotal,
      bpmErrorPercent: bpmErrors.isEmpty
          ? null
          : bpmErrors.reduce((a, b) => a + b) / bpmErrors.length,
      beatAlignmentAccuracy: beatTotal == 0 ? null : beatMatched / beatTotal,
      pitchCentsErrorMean: pitchCentsErrors.isEmpty
          ? null
          : pitchCentsErrors.fold<double>(0, (acc, e) => acc + e) /
                pitchCentsErrors.length,
      confidenceCalibration: calibrationFit.toMetrics(),
    );
  }

  /// Deterministic maximum-cardinality one-to-one matching of [expected]
  /// against [detected] within [toleranceMs], via Kuhn's augmenting-path
  /// algorithm: an expected event may only claim a still-unclaimed detected
  /// event inside the tolerance window, and a detected event is reassigned
  /// to a different expected event (freeing its previous one to seek
  /// another candidate) whenever that grows the total number of matches.
  /// Candidate edges are tried closest-gap-first (index as tie-breaker) so
  /// the result is reproducible across runs.
  ///
  /// `precision` is `null` when [detected] is empty (there is nothing to
  /// compute a precision over); `recall` is `null` only when [expected] is
  /// also empty.
  EventMatchResult matchEvents(
    List<EvalEvent> expected,
    List<EvalEvent> detected,
    int toleranceMs,
  ) {
    final sortedExpected = [...expected]
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    final sortedDetected = [...detected]
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));

    final candidatesByExpected = List<List<int>>.generate(
      sortedExpected.length,
      (i) {
        final expectedEvent = sortedExpected[i];
        final withGap =
            <MapEntry<int, int>>[
              for (var j = 0; j < sortedDetected.length; j++)
                if ((sortedDetected[j].timeMs - expectedEvent.timeMs).abs() <=
                    toleranceMs)
                  MapEntry(
                    j,
                    (sortedDetected[j].timeMs - expectedEvent.timeMs).abs(),
                  ),
            ]..sort((a, b) {
              final byGap = a.value.compareTo(b.value);
              return byGap != 0 ? byGap : a.key.compareTo(b.key);
            });
        return [for (final entry in withGap) entry.key];
      },
    );

    final matchOfDetected = _maxBipartiteMatching(
      leftCount: sortedExpected.length,
      candidatesByLeft: candidatesByExpected,
      rightCount: sortedDetected.length,
    );

    final matchedPairs = <MatchedEventPair>[];
    for (var j = 0; j < sortedDetected.length; j++) {
      final i = matchOfDetected[j];
      if (i != -1) {
        matchedPairs.add(
          MatchedEventPair(sortedExpected[i], sortedDetected[j]),
        );
      }
    }
    matchedPairs.sort((a, b) => a.expected.timeMs.compareTo(b.expected.timeMs));

    final tp = matchedPairs.length;
    final fp = sortedDetected.length - tp;
    final fn = sortedExpected.length - tp;
    final precision = sortedDetected.isEmpty
        ? null
        : tp / sortedDetected.length;
    final recall = sortedExpected.isEmpty ? null : tp / sortedExpected.length;

    return EventMatchResult(
      precisionRecallF1: PrecisionRecallF1(
        precision: precision,
        recall: recall,
        f1: _f1(precision, recall),
        truePositives: tp,
        falsePositives: fp,
        falseNegatives: fn,
      ),
      matchedPairs: matchedPairs,
    );
  }

  /// Kuhn's algorithm: finds a maximum-cardinality one-to-one matching
  /// between `leftCount` left nodes and `rightCount` right nodes, given
  /// each left node's admissible right-node candidates (ordered — ties are
  /// broken by that order). Returns `matchOfRight`, where
  /// `matchOfRight[j]` is the matched left index, or `-1` if unmatched.
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

  /// Same maximum-cardinality one-to-one matching as [matchEvents], for
  /// plain timestamp lists (beat grids). Returns
  /// `(matchedCount, unmatchedDetected)`.
  (int, int) matchTimes(
    List<int> expected,
    List<int> detected,
    int toleranceMs,
  ) {
    final sortedExpected = [...expected]..sort();
    final sortedDetected = [...detected]..sort();

    final candidatesByExpected = List<List<int>>.generate(
      sortedExpected.length,
      (i) {
        final expectedTime = sortedExpected[i];
        final withGap =
            <MapEntry<int, int>>[
              for (var j = 0; j < sortedDetected.length; j++)
                if ((sortedDetected[j] - expectedTime).abs() <= toleranceMs)
                  MapEntry(j, (sortedDetected[j] - expectedTime).abs()),
            ]..sort((a, b) {
              final byGap = a.value.compareTo(b.value);
              return byGap != 0 ? byGap : a.key.compareTo(b.key);
            });
        return [for (final entry in withGap) entry.key];
      },
    );

    final matchOfDetected = _maxBipartiteMatching(
      leftCount: sortedExpected.length,
      candidatesByLeft: candidatesByExpected,
      rightCount: sortedDetected.length,
    );

    final matched = matchOfDetected.where((i) => i != -1).length;
    return (matched, sortedDetected.length - matched);
  }

  double? _f1(double? precision, double? recall) {
    if (precision == null || recall == null) return null;
    final sum = precision + recall;
    if (sum == 0) return null;
    return 2 * precision * recall / sum;
  }

  /// `(correctFrames, totalFrames)` sampled every [chordFrameStepMs] across
  /// the expected timeline; a frame is correct if the expected and detected
  /// labels covering it match (including both being unlabelled).
  (int, int) _chordFrameCounts(
    List<EvalChordSegment> expected,
    List<EvalChordSegment> detected,
  ) {
    if (expected.isEmpty) return (0, 0);
    final maxEndMs = expected
        .map((s) => s.endMs)
        .fold<int>(0, (acc, v) => math.max(acc, v));
    var correct = 0;
    var total = 0;
    for (var t = 0; t < maxEndMs; t += chordFrameStepMs) {
      total++;
      final expectedLabel = _labelAt(expected, t);
      final detectedLabel = _labelAt(detected, t);
      if (expectedLabel == detectedLabel) correct++;
    }
    return (correct, total);
  }

  String? _labelAt(List<EvalChordSegment> segments, int timeMs) {
    for (final segment in segments) {
      if (timeMs >= segment.startMs && timeMs < segment.endMs) {
        return segment.label;
      }
    }
    return null;
  }

  /// `(matchedSegments, totalExpectedSegments)`: an expected segment matches
  /// a detected one when they share a label and their overlap covers at
  /// least [chordSegmentMinOverlapRatio] of the expected segment's
  /// duration. Matching is one-to-one — a detected segment can validate at
  /// most one expected segment — via the same maximum-cardinality
  /// bipartite matching as [matchEvents], so a single wide detected
  /// segment can no longer double-count.
  (int, int) _chordSegmentCounts(
    List<EvalChordSegment> expected,
    List<EvalChordSegment> detected,
  ) {
    final eligibleExpected = [
      for (final s in expected)
        if (s.endMs - s.startMs > 0) s,
    ];
    if (eligibleExpected.isEmpty) return (0, expected.length);

    final candidatesByExpected = List<List<int>>.generate(
      eligibleExpected.length,
      (i) {
        final expectedSegment = eligibleExpected[i];
        final expectedDuration =
            expectedSegment.endMs - expectedSegment.startMs;
        final withOverlap = <MapEntry<int, int>>[];
        for (var j = 0; j < detected.length; j++) {
          final detectedSegment = detected[j];
          if (detectedSegment.label != expectedSegment.label) continue;
          final overlapStart = math.max(
            expectedSegment.startMs,
            detectedSegment.startMs,
          );
          final overlapEnd = math.min(
            expectedSegment.endMs,
            detectedSegment.endMs,
          );
          final overlap = overlapEnd - overlapStart;
          if (overlap <= 0) continue;
          if (overlap / expectedDuration < chordSegmentMinOverlapRatio) {
            continue;
          }
          withOverlap.add(MapEntry(j, overlap));
        }
        withOverlap.sort((a, b) {
          final byOverlap = b.value.compareTo(a.value);
          return byOverlap != 0 ? byOverlap : a.key.compareTo(b.key);
        });
        return [for (final entry in withOverlap) entry.key];
      },
    );

    final matchOfDetected = _maxBipartiteMatching(
      leftCount: eligibleExpected.length,
      candidatesByLeft: candidatesByExpected,
      rightCount: detected.length,
    );
    final matched = matchOfDetected.where((i) => i != -1).length;
    return (matched, expected.length);
  }

  /// Same maximum-cardinality one-to-one matching as [matchEvents], on
  /// timestamps only; a matched pair's cents error is the absolute pitch
  /// distance between its expected and detected frequency.
  List<double> _pitchCentsErrors(
    List<PitchPoint> expected,
    List<PitchPoint> detected,
  ) {
    final sortedExpected = [...expected]
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    final sortedDetected = [...detected]
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));

    final candidatesByExpected = List<List<int>>.generate(
      sortedExpected.length,
      (i) {
        final expectedPoint = sortedExpected[i];
        final withGap =
            <MapEntry<int, int>>[
              for (var j = 0; j < sortedDetected.length; j++)
                if ((sortedDetected[j].timeMs - expectedPoint.timeMs).abs() <=
                    pitchToleranceMs)
                  MapEntry(
                    j,
                    (sortedDetected[j].timeMs - expectedPoint.timeMs).abs(),
                  ),
            ]..sort((a, b) {
              final byGap = a.value.compareTo(b.value);
              return byGap != 0 ? byGap : a.key.compareTo(b.key);
            });
        return [for (final entry in withGap) entry.key];
      },
    );

    final matchOfDetected = _maxBipartiteMatching(
      leftCount: sortedExpected.length,
      candidatesByLeft: candidatesByExpected,
      rightCount: sortedDetected.length,
    );

    final errors = <double>[];
    for (var j = 0; j < sortedDetected.length; j++) {
      final i = matchOfDetected[j];
      if (i != -1) {
        final expectedPoint = sortedExpected[i];
        final detectedPoint = sortedDetected[j];
        final cents =
            1200 * (math.log(detectedPoint.hz / expectedPoint.hz) / math.ln2);
        errors.add(cents.abs());
      }
    }
    return errors;
  }
}
