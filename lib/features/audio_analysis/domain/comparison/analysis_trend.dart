/// Whether a metric trend could be built at all (ADR 0246 §3, OD-02).
enum TrendAvailability { available, unavailable }

/// One session's value on a metric trend line.
///
/// [excluded] marks a statistical outlier (ADR 0246 §3, OD-03): the point is
/// still returned here — the trend never silently drops evidence — but it is
/// left out of [MetricTrend.includedPoints], the set the trend line itself
/// is drawn from.
final class TrendPoint {
  TrendPoint({
    required this.analysisId,
    required this.timestamp,
    required this.value,
    this.excluded = false,
  }) {
    if (analysisId.trim().isEmpty) {
      throw ArgumentError.value(analysisId, 'analysisId');
    }
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value');
    }
  }

  final String analysisId;
  final DateTime timestamp;
  final double value;
  final bool excluded;
}

/// One metric's trend within a single metric-version group (ADR 0246 §3).
/// Sessions published under a different metric version never mix into the
/// same [MetricTrend] — see [AnalysisTrend.versionGroups].
final class MetricTrend {
  MetricTrend({
    required this.metricVersion,
    required this.availability,
    required List<TrendPoint> points,
  }) : points = List<TrendPoint>.unmodifiable(points) {
    if (metricVersion < 1) {
      throw ArgumentError.value(metricVersion, 'metricVersion');
    }
  }

  final int metricVersion;
  final TrendAvailability availability;

  /// Every compatible session's point, in chronological order — including
  /// excluded outliers, so the UI can render them as visible-but-excluded.
  final List<TrendPoint> points;

  /// The points the trend line itself is computed from (excludes outliers).
  List<TrendPoint> get includedPoints =>
      List<TrendPoint>.unmodifiable(points.where((point) => !point.excluded));
}

/// One metric's trend across every compatible session, grouped by the
/// metric's published version (ADR 0246 §3). There is no cross-version
/// trend line — a version bump is a new metric definition, not a
/// continuation of the old one.
final class AnalysisTrend {
  AnalysisTrend({required this.metricId, required List<MetricTrend> versionGroups})
    : versionGroups = List<MetricTrend>.unmodifiable(versionGroups);

  final String metricId;
  final List<MetricTrend> versionGroups;
}
