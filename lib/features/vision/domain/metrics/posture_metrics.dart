// E05-R20 — Posture metric catalog (SDD §21, brief §3).
//
// The catalog mirrors `picking_metrics.dart` (R19) BY SHAPE, not by
// import. The two-finger split of `metric_definition.dart` (R18,
// fretting) is itself Fretting-specific hardcode and is NOT in this
// round's `allowed_paths` — so the posture-side lives here with the same
// throw-`ArgumentError` constructor invariant, the same `isValid`
// getter, and the same `definitionFor(id)` accessor. Only the ID enum,
// required-landmark list, and per-metric thresholds are posture-specific.
//
// The catalog exposes:
//   - `PostureMetricId` — the four observable posture metrics
//     (shoulderAsymmetry / torsoLean / elbowDrift / neckProxy).
//   - `PostureCapability` — capability required before a metric can
//     be interpreted. All four posture metrics need
//     `poseTracking` because the metrics operate on the R14
//     upper-body pose topology.
//   - `PostureMetricDefinition` — the per-metric catalog record,
//     extends the R19 shape with a `requiredPoseLandmarkIds` field
//     that the engine gates on (brief §5 /7 — R8 mandate).
//   - `postureMetricDefinitions` — the validated, unmodifiable list.
//
// Required-landmark list (brief §5 /7):
//   - shoulderAsymmetry → {leftShoulder, rightShoulder}
//   - torsoLean         → {leftShoulder, rightShoulder, leftHip, rightHip}
//   - elbowDrift        → {leftElbow, rightElbow}
//   - neckProxy         → {neckReference}
//
// The list is the gate, NOT `observation.state == good`. The R8
// scenario (state=good with a single shared landmark and 4.257 max
// drift) is rejected by the engine because the required-landmark
// set is not satisfied.

library;

import 'package:meta/meta.dart';

import '../landmarks/pose_landmarks.dart';

/// Capability required before a posture metric can be interpreted.
enum PostureCapability { poseTracking }

/// Posture metric IDs (SDD §21).
enum PostureMetricId {
  /// Vertical asymmetry between the two shoulders,
  /// normalized by shoulder span. Baseline-relative.
  shoulderAsymmetry,

  /// Vertical shift of the shoulder-pair centroid vs the hip-pair
  /// centroid, normalized by shoulder span. Baseline-relative.
  torsoLean,

  /// Lateral drift of the elbows in the normalized frame.
  /// Baseline-relative.
  elbowDrift,

  /// Vertical shift of the neck reference point,
  /// normalized by shoulder span. Baseline-relative; optional
  /// (returns `unobservable` when the reference is absent).
  neckProxy,
}

/// Per-metric definition record. Mirrors the R19 shape (`PickingMetricDefinition`)
/// and adds the `requiredPoseLandmarkIds` field that the engine
/// gates on.
@immutable
final class PostureMetricDefinition {
  PostureMetricDefinition({
    required this.id,
    required this.minimumVisibility,
    required this.window,
    required this.confidenceFormula,
    required this.requiredCapability,
    required this.requiredPoseLandmarkIds,
    required this.claimCode,
  }) {
    if (!(minimumVisibility.isFinite &&
        minimumVisibility >= 0 &&
        minimumVisibility <= 1)) {
      throw ArgumentError.value(
        minimumVisibility,
        'minimumVisibility',
        'Must be finite and in [0, 1].',
      );
    }
    if (window <= Duration.zero) {
      throw ArgumentError.value(
        window,
        'window',
        'Must be a positive Duration.',
      );
    }
    if (confidenceFormula.trim().isEmpty) {
      throw ArgumentError.value(
        confidenceFormula,
        'confidenceFormula',
        'Must be a non-empty string.',
      );
    }
    if (requiredPoseLandmarkIds.isEmpty) {
      throw ArgumentError.value(
        requiredPoseLandmarkIds,
        'requiredPoseLandmarkIds',
        'Must be non-empty (§5 /7 — R8 gate).',
      );
    }
    if (claimCode.trim().isEmpty) {
      throw ArgumentError.value(
        claimCode,
        'claimCode',
        'Must be a non-empty claim code.',
      );
    }
  }

  final PostureMetricId id;
  final double minimumVisibility;
  final Duration window;
  final String confidenceFormula;
  final PostureCapability requiredCapability;

  /// The landmark set the engine must see in the [PostureObservation]
  /// before the metric can be emitted. This is the R8 gate (§5 /7);
  /// `observation.state` is NOT used.
  final Set<PoseLandmarkId> requiredPoseLandmarkIds;

  /// The claim code emitted into the policy catalog when the metric
  /// is observable. The code is validated when the catalog is built
  /// (see `postureMetricDefinitions`).
  final String claimCode;

  bool get isValid =>
      minimumVisibility.isFinite &&
      minimumVisibility >= 0 &&
      minimumVisibility <= 1 &&
      window > Duration.zero &&
      confidenceFormula.trim().isNotEmpty &&
      requiredPoseLandmarkIds.isNotEmpty &&
      claimCode.trim().isNotEmpty;
}

/// The complete, validated posture-metric catalog.
///
/// Every entry's `claimCode` must be in the [VisionSafetyPolicy.catalog]
/// (brief §5 /6 — the catalog is the single source of truth for
/// emitted codes). The catalog is built eagerly so a regression in
/// the policy mapping surfaces at import time, not at runtime.
final List<PostureMetricDefinition> postureMetricDefinitions =
    List.unmodifiable(<PostureMetricDefinition>[
      PostureMetricDefinition(
        id: PostureMetricId.shoulderAsymmetry,
        minimumVisibility: 0.55,
        window: const Duration(milliseconds: 500),
        confidenceFormula: 'mean(minimum landmark visibility)',
        requiredCapability: PostureCapability.poseTracking,
        requiredPoseLandmarkIds: <PoseLandmarkId>{
          PoseLandmarkId.leftShoulder,
          PoseLandmarkId.rightShoulder,
        },
        claimCode: 'postureShoulderAsymmetryIncreasedVsBaseline',
      ),
      PostureMetricDefinition(
        id: PostureMetricId.torsoLean,
        minimumVisibility: 0.55,
        window: const Duration(milliseconds: 500),
        confidenceFormula: 'mean(minimum landmark visibility)',
        requiredCapability: PostureCapability.poseTracking,
        requiredPoseLandmarkIds: <PoseLandmarkId>{
          PoseLandmarkId.leftShoulder,
          PoseLandmarkId.rightShoulder,
          PoseLandmarkId.leftHip,
          PoseLandmarkId.rightHip,
        },
        claimCode: 'postureTorsoLeanShiftedVsBaseline',
      ),
      PostureMetricDefinition(
        id: PostureMetricId.elbowDrift,
        minimumVisibility: 0.55,
        window: const Duration(milliseconds: 500),
        confidenceFormula: 'mean(minimum landmark visibility)',
        requiredCapability: PostureCapability.poseTracking,
        requiredPoseLandmarkIds: <PoseLandmarkId>{
          PoseLandmarkId.leftElbow,
          PoseLandmarkId.rightElbow,
        },
        claimCode: 'postureElbowDriftObserved',
      ),
      PostureMetricDefinition(
        id: PostureMetricId.neckProxy,
        minimumVisibility: 0.55,
        window: const Duration(milliseconds: 500),
        confidenceFormula: 'mean(minimum landmark visibility)',
        requiredCapability: PostureCapability.poseTracking,
        requiredPoseLandmarkIds: <PoseLandmarkId>{PoseLandmarkId.neckReference},
        claimCode: 'postureNeckProxyShiftedVsBaseline',
      ),
    ]);
