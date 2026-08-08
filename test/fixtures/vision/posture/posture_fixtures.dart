// E05-R20 — Posture metric engine fixture generators.
//
// Pure, deterministic synthetic `PostureObservation` values for the
// posture metric engine tests. The brief §6 acceptance matrix drives the
// cases:
//
//   - `buildCleanFullBaselineObservation` — every landmark present,
//     zero drift, posture_baseline returns state=good.
//   - `buildPartialBaselineObservation` — only one shoulder present in
//     the baseline; every metric is not observable (§5 /7).
//   - `buildShoulderAsymmetryObservation` — only shoulder landmarks
//     drift (one shoulder dropped).
//   - `buildTorsoLeanObservation` — both shoulders + both hips, with the
//     given vertical offset.
//   - `buildElbowDriftObservation` — both elbows visible, with the
//     given lateral displacement.
//   - `buildNeckProxyObservation` — neck reference present, with the
//     given displacement.
//   - `buildPerspectiveObservation` — full baseline + a lateral
//     shoulder asymmetry (used by the three-quartile perspective
//     matrix).
//   - `buildDegenerateSingleShoulderObservation` — only one shoulder
//     present, large drift → state=good but every metric not observable.
//   - `buildR8DegenerateObservation` — the precise scenario from §0.0
//     R8: state=good, comparedLandmarkCount=1, maxDrift=4.257.
//   - `buildNonFiniteDriftObservation` — single required landmark
//     carries a NaN / Infinity drift value.
//
// The fixtures build a real `PostureBaselineCollector` from synthetic
// pose frames, then observe an altered pose. This is the legitimate
// test approach for `PostureObservation` (the private constructor is
// not accessible to outside-of-file callers, and modifying the source
// file is not in the round's `allowed_paths`).
//
// Visibility semantics: a landmark is "absent" from a pose when its
// visibility is below [minimumLandmarkVisibility] (default 0.5). The
// `missing` parameter sets the landmark's visibility to 0 — the
// landmark is still in the pose map but is treated as absent by the
// baseline filter. This mirrors a real-world scenario where the
// provider localizes a landmark but with low confidence.

library;

import 'package:strumsight/features/vision/domain/landmarks/pose_landmarks.dart';
import 'package:strumsight/features/vision/domain/landmarks/posture_baseline.dart';
import 'package:strumsight/features/vision/domain/quality/vision_frame_quality.dart';

const double _kShoulderSpan = 0.20;
const Duration _kBaselineDuration = Duration(seconds: 4);

const _kConfig = PostureBaselineConfig(
  minimumVisibleDuration: Duration(seconds: 3),
  minimumSampleCount: 2,
  minimumQualityScore: 0.7,
  minimumLandmarkVisibility: 0.5,
);

/// A config that only requires the left shoulder. Used by partial
/// fixtures where the baseline has only one shoulder.
const _kPartialConfig = PostureBaselineConfig(
  minimumVisibleDuration: Duration(seconds: 3),
  minimumSampleCount: 2,
  minimumQualityScore: 0.7,
  minimumLandmarkVisibility: 0.5,
  requiredIds: <PoseLandmarkId>{PoseLandmarkId.leftShoulder},
);

/// Build a pose with the requested landmarks at the given epoch.
PoseLandmarks _poseAt({
  required int timestampUs,
  required Map<PoseLandmarkId, double> offsets,
  Set<PoseLandmarkId> missing = const <PoseLandmarkId>{},
  double visibility = 0.9,
}) {
  final raw = <RawPoseLandmark>[];
  // The base landmarks for the full baseline.
  final base = <PoseLandmarkId, List<double>>{
    PoseLandmarkId.leftShoulder: [0.40, 0.30],
    PoseLandmarkId.rightShoulder: [0.60, 0.30],
    PoseLandmarkId.leftElbow: [0.42, 0.50],
    PoseLandmarkId.rightElbow: [0.58, 0.50],
    PoseLandmarkId.leftHip: [0.44, 0.70],
    PoseLandmarkId.rightHip: [0.56, 0.70],
  };
  for (final entry in base.entries) {
    // Missing landmarks are emitted with visibility 0 — the baseline
    // filter will drop them below the 0.5 threshold.
    final isMissing = missing.contains(entry.key);
    final offset = offsets[entry.key];
    final x = entry.value[0];
    final y = entry.value[1] + (offset ?? 0);
    final rawName = _rawNameFor(entry.key);
    raw.add(
      RawPoseLandmark(
        name: rawName,
        x: x,
        y: y,
        z: 0,
        visibility: isMissing ? 0.0 : visibility,
      ),
    );
  }
  // Optional neck reference.
  final neckMissing = missing.contains(PoseLandmarkId.neckReference);
  final neckOffset = offsets[PoseLandmarkId.neckReference] ?? 0;
  raw.add(
    RawPoseLandmark(
      name: 'neck',
      x: 0.5,
      y: 0.26 + neckOffset,
      z: 0,
      visibility: neckMissing ? 0.0 : visibility,
    ),
  );
  return mapRawPoseLandmarks(timestampUs: timestampUs, raw: raw);
}

/// Map a PoseLandmarkId to the raw provider name defined in
/// `poseLandmarkIdByRawName` (pose_landmarks.dart).
String _rawNameFor(PoseLandmarkId id) {
  switch (id) {
    case PoseLandmarkId.leftShoulder:
      return 'left_shoulder';
    case PoseLandmarkId.rightShoulder:
      return 'right_shoulder';
    case PoseLandmarkId.leftElbow:
      return 'left_elbow';
    case PoseLandmarkId.rightElbow:
      return 'right_elbow';
    case PoseLandmarkId.leftWrist:
      return 'left_wrist';
    case PoseLandmarkId.rightWrist:
      return 'right_wrist';
    case PoseLandmarkId.leftHip:
      return 'left_hip';
    case PoseLandmarkId.rightHip:
      return 'right_hip';
    case PoseLandmarkId.neckReference:
      return 'neck';
  }
}

/// Build a baseline from two frames covering the requested duration.
/// Both samples carry the same missing-landmark set so the baseline
/// contains exactly the landmarks we want to keep. The first sample
/// is at timestamp 0; the second sample is at [durationUs].
PostureBaselineCollector _baselineFromPose(
  PoseLandmarks pose, {
  int durationUs = 4000000,
  Set<PoseLandmarkId> missing = const <PoseLandmarkId>{},
  PostureBaselineConfig? config,
}) {
  final collector = PostureBaselineCollector(config: config ?? _kConfig);
  collector.add(
    pose: pose,
    overallQuality: VisionMetricState.good,
    qualityScore: 0.9,
  );
  final stamped = _poseAt(
    timestampUs: durationUs,
    offsets: const <PoseLandmarkId, double>{},
    missing: missing,
  );
  collector.add(
    pose: stamped,
    overallQuality: VisionMetricState.good,
    qualityScore: 0.9,
  );
  return collector;
}

/// Build a baseline + observation pair.
/// [baselineOffsets] is the offset of each landmark relative to the
/// base position at the baseline. [observationOffsets] is the offset
/// at the observation timestamp.
PostureObservation _observe({
  required Map<PoseLandmarkId, double> baselineOffsets,
  required Map<PoseLandmarkId, double> observationOffsets,
  Set<PoseLandmarkId> baselineMissing = const <PoseLandmarkId>{},
  Set<PoseLandmarkId> observationMissing = const <PoseLandmarkId>{},
  int observationTimestampUs = 5000000,
}) {
  final baselinePose = _poseAt(
    timestampUs: 0,
    offsets: baselineOffsets,
    missing: baselineMissing,
  );
  // Partial baselines need a permissive config — the default config
  // requires both shoulders, which collapses the partial fixtures.
  final config = baselineMissing.isNotEmpty ? _kPartialConfig : _kConfig;
  final collector = _baselineFromPose(
    baselinePose,
    missing: baselineMissing,
    config: config,
  );
  if (collector.baseline == null) {
    return PostureObservation.notObservable();
  }
  final observePose = _poseAt(
    timestampUs: observationTimestampUs,
    offsets: observationOffsets,
    missing: observationMissing,
  );
  return collector.observe(observePose);
}

// ---------------------------------------------------------------------------
// Public fixtures used by the test suite.
// ---------------------------------------------------------------------------

/// A clean pose against the full baseline. Every landmark drifts by 0.
/// The fixture supports the "full baseline + clean pose" baseline-matrix
/// cell. The neck reference is OPTIONAL (brief §3 / §21) — the clean
/// fixture does NOT include it, so the neckProxy metric falls back to
/// `notObservable` from the engine's R8 gate.
PostureObservation buildCleanFullBaselineObservation() {
  return _observe(
    baselineOffsets: const <PoseLandmarkId, double>{},
    observationOffsets: const <PoseLandmarkId, double>{},
    baselineMissing: const <PoseLandmarkId>{PoseLandmarkId.neckReference},
    observationMissing: const <PoseLandmarkId>{PoseLandmarkId.neckReference},
  );
}

/// A partial baseline with only the left shoulder present. Mirrors the
/// "missing / partial / full" baseline-matrix row "partial". The
/// baseline has only the left shoulder (everything else is dropped);
/// the observation has only the left shoulder visible from the
/// observation side. The neck reference is also dropped so the
/// neckProxy metric falls back to `notObservable`.
PostureObservation buildPartialBaselineObservation() {
  return _observe(
    baselineOffsets: const <PoseLandmarkId, double>{},
    observationOffsets: const <PoseLandmarkId, double>{},
    baselineMissing: const <PoseLandmarkId>{
      PoseLandmarkId.rightShoulder,
      PoseLandmarkId.leftElbow,
      PoseLandmarkId.rightElbow,
      PoseLandmarkId.leftHip,
      PoseLandmarkId.rightHip,
      PoseLandmarkId.neckReference,
    },
    observationMissing: const <PoseLandmarkId>{
      PoseLandmarkId.rightShoulder,
      PoseLandmarkId.leftElbow,
      PoseLandmarkId.rightElbow,
      PoseLandmarkId.leftHip,
      PoseLandmarkId.rightHip,
      PoseLandmarkId.neckReference,
    },
  );
}

/// A shoulder-asymmetry observation. Both shoulders drift by
/// [droppedLeftShoulder] (a vertical offset). The hips / elbows / neck
/// are NOT visible in the observation (they have visibility 0), so the
/// drift map contains only the two shoulders — this is the
/// observation that exercises the "torsoLean without hips → notObservable"
/// acceptance cell.
PostureObservation buildShoulderAsymmetryObservation({
  required double droppedLeftShoulder,
}) {
  return _observe(
    baselineOffsets: const <PoseLandmarkId, double>{},
    observationOffsets: <PoseLandmarkId, double>{
      PoseLandmarkId.leftShoulder: droppedLeftShoulder,
      PoseLandmarkId.rightShoulder: droppedLeftShoulder,
    },
    observationMissing: const <PoseLandmarkId>{
      PoseLandmarkId.leftElbow,
      PoseLandmarkId.rightElbow,
      PoseLandmarkId.leftHip,
      PoseLandmarkId.rightHip,
      PoseLandmarkId.neckReference,
    },
  );
}

/// A torso-lean observation. Both shoulders drift by [shoulderOffsetY]
/// (positive = lean down, negative = lean up). The hips are stable.
PostureObservation buildTorsoLeanObservation({
  required double shoulderOffsetY,
}) {
  return _observe(
    baselineOffsets: const <PoseLandmarkId, double>{},
    observationOffsets: <PoseLandmarkId, double>{
      PoseLandmarkId.leftShoulder: shoulderOffsetY,
      PoseLandmarkId.rightShoulder: shoulderOffsetY,
    },
  );
}

/// Elbow-drift observation. Both elbows drift by [displacement].
/// [missingRightElbow] drops the right elbow from the observation pose
/// to exercise the R8-degenerate-path "one elbow missing" cell.
PostureObservation buildElbowDriftObservation({
  required double displacement,
  bool missingRightElbow = false,
}) {
  final observationMissing = missingRightElbow
      ? <PoseLandmarkId>{PoseLandmarkId.rightElbow}
      : const <PoseLandmarkId>{};
  return _observe(
    baselineOffsets: const <PoseLandmarkId, double>{},
    observationOffsets: <PoseLandmarkId, double>{
      PoseLandmarkId.leftElbow: displacement,
      PoseLandmarkId.rightElbow: displacement,
    },
    observationMissing: observationMissing,
  );
}

/// Neck-proxy observation. The neck reference carries the given
/// displacement. The fixture is paired with a baseline that includes
/// the neck reference (this is the only fixture that does).
PostureObservation buildNeckProxyObservation({required double displacement}) {
  return _observe(
    baselineOffsets: const <PoseLandmarkId, double>{},
    observationOffsets: <PoseLandmarkId, double>{
      PoseLandmarkId.neckReference: displacement,
    },
  );
}

/// A perspective-fixture observation with a lateral shoulder offset
/// (used for the three-camera-angle matrix). [side] is the horizontal
/// offset of the left shoulder (positive = left, negative = right).
PostureObservation buildPerspectiveObservation({required double side}) {
  return _observe(
    baselineOffsets: const <PoseLandmarkId, double>{},
    observationOffsets: <PoseLandmarkId, double>{
      PoseLandmarkId.leftShoulder: side,
      PoseLandmarkId.rightShoulder: -side,
    },
  );
}

/// A degenerate observation: only the left shoulder drifted; the
/// state is `good` (mimicking posture_baseline's contract). The metric
/// engine must still emit `notObservable` for every metric that
/// requires more than one landmark.
PostureObservation buildDegenerateSingleShoulderObservation() {
  return _observe(
    baselineOffsets: const <PoseLandmarkId, double>{},
    observationOffsets: const <PoseLandmarkId, double>{},
    baselineMissing: const <PoseLandmarkId>{
      PoseLandmarkId.rightShoulder,
      PoseLandmarkId.leftElbow,
      PoseLandmarkId.rightElbow,
      PoseLandmarkId.leftHip,
      PoseLandmarkId.rightHip,
      PoseLandmarkId.neckReference,
    },
    observationMissing: const <PoseLandmarkId>{
      PoseLandmarkId.rightShoulder,
      PoseLandmarkId.leftElbow,
      PoseLandmarkId.rightElbow,
      PoseLandmarkId.leftHip,
      PoseLandmarkId.rightHip,
      PoseLandmarkId.neckReference,
    },
  );
}

/// The R8 degenerate scenario from the brief §0.0 R8: state=good,
/// comparedLandmarkCount=1, maxDrift=4.257 (the measured value from the
/// brief).
///
/// The baseline has both shoulders + both hips (so the shoulder span is
/// computed as 0.20). The observation is extreme — only the left
/// shoulder is visible (visibility 0 on every other landmark), and
/// the offset is 0.8514 normalized-frame units (=> 4.257 in shoulder-
/// span-normalized drift).
PostureObservation buildR8DegenerateObservation() {
  return _observe(
    baselineOffsets: const <PoseLandmarkId, double>{},
    observationOffsets: <PoseLandmarkId, double>{
      PoseLandmarkId.leftShoulder: 0.8514,
    },
    observationMissing: const <PoseLandmarkId>{
      PoseLandmarkId.rightShoulder,
      PoseLandmarkId.leftElbow,
      PoseLandmarkId.rightElbow,
      PoseLandmarkId.leftHip,
      PoseLandmarkId.rightHip,
      PoseLandmarkId.neckReference,
    },
  );
}

/// A non-finite drift observation. The first required landmark for
/// the affected metrics (leftShoulder) carries [value] (NaN or
/// Infinity). The engine must emit `notObservable` for the metrics
/// that require the affected landmark.
PostureObservation buildNonFiniteDriftObservation({required double value}) {
  return _observe(
    baselineOffsets: const <PoseLandmarkId, double>{},
    observationOffsets: <PoseLandmarkId, double>{
      PoseLandmarkId.leftShoulder: value,
    },
  );
}
