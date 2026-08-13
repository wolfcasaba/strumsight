/// Why one metric could not be compared, or why a direction verdict could
/// not be reached (ADR 0246 §1). Never a generic "incompatible" bucket —
/// each reason is a distinct, user-explainable cause.
enum ComparisonInconclusiveReason {
  differentMetricId,
  differentMetricVersion,
  differentTarget,
  inputQualityDiverged,
  unsupportedValueType,
  missingValue,
  missingMetadata,
  descriptiveMetricNotComparable,
}

/// Verdict for one metric's before/after movement (ADR 0246 §2). Only
/// [improved]/[regressed] imply a preferred direction; [unchanged] means the
/// delta was below the metric's meaningful threshold; [inconclusive] means
/// no verdict could be produced at all (see [ComparisonInconclusiveReason]).
enum MetricComparisonDirection { improved, regressed, unchanged, inconclusive }

/// One metric's before/after comparison result.
///
/// [beforeValue]/[afterValue]/[absoluteDelta]/[relativeDelta] are null when
/// the metric could not be compared numerically (e.g. incompatible sessions,
/// unsupported value type, or a missing value on either side) — an explicit
/// absence, never a fabricated zero.
final class MetricComparison {
  MetricComparison({
    required this.metricId,
    required this.direction,
    required this.confidence,
    required this.sampleCount,
    this.beforeValue,
    this.afterValue,
    this.absoluteDelta,
    this.relativeDelta,
    this.inconclusiveReason,
  }) {
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence');
    }
    if (sampleCount < 0) {
      throw ArgumentError.value(sampleCount, 'sampleCount');
    }
    if (direction == MetricComparisonDirection.inconclusive &&
        inconclusiveReason == null) {
      throw ArgumentError(
        'An inconclusive comparison requires an explanation.',
      );
    }
  }

  final String metricId;
  final MetricComparisonDirection direction;

  /// The lower of the two sessions' published confidences — a comparison is
  /// never more confident than its least-confident input.
  final double confidence;

  /// The lower of the two sessions' published sample counts, for the same
  /// reason.
  final int sampleCount;

  final double? beforeValue;
  final double? afterValue;
  final double? absoluteDelta;
  final double? relativeDelta;
  final ComparisonInconclusiveReason? inconclusiveReason;

  bool get isInconclusive =>
      direction == MetricComparisonDirection.inconclusive;
}

/// One before/after session comparison — a bag of per-metric verdicts, each
/// independently compatible or inconclusive (ADR 0246 §1). There is no
/// document-wide "comparable" boolean: comparability is always per-metric.
final class AnalysisComparison {
  AnalysisComparison({
    required this.beforeAnalysisId,
    required this.afterAnalysisId,
    required List<MetricComparison> metrics,
  }) : metrics = List<MetricComparison>.unmodifiable(metrics) {
    if (beforeAnalysisId.trim().isEmpty) {
      throw ArgumentError.value(beforeAnalysisId, 'beforeAnalysisId');
    }
    if (afterAnalysisId.trim().isEmpty) {
      throw ArgumentError.value(afterAnalysisId, 'afterAnalysisId');
    }
  }

  final String beforeAnalysisId;
  final String afterAnalysisId;
  final List<MetricComparison> metrics;
}
