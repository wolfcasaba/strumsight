import '../../domain/analysis_document.dart';
import '../../domain/analysis_metric.dart';
import '../../domain/comparison/analysis_trend.dart';
import 'compatibility_evaluator.dart';

/// Minimum compatible sessions before a trend line is drawn (ADR 0246 §3,
/// OD-02). Below this, [TrendAvailability.unavailable] — never a line
/// through one or two noisy points.
const int minimumSessionsForTrend = 3;

/// Robust outlier bound: points further than this many median absolute
/// deviations from the median are excluded from the trend line, but never
/// from the returned point list (ADR 0246 §3, OD-03). Inclusive — a point
/// exactly on the boundary stays in.
const double outlierMadThreshold = 3;

/// Builds a local, evidence-only trend for one metric across a set of
/// sessions (ADR 0246 §3, SDD §26.6). Entirely local: no network call, and
/// the line never reaches beyond the sessions given — the last point is
/// always the most recent session's own value, never a projected one.
abstract final class TrendBuilder {
  static AnalysisTrend build({
    required String metricId,
    required List<AnalysisDocument> sessions,
  }) {
    final sorted = [...sessions]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final pointsByVersion = <int, List<TrendPoint>>{};
    for (final document in sorted) {
      AnalysisMetricResult? metric;
      for (final candidate in document.metrics) {
        if (candidate.id == metricId) {
          metric = candidate;
          break;
        }
      }
      if (metric == null) continue;
      final value = numericMetricValue(metric.value);
      if (value == null) continue;
      pointsByVersion
          .putIfAbsent(metric.version, () => <TrendPoint>[])
          .add(
            TrendPoint(
              analysisId: document.id,
              timestamp: document.createdAt,
              value: value,
            ),
          );
    }

    final versionGroups =
        <MetricTrend>[
          for (final entry in pointsByVersion.entries)
            _buildVersionGroup(version: entry.key, rawPoints: entry.value),
        ]..sort((a, b) => a.metricVersion.compareTo(b.metricVersion));

    return AnalysisTrend(metricId: metricId, versionGroups: versionGroups);
  }

  static MetricTrend _buildVersionGroup({
    required int version,
    required List<TrendPoint> rawPoints,
  }) {
    if (rawPoints.length < minimumSessionsForTrend) {
      return MetricTrend(
        metricVersion: version,
        availability: TrendAvailability.unavailable,
        points: rawPoints,
      );
    }

    final values = [for (final point in rawPoints) point.value]..sort();
    final median = _median(values);
    final absoluteDeviations = [
      for (final value in values) (value - median).abs(),
    ]..sort();
    final mad = _median(absoluteDeviations);

    final points = <TrendPoint>[
      for (final point in rawPoints)
        if (mad > 0 && (point.value - median).abs() > outlierMadThreshold * mad)
          TrendPoint(
            analysisId: point.analysisId,
            timestamp: point.timestamp,
            value: point.value,
            excluded: true,
          )
        else
          point,
    ];

    return MetricTrend(
      metricVersion: version,
      availability: TrendAvailability.available,
      points: points,
    );
  }

  static double _median(List<double> sortedValues) {
    final count = sortedValues.length;
    if (count.isOdd) return sortedValues[count ~/ 2];
    return (sortedValues[count ~/ 2 - 1] + sortedValues[count ~/ 2]) / 2;
  }
}
