/// One measured sample in a progress trend series, already projected to a
/// plain numeric value by the caller (§0.0.B/B7 — this feature never reads a
/// repository or computes from raw evidence itself).
final class ProgressTrendPoint {
  const ProgressTrendPoint({required this.observedAt, required this.value});

  final DateTime observedAt;

  /// A `[0, 1]` ratio (e.g. accuracy) at [observedAt].
  final double value;
}

/// Whether a [ProgressTrend] has enough points to justify drawing one.
enum ProgressTrendAvailability { insufficientData, available }

/// The minimum number of distinct data points before a trend is drawn
/// (inclusive boundary) — merge-elt ADR 0289 §4, measured ONLY against this
/// feature's own [ProgressTrendPoint] input.
///
/// Deliberately NOT
/// `lib/features/audio_analysis/engine/comparison/trend_builder.dart`'s
/// `minimumSessionsForTrend` (3): that constant gates a different surface's
/// input (`AnalysisDocument` metric comparisons) and is neither imported nor
/// copied here (§0.0.B/B3) — importing it would let 3 progress data points
/// draw a trend where the round's mérce-mátrix requires "still not enough
/// data" (brief §6.1).
abstract final class ProgressTrendThresholds {
  static const int minimumDataPointsForTrend = 5;
}

/// A trend series and its derived [availability] — computed once at
/// construction so every consumer reads the same verdict (A4). [points] is
/// assumed already ordered by [ProgressTrendPoint.observedAt] (mirrors
/// `segmentByCatalogVersion`'s precondition) — direction is read from
/// `points.first`/`points.last`, and this constructor does not sort.
final class ProgressTrend {
  factory ProgressTrend({required List<ProgressTrendPoint> points}) {
    final fixed = List<ProgressTrendPoint>.unmodifiable(points);
    final availability =
        fixed.length >= ProgressTrendThresholds.minimumDataPointsForTrend
        ? ProgressTrendAvailability.available
        : ProgressTrendAvailability.insufficientData;
    return ProgressTrend._(points: fixed, availability: availability);
  }

  const ProgressTrend._({required this.points, required this.availability});

  final List<ProgressTrendPoint> points;
  final ProgressTrendAvailability availability;

  bool get hasTrend => availability == ProgressTrendAvailability.available;
}
