import 'package:meta/meta.dart';

import 'practice_metrics.dart';
import 'practice_value_equality.dart';

/// One detected BPM sample surfaced for the Free Practice view.
///
/// [bpm] is what the Gateway surfaced (already filtered through the Tempo
/// range). [at] is the moment of the sample on the active-time clock.
@immutable
final class FreePracticeBpmSample {
  const FreePracticeBpmSample({required this.bpm, required this.at});

  final double bpm;
  final Duration at;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreePracticeBpmSample && other.bpm == bpm && other.at == at;

  @override
  int get hashCode => Object.hash(bpm, at);
}

/// One explicit segment of the observed chord timeline.
///
/// A segment carries either the canonical chord label that was observed, or
/// `null` for the *"no chord detected"* span — the brief explicitly bans
/// silently dropping the null runs.
@immutable
final class FreePracticeChordSegment {
  const FreePracticeChordSegment({required this.label, required this.duration});

  /// Canonical chord label, or `null` for the "no chord" segment.
  final String? label;
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreePracticeChordSegment &&
          other.label == label &&
          other.duration == duration;

  @override
  int get hashCode => Object.hash(label, duration);
}

/// Tempo-stability metric computed from the observed inter-strum intervals.
///
/// `InsufficientData` is the only acceptable response when fewer than four
/// strums were observed (three intervals). Otherwise the value is the
/// median-absolute-deviation-around-the-median of the interval set, in
/// milliseconds — outlier-tolerant by design (ADR 0082 §3).
@immutable
sealed class FreePracticeTempoStability {
  const FreePracticeTempoStability();
}

@immutable
final class FreePracticeTempoStabilityAvailable
    extends FreePracticeTempoStability {
  const FreePracticeTempoStabilityAvailable(this.deviation);

  /// Median absolute deviation around the interval median, in milliseconds.
  final Duration deviation;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreePracticeTempoStabilityAvailable &&
          other.deviation == deviation;

  @override
  int get hashCode => Object.hash(runtimeType, deviation);
}

@immutable
final class FreePracticeTempoStabilityInsufficientData
    extends FreePracticeTempoStability {
  const FreePracticeTempoStabilityInsufficientData();

  @override
  bool operator ==(Object other) =>
      other is FreePracticeTempoStabilityInsufficientData;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Direction ratio metric.
///
/// `null` label = no direction information was observed (Rhythm-only with
/// direction-less events). `InsufficientData` = observations existed but the
/// ratio would divide by zero (zero strums).
@immutable
sealed class FreePracticeDirectionRatio {
  const FreePracticeDirectionRatio();
}

@immutable
final class FreePracticeDirectionRatioAvailable
    extends FreePracticeDirectionRatio {
  const FreePracticeDirectionRatioAvailable({
    required this.downCount,
    required this.upCount,
    required this.downRatio,
    required this.upRatio,
  });

  final int downCount;
  final int upCount;

  /// `downCount / strumCount` in [0, 1].
  final double downRatio;

  /// `upCount / strumCount` in [0, 1].
  final double upRatio;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreePracticeDirectionRatioAvailable &&
          other.downCount == downCount &&
          other.upCount == upCount &&
          other.downRatio == downRatio &&
          other.upRatio == upRatio;

  @override
  int get hashCode => Object.hash(downCount, upCount, downRatio, upRatio);
}

/// Direction is inapplicable: the definition carried no direction info.
@immutable
final class FreePracticeDirectionRatioNotApplicable
    extends FreePracticeDirectionRatio {
  const FreePracticeDirectionRatioNotApplicable();

  @override
  bool operator ==(Object other) =>
      other is FreePracticeDirectionRatioNotApplicable;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Direction had no observations (zero strums).
@immutable
final class FreePracticeDirectionRatioInsufficientData
    extends FreePracticeDirectionRatio {
  const FreePracticeDirectionRatioInsufficientData();

  @override
  bool operator ==(Object other) =>
      other is FreePracticeDirectionRatioInsufficientData;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Score-free summary of one Free Practice session.
///
/// The summary contains **only facts** observed during the run: counts,
/// ratios, timeline, and detected meter. It never carries a score, verdict,
/// or pass/fail outcome — those fields exist only on the legacy
/// `PracticeAttemptResult` and are deliberately absent here (ADR 0082 §1).
@immutable
final class FreePracticeSummary {
  FreePracticeSummary({
    required this.strumCount,
    required this.activeDuration,
    required Duration chordTimelineDuration,
    required List<FreePracticeChordSegment> chordTimeline,
    required List<FreePracticeBpmSample> bpmSamples,
    required this.tempoStability,
    required this.directionRatio,
  }) : chordTimeline = List<FreePracticeChordSegment>.unmodifiable(
         chordTimeline,
       ),
       chordTimelineDuration = chordTimelineDuration < Duration.zero
           ? Duration.zero
           : chordTimelineDuration,
       bpmSamples = List<FreePracticeBpmSample>.unmodifiable(bpmSamples);

  /// Total number of strum observations counted.
  final int strumCount;

  /// Active time (`playingElapsed`) accumulated during the session.
  final Duration activeDuration;

  /// Sum of the chord-timeline segment durations. The contract
  /// (A9 §5) is `chordTimelineDuration <= activeDuration`.
  final Duration chordTimelineDuration;

  /// Ordered chord segments covering the observed chord timeline.
  final List<FreePracticeChordSegment> chordTimeline;

  /// Detected BPM samples (one per gateway emission, BPM > 0).
  final List<FreePracticeBpmSample> bpmSamples;

  /// Tempo stability — `InsufficientData` for fewer than four strums.
  final FreePracticeTempoStability tempoStability;

  /// Direction ratio — `NotApplicable` when the definition is direction-less,
  /// `InsufficientData` when zero strums were observed.
  final FreePracticeDirectionRatio directionRatio;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreePracticeSummary &&
          other.strumCount == strumCount &&
          other.activeDuration == activeDuration &&
          other.chordTimelineDuration == chordTimelineDuration &&
          listEquals(other.chordTimeline, chordTimeline) &&
          listEquals(other.bpmSamples, bpmSamples) &&
          other.tempoStability == tempoStability &&
          other.directionRatio == directionRatio;

  @override
  int get hashCode => Object.hash(
    strumCount,
    activeDuration,
    chordTimelineDuration,
    listHash(chordTimeline),
    listHash(bpmSamples),
    tempoStability,
    directionRatio,
  );
}

/// Aggregates the result of summarizing a Free Practice run with the
/// scoring-pipeline-compatible [PracticeMetrics] snapshot built by the
/// existing R10 aggregator (whose `overall` is `MetricNotApplicable` for
/// the `freePracticeOpen` profile).
@immutable
final class FreePracticeSummaryBundle {
  const FreePracticeSummaryBundle({
    required this.summary,
    required this.metrics,
  });

  final FreePracticeSummary summary;
  final PracticeMetrics metrics;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreePracticeSummaryBundle &&
          other.summary == summary &&
          other.metrics == metrics;

  @override
  int get hashCode => Object.hash(summary, metrics);
}
