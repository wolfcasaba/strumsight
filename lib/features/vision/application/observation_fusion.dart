import '../domain/evidence/confidence_model.dart';
import '../domain/evidence/evidence_provenance.dart';
import '../domain/evidence/vision_evidence.dart';
import '../domain/evidence/vision_observation.dart';
import '../domain/metrics/metric_observation.dart';
import '../domain/sync/sync_quality.dart';

/// Versioned, fusion-owned observability thresholds.
///
/// These thresholds are applied on top of, never instead of, each metric's
/// existing [EvidenceMetric.window] contract.
final class FusionThresholds {
  const FusionThresholds({
    required this.version,
    required this.minimumObservationCount,
    required this.minimumVisibleDuration,
    required this.maximumGap,
    required this.inferredConfidencePenalty,
    this.maximumRetainedEvidence = 128,
  }) : assert(version != ''),
       assert(minimumObservationCount >= 2),
       assert(inferredConfidencePenalty > 0 && inferredConfidencePenalty < 1),
       assert(maximumRetainedEvidence > 0);

  final String version;
  final int minimumObservationCount;
  final Duration minimumVisibleDuration;
  final Duration maximumGap;
  final double inferredConfidencePenalty;
  final int maximumRetainedEvidence;
}

/// Windowed, bounded-memory fusion from normalized observations to evidence.
final class ObservationFusion {
  ObservationFusion({
    required this.thresholds,
    this.confidenceModel = const ConfidenceModel(),
  });

  final FusionThresholds thresholds;
  final ConfidenceModel confidenceModel;
  final Map<String, List<VisionObservation>> _observationsByMetric =
      <String, List<VisionObservation>>{};
  final Map<String, VisionEvidence> _evidenceByWindow =
      <String, VisionEvidence>{};

  List<VisionEvidence> get emittedEvidence =>
      List<VisionEvidence>.unmodifiable(_evidenceByWindow.values);

  int get retainedObservationCount => _observationsByMetric.values.fold<int>(
    0,
    (count, observations) => count + observations.length,
  );

  void add(VisionObservation observation) {
    final observations = _observationsByMetric.putIfAbsent(
      observation.metric.key,
      () => <VisionObservation>[],
    );
    observations.add(observation);
  }

  void addAll(Iterable<VisionObservation> observations) {
    for (final observation in observations) {
      add(observation);
    }
  }

  VisionEvidence fuse({
    required EvidenceMetric metric,
    required int windowEndUs,
  }) {
    final window = EvidenceWindow(
      startUs: windowEndUs - metric.window.inMicroseconds,
      endUs: windowEndUs,
    );
    final cacheKey = '${metric.key}:${window.startUs}:${window.endUs}';
    final cached = _evidenceByWindow[cacheKey];
    if (cached != null) return cached;

    final retained = _observationsByMetric[metric.key] ?? <VisionObservation>[];
    final inWindow =
        retained
            .where((observation) => window.contains(observation.timestampUs))
            .toList()
          ..sort(
            (left, right) => left.timestampUs.compareTo(right.timestampUs),
          );
    final evidence = _fuseWindow(
      metric: metric,
      window: window,
      observations: inWindow,
    );
    _evidenceByWindow[cacheKey] = evidence;
    while (_evidenceByWindow.length > thresholds.maximumRetainedEvidence) {
      _evidenceByWindow.remove(_evidenceByWindow.keys.first);
    }

    // Raw observations older than this completed metric window cannot affect a
    // later window. The cache retains only small evidence objects, not frames.
    retained.removeWhere(
      (observation) => observation.timestampUs < window.startUs,
    );
    return evidence;
  }

  VisionEvidence _fuseWindow({
    required EvidenceMetric metric,
    required EvidenceWindow window,
    required List<VisionObservation> observations,
  }) {
    final provenance = _provenance(
      metric: metric,
      window: window,
      observations: observations,
    );
    final id = VisionEvidence.deterministicId(metric: metric, window: window);
    final visible = observations
        .where(
          (observation) =>
              observation.metricObservation.observability ==
                  MetricObservability.observable &&
              observation.metricObservation.confidence >=
                  metric.minimumVisibility,
        )
        .toList(growable: false);
    final hasMinimumEvidence =
        visible.length >= thresholds.minimumObservationCount &&
        _visibleDuration(visible) >= thresholds.minimumVisibleDuration;
    final hasUnbridgeableGap = _hasGapLongerThan(
      visible,
      thresholds.maximumGap,
    );
    if (!hasMinimumEvidence ||
        hasUnbridgeableGap ||
        !_hasSingleModelVersion(visible) ||
        !_hasSingleQualityThresholdsVersion(visible) ||
        (metric.requiresGeometry && !_hasSingleGeometrySource(visible))) {
      return VisionEvidence(
        id: id,
        metric: metric,
        value: null,
        confidence: 0,
        observationState: ObservationState.notObservable,
        provenance: provenance,
      );
    }

    final hasInterpolatedGap = visible.any(
      (observation) => observation.wasInterpolated,
    );
    final components = ConfidenceComponents(
      model: visible
          .map((observation) => observation.metricObservation.confidence)
          .reduce(_minimum),
      quality: visible
          .map(
            (observation) =>
                confidenceModel.qualityContribution(observation.frameQuality),
          )
          .reduce(_minimum),
      geometry: metric.requiresGeometry
          ? visible
                .map((observation) => observation.geometryConfidence.confidence)
                .reduce(_minimum)
          : 1,
      sync: visible
          .map(
            (observation) =>
                confidenceModel.syncContribution(observation.syncQuality),
          )
          .reduce(_minimum),
    );
    final confidence =
        confidenceModel.combine(components) *
        (hasInterpolatedGap ? thresholds.inferredConfidencePenalty : 1);
    return VisionEvidence(
      id: id,
      metric: metric,
      value:
          visible
              .map((observation) => observation.metricObservation.value!)
              .reduce((sum, value) => sum + value) /
          visible.length,
      confidence: confidence,
      observationState: hasInterpolatedGap
          ? ObservationState.inferred
          : ObservationState.observed,
      provenance: provenance,
    );
  }

  EvidenceProvenance _provenance({
    required EvidenceMetric metric,
    required EvidenceWindow window,
    required List<VisionObservation> observations,
  }) {
    final first = observations.isEmpty ? null : observations.first;
    final usesTrackedGeometry =
        metric.requiresGeometry &&
        observations.isNotEmpty &&
        observations.every(
          (observation) => observation.geometrySource == GeometrySource.tracked,
        );
    return EvidenceProvenance(
      metricId: metric.key,
      window: window,
      modelVersion: first?.modelVersion ?? 'unavailable',
      geometrySource: usesTrackedGeometry
          ? GeometrySource.tracked
          : GeometrySource.manual,
      syncQuality: _lowestSyncQuality(observations),
      thresholdsVersion: thresholds.version,
      qualityThresholdsVersion:
          first?.frameQuality.thresholdsVersion ?? 'unavailable',
    );
  }

  bool _hasSingleModelVersion(List<VisionObservation> observations) =>
      observations
          .map((observation) => observation.modelVersion)
          .toSet()
          .length <=
      1;

  bool _hasSingleQualityThresholdsVersion(
    List<VisionObservation> observations,
  ) =>
      observations
          .map((observation) => observation.frameQuality.thresholdsVersion)
          .toSet()
          .length <=
      1;

  bool _hasSingleGeometrySource(List<VisionObservation> observations) =>
      observations
          .map((observation) => observation.geometrySource)
          .toSet()
          .length <=
      1;

  Duration _visibleDuration(List<VisionObservation> observations) {
    if (observations.length < 2) return Duration.zero;
    return Duration(
      microseconds:
          observations.last.timestampUs - observations.first.timestampUs,
    );
  }

  bool _hasGapLongerThan(
    List<VisionObservation> observations,
    Duration maximumGap,
  ) {
    for (var index = 1; index < observations.length; index += 1) {
      final gapUs =
          observations[index].timestampUs - observations[index - 1].timestampUs;
      if (gapUs > maximumGap.inMicroseconds) return true;
    }
    return false;
  }

  SyncQuality _lowestSyncQuality(List<VisionObservation> observations) {
    if (observations.isEmpty) return SyncQuality.poor;
    return observations
        .map((observation) => observation.syncQuality)
        .reduce(
          (lowest, quality) => quality.index < lowest.index ? quality : lowest,
        );
  }

  static double _minimum(double left, double right) =>
      right < left ? right : left;
}
