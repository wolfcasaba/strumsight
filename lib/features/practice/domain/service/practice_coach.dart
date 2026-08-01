import '../../domain/model/practice_insight.dart';
import '../../domain/model/practice_metrics.dart';
import '../../domain/model/practice_session_result.dart' as presult;

/// Pure coach — converts one finished session into a single
/// [PracticeInsight] (ADR 0084 §Döntés 7–9).
///
/// The rules below are the exact matrix from the brief A4 / A5 acceptance
/// criteria, and the brief explicitly forbids relaxing them. Every insight
/// has a documented evidence threshold; the coach never invents a story
/// from a single data point.
///
/// Priority order (fixed; ties break on the list position — ADR 0084
/// §Döntés 8):
///
///   1. `noSignal`               — zero observations.
///   2. `lowCompletion`          — completion < 0.5.
///   3. `biasLate` / `biasEarly` — paired-event bias crosses ±0.5 with
///                                 enough evidence (≥ 8 paired events,
///                                 ≥ 70% share).
///   4. `directionError`         — direction < 0.6.
///   5. `chordError`             — chord < 0.6.
///   6. `chordPairProblem`       — one chord pair with ≥ 3 measurements is
///                                 the median-worst by ≥ 30% relative delay.
///   7. `tempoTooHigh`           — rhythm < 0.7 with a tempo ≥ 120 BPM.
///   8. `positiveReinforcement`  — every available dimension ≥ 0.85.
///   9. `nextDifficulty`         — the user's other dimensions are clean and
///                                 the rhythm ceiling has been comfortably hit.
class PracticeCoach {
  const PracticeCoach();

  static const double _lowCompletionThreshold = 0.5;
  static const double _directionErrorThreshold = 0.6;
  static const double _chordErrorThreshold = 0.6;
  static const double _rhythmErrorThreshold = 0.7;
  static const double _reinforcementThreshold = 0.85;
  static const double _tempoCeilingForTempoTooHigh = 120.0;
  static const double _tempoCeilingForNextDifficulty = 130.0;

  static const int _biasMinPairedEvents = 8;
  static const double _biasMinShare = 0.7;

  static const int _pairMinMeasurements = 3;
  static const double _pairMinRelativeDelay = 0.3;

  PracticeInsight coach({
    required presult.PracticeSessionResult result,
    required PracticeSessionContext context,
  }) {
    if (result.attempts.isEmpty) {
      return const PracticeInsight(code: PracticeInsightCode.noSignal);
    }

    final finalAttempt = result.finalAttempt;
    if (finalAttempt == null) {
      return const PracticeInsight(code: PracticeInsightCode.noSignal);
    }
    final metrics = finalAttempt.metrics;

    // 1. No signal — no strums heard.
    final strumCount = context.strumCount;
    if (strumCount == 0) {
      return const PracticeInsight(code: PracticeInsightCode.noSignal);
    }

    // 2. Low completion — session was cut short.
    final completion = _extractAvailable(metrics.completion);
    if (completion != null && completion < _lowCompletionThreshold) {
      return const PracticeInsight(code: PracticeInsightCode.lowCompletion);
    }

    // 3. Dominant timing bias — needs paired evidence.
    final bias = context.timingBias;
    final pairedEvents = context.pairedEventCount;
    if (pairedEvents >= _biasMinPairedEvents && bias != null) {
      if (bias > Duration.zero) {
        final lateShare = context.lateShare ?? 0;
        if (lateShare >= _biasMinShare) {
          return const PracticeInsight(code: PracticeInsightCode.biasLate);
        }
      } else if (bias < Duration.zero) {
        final earlyShare = context.earlyShare ?? 0;
        if (earlyShare >= _biasMinShare) {
          return const PracticeInsight(code: PracticeInsightCode.biasEarly);
        }
      }
    }

    // 4. Direction error — the dim exists and is below threshold.
    final direction = _extractAvailable(metrics.direction);
    if (direction != null && direction < _directionErrorThreshold) {
      return const PracticeInsight(code: PracticeInsightCode.directionError);
    }

    // 5. Chord error — the dim exists and is below threshold.
    final chord = _extractAvailable(metrics.chord);
    if (chord != null && chord < _chordErrorThreshold) {
      // 5b. Down-rank to chord-pair problem when one pair dominates.
      final pair = context.slowestChordPair;
      if (pair != null &&
          pair.attempts >= _pairMinMeasurements &&
          pair.relativeDelayToFastest != null &&
          pair.relativeDelayToFastest! >= _pairMinRelativeDelay) {
        return const PracticeInsight(
          code: PracticeInsightCode.chordPairProblem,
        );
      }
      return const PracticeInsight(code: PracticeInsightCode.chordError);
    }

    // 6. Chord-pair problem — chord itself is fine but one pair is slow.
    final pair = context.slowestChordPair;
    if (pair != null &&
        pair.attempts >= _pairMinMeasurements &&
        pair.relativeDelayToFastest != null &&
        pair.relativeDelayToFastest! >= _pairMinRelativeDelay) {
      return const PracticeInsight(code: PracticeInsightCode.chordPairProblem);
    }

    // 7. Tempo too high — rhythm is bad AND tempo is up.
    final rhythm = _extractAvailable(metrics.rhythm);
    final tempo = result.highestStableTempo;
    if (rhythm != null &&
        rhythm < _rhythmErrorThreshold &&
        tempo != null &&
        tempo.bpm >= _tempoCeilingForTempoTooHigh) {
      return const PracticeInsight(
        code: PracticeInsightCode.tempoTooHigh,
        recommendationKind: PracticeRecommendationKind.reduceTempo,
      );
    }

    // 8. Positive reinforcement — every available dim is clean.
    if (_allAvailableAtLeast(metrics, _reinforcementThreshold)) {
      return const PracticeInsight(
        code: PracticeInsightCode.positiveReinforcement,
      );
    }

    // 9. Next-difficulty — every dim is at 0.85 AND the tempo ceiling is hit.
    if (_allAvailableAtLeast(metrics, _reinforcementThreshold) &&
        tempo != null &&
        tempo.bpm >= _tempoCeilingForNextDifficulty) {
      return const PracticeInsight(
        code: PracticeInsightCode.nextDifficulty,
        recommendationKind: PracticeRecommendationKind.nextDifficulty,
      );
    }

    // 10. Default — no specific story to tell. Per ADR 0084 §Döntés 9 the
    // fallback must NOT be empty praise: emit the "no signal" code, which
    // is the documented "no decisive story" branch.
    return const PracticeInsight(code: PracticeInsightCode.noSignal);
  }

  /// Returns the value of [MetricAvailable], or `null` otherwise.
  static double? _extractAvailable(MetricValue value) {
    return switch (value) {
      MetricAvailable(:final value) => value,
      MetricNotApplicable() => null,
      MetricInsufficientData() => null,
    };
  }

  /// True iff every Available dimension in [metrics] clears [threshold].
  /// NotApplicable and InsufficientData dimensions are ignored (the rule
  /// applies to the dimensions the mode actually scored).
  static bool _allAvailableAtLeast(PracticeMetrics metrics, double threshold) {
    final values = <MetricValue>[
      metrics.completion,
      metrics.rhythm,
      metrics.direction,
      metrics.chord,
      metrics.overall,
    ];
    var anyAvailable = false;
    for (final value in values) {
      final extracted = _extractAvailable(value);
      if (extracted == null) continue;
      anyAvailable = true;
      if (extracted < threshold) return false;
    }
    return anyAvailable;
  }
}

/// Inputs the [PracticeCoach] reads alongside the [presult.PracticeSessionResult].
///
/// All fields except [strumCount] and [pairedEventCount] are optional and
/// default to null/empty — the rules gate on absence, not on a default
/// value.
class PracticeSessionContext {
  const PracticeSessionContext({
    required this.strumCount,
    required this.pairedEventCount,
    this.timingBias,
    this.lateShare,
    this.earlyShare,
    this.slowestChordPair,
  });

  final int strumCount;

  /// Number of events the timing scorer could pair (target ↔ observation).
  /// Used to gate the bias insights — under 8 paired events is anecdotal.
  final int pairedEventCount;

  /// Signed average timing error (negative = early). Null when the session
  /// had no paired events.
  final Duration? timingBias;

  /// Share of paired events graded `late`, ∈ [0, 1]. Null when N/A.
  final double? lateShare;

  /// Share of paired events graded `early`, ∈ [0, 1]. Null when N/A.
  final double? earlyShare;

  /// The chord pair the analyzer flagged as the median-slowest, or `null`
  /// when the session has no chord-change data.
  final SlowestChordPair? slowestChordPair;
}

/// One chord pair the coach considers for the `chordPairProblem` insight.
class SlowestChordPair {
  const SlowestChordPair({
    required this.pairKey,
    required this.attempts,
    this.relativeDelayToFastest,
  });

  final String pairKey;
  final int attempts;

  /// `(slowest - fastest) / fastest` for the same mode's other pairs.
  /// `null` when only one pair was measured (no comparison to make).
  final double? relativeDelayToFastest;
}
