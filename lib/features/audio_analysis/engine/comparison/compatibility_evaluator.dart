import 'dart:math' as math;

import '../../domain/analysis_metric.dart';
import '../../domain/analysis_metric_catalog.dart';
import '../../domain/analysis_provenance.dart';
import '../../domain/comparison/analysis_comparison.dart';
import '../../domain/comparison/metric_metadata.dart';
import '../../domain/signal_quality_report.dart';

/// Coarse signal-quality bucket used only for cross-session compatibility
/// (ADR 0246 §1, OD-01) — never shown to the user as a quality score; that
/// remains the raw [SignalQualityReport] fields the overview screen formats.
enum SignalQualityGrade { excellent, good, fair, poor }

const double _qualityGradeExcellentThreshold = 0.85;
const double _qualityGradeGoodThreshold = 0.65;
const double _qualityGradeFairThreshold = 0.4;

/// Inclusive: a noise-floor gap of exactly this many dB is still compatible
/// (ADR 0246 §1, OD-01; brief §6 threshold-triple: 9.9/10.0/10.1 dB).
const double noiseFloorCompatibilityThresholdDbfs = 10;

/// Extracts a plain comparable number from a metric's published value, in
/// the unit [MetricMetadata.minimumMeaningfulDelta] is expressed in:
/// milliseconds for durations, the raw ratio for percentages, the raw
/// number otherwise. Returns null for value types comparison does not (yet)
/// support (distributions, time series, categories) or when no value was
/// published at all.
double? numericMetricValue(AnalysisMetricValue? value) => switch (value) {
  null => null,
  ScalarMetricValue v => v.value,
  PercentageMetricValue v => v.value,
  DurationMetricValue v => v.value.inMicroseconds / 1000,
  ScoreMetricValue v => v.value,
  DistributionMetricValue _ => null,
  TimeSeriesMetricValue _ => null,
  CategoryMetricValue _ => null,
};

/// Evaluates whether two sessions' metrics are comparable at all, and if so,
/// resolves the direction verdict (ADR 0246 §1–§2).
///
/// Fail-closed by construction: every early-return path here produces
/// `inconclusive` with a named reason. There is no "compare anyway, but
/// flag it" branch — an incompatible pair is never shown as if it were
/// compatible (SDD §26.1).
abstract final class CompatibilityEvaluator {
  static SignalQualityGrade gradeOf(SignalQualityReport report) {
    final overall = report.overall;
    if (overall >= _qualityGradeExcellentThreshold) {
      return SignalQualityGrade.excellent;
    }
    if (overall >= _qualityGradeGoodThreshold) return SignalQualityGrade.good;
    if (overall >= _qualityGradeFairThreshold) return SignalQualityGrade.fair;
    return SignalQualityGrade.poor;
  }

  static bool _isClipped(SignalQualityReport report) =>
      report.clippedSampleRatio > 0;

  /// Pure metric-identity compatibility, decoupled from
  /// [AnalysisMetricResult]'s constructor (which always couples `id` and
  /// `version` 1:1, so two *real* results can never share an id with
  /// different versions). This keeps "different metric" and "different
  /// metric version" independently testable ahead of a future metric
  /// version bump (ADR 0218).
  static ComparisonInconclusiveReason? compareMetricIdentity({
    required String idA,
    required int versionA,
    required String idB,
    required int versionB,
  }) {
    if (idA == idB) return null;
    if (_baseId(idA) == _baseId(idB)) {
      return ComparisonInconclusiveReason.differentMetricVersion;
    }
    return ComparisonInconclusiveReason.differentMetricId;
  }

  static String _baseId(String id) {
    final index = id.lastIndexOf('.v');
    return index == -1 ? id : id.substring(0, index);
  }

  /// Compatibility-only check (no direction resolution). Exposed
  /// separately so the nine-cell compatibility matrix can be tested without
  /// also depending on [MetricMetadata] being registered for the id.
  static ComparisonInconclusiveReason? evaluateCompatibility({
    required AnalysisMetricResult before,
    required AnalysisMetricResult after,
    required SignalQualityReport beforeQuality,
    required SignalQualityReport afterQuality,
    required AnalysisProvenance beforeProvenance,
    required AnalysisProvenance afterProvenance,
  }) {
    final identity = compareMetricIdentity(
      idA: before.id,
      versionA: before.version,
      idB: after.id,
      versionB: after.version,
    );
    if (identity != null) return identity;

    if (beforeProvenance.targetVersion != afterProvenance.targetVersion) {
      return ComparisonInconclusiveReason.differentTarget;
    }

    if (_isClipped(beforeQuality) != _isClipped(afterQuality)) {
      return ComparisonInconclusiveReason.inputQualityDiverged;
    }
    if (gradeOf(beforeQuality) != gradeOf(afterQuality)) {
      return ComparisonInconclusiveReason.inputQualityDiverged;
    }
    final noiseFloorDelta =
        (beforeQuality.noiseFloorDbfs - afterQuality.noiseFloorDbfs).abs();
    if (noiseFloorDelta > noiseFloorCompatibilityThresholdDbfs) {
      return ComparisonInconclusiveReason.inputQualityDiverged;
    }

    // Dynamics evidence is only comparable under a matching DSP
    // configuration (normalization/gain policy, clipping handling) — SDD
    // §16.3. dspConfigHash is the existing reproducibility fingerprint for
    // exactly that configuration (ADR 0246 §1).
    if (DynamicsMetricIds.all.contains(before.id) &&
        beforeProvenance.dspConfigHash != afterProvenance.dspConfigHash) {
      return ComparisonInconclusiveReason.inputQualityDiverged;
    }

    return null;
  }

  /// Full comparison for one metric: compatibility first, then (only if
  /// compatible) the direction verdict from [MetricMetadataCatalog].
  static MetricComparison compare({
    required AnalysisMetricResult before,
    required AnalysisMetricResult after,
    required SignalQualityReport beforeQuality,
    required SignalQualityReport afterQuality,
    required AnalysisProvenance beforeProvenance,
    required AnalysisProvenance afterProvenance,
  }) {
    final confidence = math.min(before.confidence, after.confidence);
    final sampleCount = before.sampleCount < after.sampleCount
        ? before.sampleCount
        : after.sampleCount;

    final incompatibility = evaluateCompatibility(
      before: before,
      after: after,
      beforeQuality: beforeQuality,
      afterQuality: afterQuality,
      beforeProvenance: beforeProvenance,
      afterProvenance: afterProvenance,
    );
    if (incompatibility != null) {
      return MetricComparison(
        metricId: after.id,
        direction: MetricComparisonDirection.inconclusive,
        confidence: confidence,
        sampleCount: sampleCount,
        inconclusiveReason: incompatibility,
      );
    }

    final metadata = MetricMetadataCatalog.forId(after.id);
    if (metadata == null) {
      return MetricComparison(
        metricId: after.id,
        direction: MetricComparisonDirection.inconclusive,
        confidence: confidence,
        sampleCount: sampleCount,
        inconclusiveReason: ComparisonInconclusiveReason.missingMetadata,
      );
    }

    final beforeValue = numericMetricValue(before.value);
    final afterValue = numericMetricValue(after.value);
    if (beforeValue == null || afterValue == null) {
      final reason = before.value == null || after.value == null
          ? ComparisonInconclusiveReason.missingValue
          : ComparisonInconclusiveReason.unsupportedValueType;
      return MetricComparison(
        metricId: after.id,
        direction: MetricComparisonDirection.inconclusive,
        confidence: confidence,
        sampleCount: sampleCount,
        beforeValue: beforeValue,
        afterValue: afterValue,
        inconclusiveReason: reason,
      );
    }

    final absoluteDelta = afterValue - beforeValue;
    final direction = _resolveDirection(metadata, beforeValue, afterValue);
    final relativeDelta = beforeValue != 0
        ? absoluteDelta / beforeValue.abs()
        : null;

    return MetricComparison(
      metricId: after.id,
      direction: direction,
      confidence: confidence,
      sampleCount: sampleCount,
      beforeValue: beforeValue,
      afterValue: afterValue,
      absoluteDelta: absoluteDelta,
      relativeDelta: relativeDelta,
      inconclusiveReason: direction == MetricComparisonDirection.inconclusive
          ? ComparisonInconclusiveReason.descriptiveMetricNotComparable
          : null,
    );
  }

  static MetricComparisonDirection _resolveDirection(
    MetricMetadata metadata,
    double before,
    double after,
  ) {
    if (metadata.direction == MetricDirection.targetRange) {
      return _resolveTargetRangeDirection(metadata, before, after);
    }

    final absoluteDelta = (after - before).abs();
    if (absoluteDelta < metadata.minimumMeaningfulDelta) {
      return MetricComparisonDirection.unchanged;
    }

    if (metadata.direction == MetricDirection.descriptive) {
      // A descriptive metric may move by a meaningful amount, but that
      // movement is never framed as improved/regressed (SDD §26.4).
      return MetricComparisonDirection.inconclusive;
    }

    final delta = after - before;
    final improved = metadata.direction == MetricDirection.lowerIsBetter
        ? delta < 0
        : delta > 0;
    return improved
        ? MetricComparisonDirection.improved
        : MetricComparisonDirection.regressed;
  }

  static MetricComparisonDirection _resolveTargetRangeDirection(
    MetricMetadata metadata,
    double before,
    double after,
  ) {
    final min = metadata.targetRangeMin!;
    final max = metadata.targetRangeMax!;
    double distanceToRange(double value) {
      if (value < min) return min - value;
      if (value > max) return value - max;
      return 0;
    }

    final beforeDistance = distanceToRange(before);
    final afterDistance = distanceToRange(after);
    final deltaDistance = afterDistance - beforeDistance;
    if (deltaDistance.abs() < metadata.minimumMeaningfulDelta) {
      return MetricComparisonDirection.unchanged;
    }
    return deltaDistance < 0
        ? MetricComparisonDirection.improved
        : MetricComparisonDirection.regressed;
  }
}
