import '../domain/analysis_document.dart';
import '../domain/comparison/analysis_comparison.dart';
import '../engine/comparison/compatibility_evaluator.dart';

/// Compares two persisted [AnalysisDocument]s metric-by-metric (ADR 0246
/// §1). Only metrics published under the exact same ID in both documents are
/// compared — a metric present in only one session has no before/after
/// pair and is simply not part of the result, never silently zero-filled.
final class CompareAnalysesUseCase {
  const CompareAnalysesUseCase();

  AnalysisComparison call({
    required AnalysisDocument before,
    required AnalysisDocument after,
  }) {
    final beforeById = {for (final metric in before.metrics) metric.id: metric};

    final comparisons = <MetricComparison>[
      for (final afterMetric in after.metrics)
        if (beforeById[afterMetric.id] case final beforeMetric?)
          CompatibilityEvaluator.compare(
            before: beforeMetric,
            after: afterMetric,
            beforeQuality: before.signalQuality,
            afterQuality: after.signalQuality,
            beforeProvenance: before.provenance,
            afterProvenance: after.provenance,
          ),
    ];

    return AnalysisComparison(
      beforeAnalysisId: before.id,
      afterAnalysisId: after.id,
      metrics: comparisons,
    );
  }
}
