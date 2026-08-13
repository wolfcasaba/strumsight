import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/comparison/analysis_comparison.dart';
import 'widgets/labels_adapter.dart';
import 'widgets/metric_delta_row.dart';

/// Renders an already-built [AnalysisComparison] (ADR 0246). This screen is
/// pure presentation: every compatibility/direction decision was already
/// made by `CompareAnalysesUseCase` + `CompatibilityEvaluator`; the screen
/// only formats and lays out the verdicts it is handed.
final class AnalysisCompareScreen extends StatelessWidget {
  const AnalysisCompareScreen({super.key, required this.comparison});

  final AnalysisComparison comparison;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = AppLocalizationsOverviewLabels(l10n);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.analysisCompareTitle)),
      body: SafeArea(
        child: comparison.metrics.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.analysisCompareEmpty),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: comparison.metrics.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) => MetricDeltaRow(
                  data: _rowData(comparison.metrics[index], l10n, labels),
                ),
              ),
      ),
    );
  }

  MetricDeltaRowData _rowData(
    MetricComparison metric,
    AppLocalizations l10n,
    AppLocalizationsOverviewLabels labels,
  ) {
    final directionLabel = switch (metric.direction) {
      MetricComparisonDirection.improved =>
        l10n.analysisCompareDirectionImproved,
      MetricComparisonDirection.regressed =>
        l10n.analysisCompareDirectionRegressed,
      MetricComparisonDirection.unchanged =>
        l10n.analysisCompareDirectionUnchanged,
      MetricComparisonDirection.inconclusive =>
        l10n.analysisCompareDirectionInconclusive,
    };
    final directionIcon = switch (metric.direction) {
      MetricComparisonDirection.improved => Icons.trending_up,
      MetricComparisonDirection.regressed => Icons.trending_down,
      MetricComparisonDirection.unchanged => Icons.trending_flat,
      MetricComparisonDirection.inconclusive => Icons.help_outline,
    };

    return MetricDeltaRowData(
      metricId: metric.metricId,
      metricLabel: labels.metricLabel(metric.metricId),
      directionLabel: directionLabel,
      directionIcon: directionIcon,
      beforeValueText: l10n.analysisCompareBeforeValue(
        _formatNumber(metric.beforeValue),
      ),
      afterValueText: l10n.analysisCompareAfterValue(
        _formatNumber(metric.afterValue),
      ),
      deltaText: l10n.analysisCompareDelta(_formatNumber(metric.absoluteDelta)),
      confidenceText: l10n.analysisCompareConfidence(
        (metric.confidence * 100).toStringAsFixed(0),
      ),
      sampleCountText: l10n.analysisCompareSampleCount(metric.sampleCount),
      isInconclusive: metric.isInconclusive,
      reasonText: metric.inconclusiveReason == null
          ? ''
          : _reasonText(metric.inconclusiveReason!, l10n),
    );
  }

  String _formatNumber(double? value) =>
      value == null ? '—' : value.toStringAsFixed(2);

  String _reasonText(
    ComparisonInconclusiveReason reason,
    AppLocalizations l10n,
  ) => switch (reason) {
    ComparisonInconclusiveReason.differentMetricId =>
      l10n.analysisCompareReasonDifferentMetricId,
    ComparisonInconclusiveReason.differentMetricVersion =>
      l10n.analysisCompareReasonDifferentMetricVersion,
    ComparisonInconclusiveReason.differentTarget =>
      l10n.analysisCompareReasonDifferentTarget,
    ComparisonInconclusiveReason.inputQualityDiverged =>
      l10n.analysisCompareReasonInputQualityDiverged,
    ComparisonInconclusiveReason.unsupportedValueType =>
      l10n.analysisCompareReasonUnsupportedValueType,
    ComparisonInconclusiveReason.missingValue =>
      l10n.analysisCompareReasonMissingValue,
    ComparisonInconclusiveReason.missingMetadata =>
      l10n.analysisCompareReasonMissingMetadata,
    ComparisonInconclusiveReason.descriptiveMetricNotComparable =>
      l10n.analysisCompareReasonDescriptiveMetricNotComparable,
  };
}
