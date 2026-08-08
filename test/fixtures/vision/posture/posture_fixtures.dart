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
    if (missing.contains(entry.key)) continue;
    final offset = offsets[entry.key];
    final x = entry.value[0] + (offset ?? 0);
    final y = entry.value[1] + (offset ?? 0);
    final rawName = entry.key.name.replaceFirst('left', 'left_').replaceFirst(
      'right',
      'right_',
    );
    raw.add(
      RawPoseLandmark(
        name: rawName,
        x: x,
        y: y,
        z: 0,
        visibility: visibility,
      ),
    );
  }
  // Optional neck reference.
  if (!missing.contains(PoseLandmarkId.neckReference)) {
    final offset = offsets[PoseLandmarkId.neckReference] ?? 0;
    raw.add(
      RawPoseLandmark(
        name: 'neck',
        x: 0.5,
        y: 0.26 + offset,
        z: 0,
        visibility: visibility,
      ),
    );
  }
  return mapRawPoseLandmarks(timestampUs: timestampUs, raw: raw);
}

/// Build a baseline from two identical frames covering [_kBaselineDuration].
PostureBaselineCollector _baselineFromPose(PoseLandmarks pose) {
  final collector = PostureBaselineCollector(config: _kConfig);
  collector.add(
    pose: pose,
    overallQuality: VisionMetricState.good,
    qualityScore: 0.9,
  );
  collector.add(
    pose: pose,
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
  final collector = _baselineFromPose(baselinePose);
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
/// cell.
PostureObservation buildCleanFullBaselineObservation() {
  return _observe(
    baselineOffsets: const <PoseLandmarkId, double>{},
    observationOffsets: const <PoseLandmarkId, double>{},
  );
}

/// A partial baseline with only the left shoulder present. Mirrors the
/// "missing / partial / full" baseline-matrix row "partial".
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
    },
  );
}

/// A shoulder-asymmetry observation. Both shoulders drift by
/// [droppedLeftShoulder] (a vertical offset). The metric is the absolute
/// |Δy| normalized by the shoulder span.
PostureObservation buildShoulderAsymmetryObservation({
  required double droppedLeftShoulder,
}) {
  return _observe(
    baselineOffsets: const <PoseLandmarkId, double>{},
    observationOffsets: <PoseLandmarkId, double>{
      PoseLandmarkId.leftShoulder: droppedLeftShoulder,
      PoseLandmarkId.rightShoulder: droppedLeftShoulder,
    },
  );
}

/// A torso-lean observation. Both shoulders drift by [shoulderOffsetY]
/// (positive = lean down, negative = lean up). The hips are stable.
PostureObservation buildTorsoLeanObservation({required double shoulderOffsetY}) {
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
    },
  );
}

/// The R8 degenerate scenario from the brief §0.0 R8: state=good,
/// comparedLandmarkCount=1, maxDrift=4.257 (the measured value from the
/// brief). The single shared landmark is the left shoulder; the
/// normalized drift is 4.257 (=> 0.8514 in normalized-frame units over
/// the 0.20 shoulder span).
PostureObservation buildR8DegenerateObservation() {
  return _observe(
    baselineOffsets: const <PoseLandmarkId, double>{},
    observationOffsets: <PoseLandmarkId, double>{
      PoseLandmarkId.leftShoulder: 0.8514,
    },
    baselineMissing: const <PoseLandmarkId>{
      PoseLandmarkId.rightShoulder,
      PoseLandmarkId.leftElbow,
      PoseLandmarkId.rightElbow,
      PoseLandmarkId.leftHip,
      PoseLandmarkId.rightHip,
    },
  );
}

/// A non-finite drift observation. The first required landmark for
/// every metric carries [value] (NaN or Infinity). The engine must
/// emit `notObservable` for every metric, regardless of the value.
PostureObservation buildNonFiniteDriftObservation({required double value}) {
  // The baseline is clean. The observation drifts the left shoulder
  // by a non-finite value. The drift map ends up with NaN/Infinity,
  // which the posture_baseline observes — its thresholding will
  // either propagate the NaN or produce a notObservable observation.
  // The engine must still defend with a finite-value guard.
  return _observe(
    baselineOffsets: const <PoseLandmarkId, double>{},
    observationOffsets: <PoseLandmarkId, double>{
      PoseLandmarkId.leftShoulder: value,
    },
  );
}
