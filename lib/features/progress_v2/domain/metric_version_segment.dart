import 'progress_trend.dart';

/// One contiguous run of [ProgressTrendPoint]s sharing the same
/// `catalogVersion` (§5.5) — segmenting by version keeps a mérce
/// recalibration from ever reading as continuous, sudden improvement within
/// one line (A5).
final class MetricVersionSegment {
  factory MetricVersionSegment({
    required int catalogVersion,
    required List<ProgressTrendPoint> points,
  }) => MetricVersionSegment._(
    catalogVersion: catalogVersion,
    points: List.unmodifiable(points),
  );

  const MetricVersionSegment._({
    required this.catalogVersion,
    required this.points,
  });

  final int catalogVersion;
  final List<ProgressTrendPoint> points;
}

/// One sample tagged with the `catalogVersion` (`MasteryProgress
/// .catalogVersion`, §0.0.B/B8) it was measured under.
typedef VersionedTrendSample = ({int catalogVersion, ProgressTrendPoint point});

/// Groups [samples] (assumed already ordered by observation time) into
/// contiguous [MetricVersionSegment]s. A version boundary ALWAYS starts a new
/// segment, even if an earlier version number reappears later — it is never
/// merged back into an earlier segment of the same version (A5: a version
/// change must stay visibly its own section in the history, not blend back
/// into an older one).
List<MetricVersionSegment> segmentByCatalogVersion(
  List<VersionedTrendSample> samples,
) {
  final segments = <MetricVersionSegment>[];
  for (final sample in samples) {
    if (segments.isNotEmpty &&
        segments.last.catalogVersion == sample.catalogVersion) {
      final previous = segments.removeLast();
      segments.add(
        MetricVersionSegment(
          catalogVersion: previous.catalogVersion,
          points: [...previous.points, sample.point],
        ),
      );
    } else {
      segments.add(
        MetricVersionSegment(
          catalogVersion: sample.catalogVersion,
          points: [sample.point],
        ),
      );
    }
  }
  return List.unmodifiable(segments);
}
