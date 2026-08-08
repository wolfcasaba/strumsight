import '../geometry/geometry_confidence.dart';
import '../metrics/fretting_metrics.dart';
import '../metrics/metric_definition.dart';
import '../metrics/metric_observation.dart';
import '../metrics/picking_metrics.dart';
import '../metrics/posture_metrics.dart';
import '../quality/vision_frame_quality.dart';
import '../sync/sync_quality.dart';
import 'evidence_provenance.dart';

/// The three production metric catalogs that can feed evidence fusion.
enum EvidenceMetricFamily { fretting, picking, posture }

/// A metric's existing catalog contract, normalized for the fusion boundary.
///
/// The window always originates in the production metric definition; fusion
/// owns only its additional observation-count, duration, and gap thresholds.
final class EvidenceMetric {
  const EvidenceMetric._({
    required this.family,
    required this.id,
    required this.window,
    required this.minimumVisibility,
    required this.requiresGeometry,
  });

  factory EvidenceMetric.fretting(FrettingMetricId id) {
    final definition = FrettingMetrics.definitions.firstWhere(
      (definition) => definition.id == id,
    );
    return EvidenceMetric._(
      family: EvidenceMetricFamily.fretting,
      id: id.name,
      window: definition.window,
      minimumVisibility: definition.minimumVisibility,
      requiresGeometry:
          definition.requiredCapability ==
          FrettingCapability.guitarRelativeTracking,
    );
  }

  factory EvidenceMetric.picking(PickingMetricId id) {
    final definition = pickingMetricDefinitions.firstWhere(
      (definition) => definition.id == id,
    );
    return EvidenceMetric._(
      family: EvidenceMetricFamily.picking,
      id: id.name,
      window: definition.window,
      minimumVisibility: definition.minimumVisibility,
      requiresGeometry:
          definition.requiredCapability ==
          PickingCapability.guitarRelativeTracking,
    );
  }

  factory EvidenceMetric.posture(PostureMetricId id) {
    final definition = postureMetricDefinitions.firstWhere(
      (definition) => definition.id == id,
    );
    return EvidenceMetric._(
      family: EvidenceMetricFamily.posture,
      id: id.name,
      window: definition.window,
      minimumVisibility: definition.minimumVisibility,
      requiresGeometry: false,
    );
  }

  final EvidenceMetricFamily family;
  final String id;
  final Duration window;
  final double minimumVisibility;
  final bool requiresGeometry;

  String get key => '${family.name}:$id';

  static List<EvidenceMetric> get currentCatalog =>
      List<EvidenceMetric>.unmodifiable(<EvidenceMetric>[
        for (final id in FrettingMetricId.values) EvidenceMetric.fretting(id),
        for (final id in PickingMetricId.values) EvidenceMetric.picking(id),
        for (final id in PostureMetricId.values) EvidenceMetric.posture(id),
      ]);
}

/// One normalized, timestamped input consumed by [ObservationFusion].
final class VisionObservation {
  VisionObservation({
    required this.timestampUs,
    required this.metric,
    required this.modelVersion,
    required this.metricObservation,
    required this.frameQuality,
    required this.geometrySource,
    required this.geometryConfidence,
    required this.syncQuality,
    this.wasInterpolated = false,
  }) {
    if (modelVersion.trim().isEmpty) {
      throw ArgumentError.value(
        modelVersion,
        'modelVersion',
        'Must not be empty.',
      );
    }
  }

  final int timestampUs;
  final EvidenceMetric metric;
  final String modelVersion;
  final MetricObservation metricObservation;
  final VisionFrameQuality frameQuality;
  final GeometrySource geometrySource;
  final GeometryConfidence geometryConfidence;
  final SyncQuality syncQuality;

  /// True only when the upstream tracker bridged a known short occlusion.
  final bool wasInterpolated;
}
