import 'package:meta/meta.dart';

import 'practice_validation.dart';

/// Explicitly available or unavailable state of one normalized metric.
@immutable
sealed class MetricValue {
  const MetricValue();

  /// Returns every validation problem for this metric state.
  List<PracticeValidationFailure> validate();
}

/// A normalized metric that could be calculated.
@immutable
final class MetricAvailable extends MetricValue {
  const MetricAvailable(this.value);

  final double value;

  @override
  List<PracticeValidationFailure> validate() {
    if (!value.isFinite) {
      return const [
        PracticeValidationFailure(
          code: PracticeValidationCode.metricValueNotFinite,
          message: 'Metric value must be finite.',
        ),
      ];
    }
    if (value < 0 || value > 1) {
      return const [
        PracticeValidationFailure(
          code: PracticeValidationCode.metricValueOutOfRange,
          message: 'Metric value must be between zero and one.',
        ),
      ];
    }
    return const [];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MetricAvailable && other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);
}

/// A metric that does not apply to the selected practice mode.
@immutable
final class MetricNotApplicable extends MetricValue {
  const MetricNotApplicable();

  @override
  List<PracticeValidationFailure> validate() => const [];

  @override
  bool operator ==(Object other) => other is MetricNotApplicable;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// A metric that applies but could not be calculated from the available data.
@immutable
final class MetricInsufficientData extends MetricValue {
  const MetricInsufficientData(this.reasonCode);

  final String reasonCode;

  @override
  List<PracticeValidationFailure> validate() {
    if (reasonCode.isEmpty) {
      return const [
        PracticeValidationFailure(
          code: PracticeValidationCode.metricInsufficientDataReasonEmpty,
          message: 'Insufficient-data metric requires a reason code.',
        ),
      ];
    }
    return const [];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MetricInsufficientData && other.reasonCode == reasonCode;

  @override
  int get hashCode => Object.hash(runtimeType, reasonCode);
}

/// Aggregated metrics and counters for one practice attempt.
@immutable
final class PracticeMetrics {
  const PracticeMetrics({
    required this.completion,
    required this.rhythm,
    required this.direction,
    required this.chord,
    required this.overall,
    required this.totalTargets,
    required this.resolvedTargets,
    required this.maxCombo,
    required this.scorePoints,
    required this.meanAbsoluteOffset,
    required this.timingBias,
  });

  final MetricValue completion;
  final MetricValue rhythm;
  final MetricValue direction;
  final MetricValue chord;
  final MetricValue overall;
  final int totalTargets;
  final int resolvedTargets;
  final int maxCombo;
  final int scorePoints;
  final Duration meanAbsoluteOffset;

  /// Signed average timing error; negative values represent early input.
  final Duration timingBias;

  /// Returns every nested and aggregate validation problem.
  List<PracticeValidationFailure> validate() {
    final failures = <PracticeValidationFailure>[
      ...completion.validate(),
      ...rhythm.validate(),
      ...direction.validate(),
      ...chord.validate(),
      ...overall.validate(),
    ];
    if (totalTargets < 0) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.metricsTotalTargetsNegative,
          message: 'Total target count cannot be negative.',
        ),
      );
    }
    if (resolvedTargets > totalTargets) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.metricsResolvedTargetsExceedsTotal,
          message: 'Resolved target count cannot exceed total targets.',
        ),
      );
    }
    if (maxCombo < 0) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.metricsMaxComboNegative,
          message: 'Maximum combo cannot be negative.',
        ),
      );
    }
    if (scorePoints < 0) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.metricsScorePointsNegative,
          message: 'Score points cannot be negative.',
        ),
      );
    }
    if (meanAbsoluteOffset < Duration.zero) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.metricsMeanAbsoluteOffsetNegative,
          message: 'Mean absolute timing offset cannot be negative.',
        ),
      );
    }
    return List.unmodifiable(failures);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeMetrics &&
          other.completion == completion &&
          other.rhythm == rhythm &&
          other.direction == direction &&
          other.chord == chord &&
          other.overall == overall &&
          other.totalTargets == totalTargets &&
          other.resolvedTargets == resolvedTargets &&
          other.maxCombo == maxCombo &&
          other.scorePoints == scorePoints &&
          other.meanAbsoluteOffset == meanAbsoluteOffset &&
          other.timingBias == timingBias;

  @override
  int get hashCode => Object.hash(
    completion,
    rhythm,
    direction,
    chord,
    overall,
    totalTargets,
    resolvedTargets,
    maxCombo,
    scorePoints,
    meanAbsoluteOffset,
    timingBias,
  );
}

/// Stable reason codes for unavailable practice scoring dimensions.
abstract final class PracticeMetricReasonCode {
  static const String noSignal = 'practice.metric.no_signal';
  static const String noApplicableTargets =
      'practice.metric.no_applicable_targets';
  static const String chordUnstable = 'practice.metric.chord_unstable';
  static const String insufficientSamples =
      'practice.metric.insufficient_samples';

  static const Set<String> values = {
    noSignal,
    noApplicableTargets,
    chordUnstable,
    insufficientSamples,
  };
}
