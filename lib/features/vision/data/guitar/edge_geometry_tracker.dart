/// Edge-/feature-based geometry tracker adapter (E05-R16).
///
/// Lightweight, deterministic, **not** an ML model — the brief §8 step 3
/// is explicit about this ("él-/feature-alapú — NEM ML-modell, NEM
/// model-asset; az automatikus gitárdetektor a Kör 17 dolga"). The
/// adapter implements the `GeometryTracker` contract by:
///
///   1. pairing each frame-observed feature with the nearest manual
///      anchor point (nut, bridge, neck polygon vertices);
///   2. computing a per-frame 2D translation as the **median** of the
///      per-pair vectors (median = robust to a single bad feature);
///   3. applying that translation to every manual anchor to produce
///      the proposed calibration;
///   4. reporting the drift = magnitude of the translation.
///
/// **Drift-bound enforcement.** The adapter REFUSES to produce an
/// observation whose drift exceeds [lostDriftBound] — instead it returns
/// `null`. This is the first line of the brief §5.1 "tracker nem
/// írhatja felül korlátlanul a manual anchorokat" guard; the second
/// line lives in [CalibrationLossMachine] (state-side hysteresis).
/// Together they make silent drift accumulation impossible: the adapter
/// says "I refuse", the machine says "I will not silently degrade".
///
/// **Confidence model.** Confidence scales linearly with how many
/// features the detector produced vs. how many it should have produced
/// (`expectedFeatureCount` defaults to the polygon vertex count plus
/// the two anchors). Below [trackingConfidenceThreshold] the loss
/// machine attributes the frame to the manual anchor, NOT to the
/// tracker (brief §5.4 — low-confidence tracker output is a manual
/// observation, not a tracked one).
library;

import 'dart:math' as math;

import '../../../../core/camera/camera_coordinate_space.dart';
import '../../domain/calibration/guitar_calibration.dart';
import '../../domain/geometry/geometry_confidence.dart';
import '../../domain/geometry/geometry_tracker.dart';

/// Lightweight edge/feature-based geometry tracker.
///
/// See file-level doc for the algorithm. Construction is trivial — this
/// tracker has no native resources and is fully pure Dart. The
/// `expectedFeatureCount` defaults to a conservative `4` (the typical
/// minimum useful for a robust translation estimate: nut + bridge +
/// two polygon midpoints).
final class EdgeGeometryTracker implements GeometryTracker {
  EdgeGeometryTracker({this.expectedFeatureCount = 4})
    : assert(expectedFeatureCount > 0);

  /// How many features the detector is expected to produce per frame.
  /// Confidence scales linearly toward `1.0` as the detected feature
  /// count approaches this value. Tuned per-frame in tests via the
  /// [FrameObservation.detectedFeatures] length.
  final int expectedFeatureCount;

  @override
  String get adapterId => 'edge_geometry_tracker.v1';

  @override
  GeometryObservation? observe({
    required GuitarCalibration anchor,
    required FrameObservation observation,
  }) {
    final features = observation.detectedFeatures;
    if (features.isEmpty) return null;

    // Anchor set: nut + bridge + every polygon vertex.
    final anchorPoints = <NormalizedPoint>[
      anchor.nutAnchor,
      anchor.bridgeAnchor,
      ...anchor.neckPolygon,
    ];

    // Per-feature nearest-anchor pair → translation vector.
    final translations = <(double, double)>[];
    for (final feature in features) {
      final closest = _nearestAnchor(feature, anchorPoints);
      if (closest == null) continue;
      translations.add((feature.x - closest.x, feature.y - closest.y));
    }
    if (translations.isEmpty) return null;

    // Median per-axis translation — robust to one outlier feature.
    final shift = _medianShift(translations);
    final drift = math.sqrt(shift.$1 * shift.$1 + shift.$2 * shift.$2);

    // Drift-bound guard: refuse to produce an observation whose drift
    // would push the loss machine past `lost` (brief §5.1).
    if (drift > lostDriftBound) return null;

    // Confidence: feature-count ratio, clamped to [0, 1].
    final ratio = features.length / expectedFeatureCount;
    final confidence = (ratio.clamp(0.0, 1.0)).toDouble();

    // Build the proposed calibration by translating every anchor.
    final shiftedNut = NormalizedPoint(
      (anchor.nutAnchor.x + shift.$1).clamp(0.0, 1.0),
      (anchor.nutAnchor.y + shift.$2).clamp(0.0, 1.0),
    );
    final shiftedBridge = NormalizedPoint(
      (anchor.bridgeAnchor.x + shift.$1).clamp(0.0, 1.0),
      (anchor.bridgeAnchor.y + shift.$2).clamp(0.0, 1.0),
    );
    final shiftedPolygon = anchor.neckPolygon
        .map(
          (p) => NormalizedPoint(
            (p.x + shift.$1).clamp(0.0, 1.0),
            (p.y + shift.$2).clamp(0.0, 1.0),
          ),
        )
        .toList(growable: false);

    final proposed = GuitarCalibration(
      nutAnchor: shiftedNut,
      bridgeAnchor: shiftedBridge,
      neckPolygon: shiftedPolygon,
      // The tracker is stateless w.r.t. `createdAt` — it preserves the
      // manual anchor's timestamp. The anchor was saved at user
      // calibration time; the tracker only translates the geometry.
      createdAt: anchor.createdAt,
    );

    return GeometryObservation(
      proposed: proposed,
      confidence: GeometryConfidence(confidence: confidence, drift: drift),
    );
  }

  NormalizedPoint? _nearestAnchor(
    NormalizedPoint feature,
    List<NormalizedPoint> anchors,
  ) {
    NormalizedPoint? best;
    var bestDist = double.infinity;
    for (final a in anchors) {
      final dx = feature.x - a.x;
      final dy = feature.y - a.y;
      final d = dx * dx + dy * dy;
      if (d < bestDist) {
        bestDist = d;
        best = a;
      }
    }
    return best;
  }

  (double, double) _medianShift(List<(double, double)> translations) {
    final sortedDx = translations.map((t) => t.$1).toList()..sort();
    final sortedDy = translations.map((t) => t.$2).toList()..sort();
    final mid = translations.length ~/ 2;
    return (sortedDx[mid], sortedDy[mid]);
  }
}
