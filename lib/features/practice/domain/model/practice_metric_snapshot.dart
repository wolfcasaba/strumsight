import 'package:meta/meta.dart';

import 'practice_metrics.dart';
import 'practice_validation.dart';

/// A persisted, comparable snapshot of one attempt's metric values.
///
/// The attempt's [MetricValue]s are sealed — Available / NotApplicable /
/// InsufficientData — so each dimension is preserved as one of three kinds
/// (a normalised `double` ∈ [0,1], a sealed `MetricNotApplicable` marker,
/// or an insufficient-data reason code). Storing the *kind* is what makes
/// the result screen's "el nem érhető dimenzió ≠ 0%" rule survive a save
/// and a load (ADR 0084 §Döntés 10).
@immutable
final class PracticeMetricSnapshot {
  const PracticeMetricSnapshot({
    required this.completion,
    required this.rhythm,
    required this.direction,
    required this.chord,
    required this.overall,
  });

  final PracticeMetricDimension completion;
  final PracticeMetricDimension rhythm;
  final PracticeMetricDimension direction;
  final PracticeMetricDimension chord;
  final PracticeMetricDimension overall;

  /// Builds a snapshot from a live [PracticeMetrics] (controller-side).
  factory PracticeMetricSnapshot.fromMetrics(PracticeMetrics metrics) {
    return PracticeMetricSnapshot(
      completion: PracticeMetricDimension.fromMetricValue(metrics.completion),
      rhythm: PracticeMetricDimension.fromMetricValue(metrics.rhythm),
      direction: PracticeMetricDimension.fromMetricValue(metrics.direction),
      chord: PracticeMetricDimension.fromMetricValue(metrics.chord),
      overall: PracticeMetricDimension.fromMetricValue(metrics.overall),
    );
  }

  List<PracticeValidationFailure> validate() {
    return <PracticeValidationFailure>[
      ...completion.validate(),
      ...rhythm.validate(),
      ...direction.validate(),
      ...chord.validate(),
      ...overall.validate(),
    ];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeMetricSnapshot &&
          other.completion == completion &&
          other.rhythm == rhythm &&
          other.direction == direction &&
          other.chord == chord &&
          other.overall == overall;

  @override
  int get hashCode =>
      Object.hash(completion, rhythm, direction, chord, overall);
}

/// One persisted practice-metric dimension.
///
/// Sealed by construction: a [PracticeMetricSnapshot] never silently
/// substitutes 0.0 for an inapplicable dimension, and never substitutes a
/// percentage for an "insufficient data" condition. The result screen
/// renders exactly what this carries.
@immutable
sealed class PracticeMetricDimension {
  const PracticeMetricDimension();

  /// Stable kind name for persistence / pattern matching.
  String get kind;

  factory PracticeMetricDimension.fromMetricValue(MetricValue value) {
    return switch (value) {
      MetricAvailable(:final value) => PracticeMetricDimensionAvailable(value),
      MetricNotApplicable() => const PracticeMetricDimensionNotApplicable(),
      MetricInsufficientData(:final reasonCode) =>
        PracticeMetricDimensionInsufficientData(reasonCode),
    };
  }

  factory PracticeMetricDimension.available(double value) =>
      PracticeMetricDimensionAvailable(value);

  factory PracticeMetricDimension.notApplicable() =>
      const PracticeMetricDimensionNotApplicable();

  factory PracticeMetricDimension.insufficientData(String reasonCode) =>
      PracticeMetricDimensionInsufficientData(reasonCode);

  /// Resolves the [MetricValue] counterpart for the controller.
  MetricValue toMetricValue();

  List<PracticeValidationFailure> validate();
}

@immutable
final class PracticeMetricDimensionAvailable extends PracticeMetricDimension {
  const PracticeMetricDimensionAvailable(this.value);
  final double value;

  @override
  String get kind => 'available';

  @override
  MetricValue toMetricValue() => MetricAvailable(value);

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
      other is PracticeMetricDimensionAvailable && other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);
}

@immutable
final class PracticeMetricDimensionNotApplicable
    extends PracticeMetricDimension {
  const PracticeMetricDimensionNotApplicable();

  @override
  String get kind => 'notApplicable';

  @override
  MetricValue toMetricValue() => const MetricNotApplicable();

  @override
  List<PracticeValidationFailure> validate() => const [];

  @override
  bool operator ==(Object other) =>
      other is PracticeMetricDimensionNotApplicable;

  @override
  int get hashCode => runtimeType.hashCode;
}

@immutable
final class PracticeMetricDimensionInsufficientData
    extends PracticeMetricDimension {
  const PracticeMetricDimensionInsufficientData(this.reasonCode);
  final String reasonCode;

  @override
  String get kind => 'insufficientData';

  @override
  MetricValue toMetricValue() => MetricInsufficientData(reasonCode);

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
      other is PracticeMetricDimensionInsufficientData &&
          other.reasonCode == reasonCode;

  @override
  int get hashCode => Object.hash(runtimeType, reasonCode);
}
