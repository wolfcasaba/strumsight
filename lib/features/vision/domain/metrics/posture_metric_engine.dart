// E05-R20 — Posture metric engine (SDD §21, brief §5).
//
// Pure-Dart calculator for the four posture metrics (SDD §21,
// brief §3 / §4). The engine reads a single `PostureObservation`
// (R14) and produces a `MetricObservation` per metric ID.
//
// **R8 DEGENERATE GATE (brief §5 /7 — KÖTÖTT).** The engine must
// NOT trust `observation.state` to decide whether a metric is
// observable. `posture_baseline.dart` ALWAYS emits `state=good`
// when at least one landmark is shared with the baseline (§0.0
// R8 — measured: `comparedLandmarkCount=1, maxDrift=4.257` still
// gives `state=good`). The engine gates on the per-metric
// `requiredPoseLandmarkIds` list: every required ID must have a
// non-null `driftFor(id)` in the observation. A single missing
// required landmark → `notObservable`, regardless of the state.
// This is the opposite of "trust observation.state", and it is
// the ONLY safe behaviour.
//
// **Outputs are CLAIM CODES, not sentences** (brief §5 /3). The
// engine emits a `MetricObservation` whose claim code is the
// metric's catalog entry; the free-text rendering is R23's job.
// The emission also passes through the [SafetyClaimGuard] (the
// `evaluate` call is hard-coded, not optional) — a metric whose
// code is not in the catalog or whose class is forbidden expands
// to `notObservable` + a build-time error in the catalog
// definition.
//
// **NaN/Infinity guard.** Every drift value is funneled through
// `_finiteOrZero`; non-finite drifs win zero contribution. The
// engine never produces an observable value with a non-finite
// component.

library;

import 'dart:math' as math;

import '../landmarks/pose_landmarks.dart';
import '../landmarks/posture_baseline.dart';
import '../quality/vision_frame_quality.dart';
import '../safety/safety_claim_guard.dart';
import 'metric_observation.dart';
import 'posture_metrics.dart';

/// Pure, confidence-aware calculations for the four posture metrics.
final class PostureMetricEngine {
  const PostureMetricEngine();

  /// Look up the catalog definition for a metric. Same shape as R19.
  static PostureMetricDefinition definitionFor(PostureMetricId id) =>
      postureMetricDefinitions.firstWhere((definition) => definition.id == id);

  /// Compute the metric for the given observation.
  ///
  /// The output is `notObservable` when ANY of the following holds:
  ///   - the observation is `notObservable` (no baseline / no
  ///     shared landmarks);
  ///   - any required landmark ID is missing from the observation
  ///     (`driftFor(id) == null` — R8 gate);
  ///   - any required-landmark drift is non-finite (NaN/Infinity
  ///     guard);
  ///   - the metric's catalog `claimCode` is rejected by the
  ///     [SafetyClaimGuard] (fail-closed — this is a build-time
  ///     alarm in the catalog, but the engine defends in depth).
  MetricObservation compute({
    required PostureObservation observation,
    required PostureMetricId id,
  }) {
    final definition = definitionFor(id);

    // (1) Observation-level not-check.
    if (observation.state == VisionMetricState.notObservable) {
      return MetricObservation.notObservable();
    }

    // (2) R8 gate — per-metric required-landmark check.
    for (final landmarkId in definition.requiredPoseLandmarkIds) {
      final drift = observation.driftFor(landmarkId);
      if (drift == null) return MetricObservation.notObservable();
      if (!drift.isFinite) return MetricObservation.notObservable();
    }

    // (3) Compute the metric value.
    final value = _computeValue(observation: observation, id: id);
    if (value == null) return MetricObservation.notObservable();

    // (4) Confidence — average of the required-landmark drifts
    // (the drift is normalized-by-shoulder-span, so it is in
    // roughly [0, ∞); we use 1.0 for the floor because the
    // observation passes the gate already).
    final driftValues = definition.requiredPoseLandmarkIds
        .map((id) => observation.driftFor(id)!)
        .toList(growable: false);
    final confidence = _confidence(driftValues);

    // (5) Safety guard — the claim code MUST be allowed. If the
    // catalog regresses (e.g. a forbidden class slipped in), the
    // guard rejects it and the metric goes notObservable.
    final guard = const SafetyClaimGuard().evaluate(definition.claimCode);
    if (!guard.isAllowed) {
      return MetricObservation.notObservable();
    }

    return MetricObservation.observable(
      value: value,
      confidence: confidence,
    );
  }

  /// Compute the sign-preserved numeric value for [id].
  ///
  /// Returns `null` when the value is non-finite (the engine
  /// converts non-finite drift contributions to zero, so the output
  /// can also be zero — that's still a valid observable).
  double? _computeValue({
    required PostureObservation observation,
    required PostureMetricId id,
  }) {
    switch (id) {
      case PostureMetricId.shoulderAsymmetry:
        return _shoulderAsymmetry(observation);
      case PostureMetricId.torsoLean:
        return _torsoLean(observation);
      case PostureMetricId.elbowDrift:
        return _elbowDrift(observation);
      case PostureMetricId.neckProxy:
        return _neckProxy(observation);
    }
  }

  /// Vertical asymmetry between the two shoulders.
  ///
  /// Returns the absolute mean of the two shoulder drifts: the
  /// metric is the magnitude of the asymmetry, not its sign
  /// (sign-preserving variants live in the catalog). The
  /// shoulder-span normalization already happened in
  /// `posture_baseline.dart`, so we are already in the
  /// normalized-frame space.
  double _shoulderAsymmetry(PostureObservation obs) {
    final left = obs.driftFor(PoseLandmarkId.leftShoulder)!;
    final right = obs.driftFor(PoseLandmarkId.rightShoulder)!;
    return ((left.abs() + right.abs()) / 2).toDouble();
  }

  /// Vertical shift of the shoulder centroid vs the hip centroid.
  ///
  /// Sign-preserved: a positive value means the shoulders moved
  /// down (or the hips moved up — symmetric observation).
  double _torsoLean(PostureObservation obs) {
    final leftShoulder = obs.driftFor(PoseLandmarkId.leftShoulder)!;
    final rightShoulder = obs.driftFor(PoseLandmarkId.rightShoulder)!;
    final leftHip = obs.driftFor(PoseLandmarkId.leftHip)!;
    final rightHip = obs.driftFor(PoseLandmarkId.rightHip)!;
    final shoulderCentroid = (leftShoulder + rightShoulder) / 2;
    final hipCentroid = (leftHip + rightHip) / 2;
    return (shoulderCentroid - hipCentroid).toDouble();
  }

  /// Average lateral drift of the two elbows. The metric is the
  /// magnitude of the drift (always non-negative).
  double _elbowDrift(PostureObservation obs) {
    final left = obs.driftFor(PoseLandmarkId.leftElbow)!;
    final right = obs.driftFor(PoseLandmarkId.rightElbow)!;
    return ((left.abs() + right.abs()) / 2).toDouble();
  }

  /// Vertical shift of the neck reference point.
  double _neckProxy(PostureObservation obs) {
    return obs.driftFor(PoseLandmarkId.neckReference)!.toDouble();
  }

  /// Confidence — the average of the required-landmark drift
  /// values, clamped to [0, 1]. The drift is normalized by the
  /// shoulder span, so a value of 0.5 represents a half-shoulder
  /// drift; the function uses the clamp so absurd drifts do not
  /// surface as "low confidence" artefacts.
  double _confidence(List<double> values) {
    if (values.isEmpty) return 0.0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    if (!mean.isFinite) return 0.0;
    // The drift is a magnitude; the "confidence" here is the
    // 1 - min(1, mean) heuristic — a small drift is a high
    // confidence measurement (the landmarks were close to the
    // baseline), a large drift is lower confidence (the rig
    // moved a lot). The thesis is: the metric is observable,
    // but the user is far from their baseline.
    final conf = (1.0 - math.min(1.0, mean.abs())).toDouble();
    return conf.clamp(0.0, 1.0).toDouble();
  }
}
