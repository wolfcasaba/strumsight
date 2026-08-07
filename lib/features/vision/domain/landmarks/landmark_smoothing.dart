// E05-R13 — Landmark temporal smoothing (SDD §15.4, Kör 13 §Feladatok).
//
// Two profiles, one filter:
//   - picking  — must NOT eat fast strokes (≥ 90% amplitude preservation
//                on the brief's fast-strum fixture is a hard floor);
//   - fretting — heavier smoothing of the slow jitter the fretting hand
//                is known to produce (≥ 60% high-frequency noise reduction
//                on a noisy-but-stationary trajectory).
//
// The filter is a per-landmark EMA with profile-specific alpha, plus a
// velocity-based jump-rejection gate that drops any raw input whose
// per-frame distance from the previous smoothed value exceeds
// [LandmarkSmoothingFilter.jumpVelocityThreshold]. The threshold is tuned
// BETWEEN a real fast strum (per-frame delta ~ 0.08 normalized space at
// 30 fps) and a single-frame teleport (delta ~ 0.55+). See the
// `teleport*` acceptance cell for the falsification target.
//
// Stateless, pure Dart, framework-free. The assigner owns the per-track
// previous-value state; this class never holds it.
//
// The two profile alphas are exposed as constants for the
// `LandmarkSmoothingFilter.proofProfileSwap` mutation test
// (brief §6 / §10 "valódi-sértés próba"): swapping them makes the
// §6 acceptance matrix turn RED — which is the documented falsification
// signal that the profiles are not equivalent and the picking floor
// (≥ 90%) is a hard contract.

library;

import 'dart:math' as math;

import 'hand_landmarks.dart' show HandLandmarkId, HandLandmarkPoint;

/// Which temporal profile the filter applies.
///
/// The two values are intentionally distinct enum constants rather than
/// parameters on the filter constructor: they pin the *tunings*, not just
/// the policy. Future profiles (e.g. a `pose` profile for the R14 pipeline)
/// add a value here instead of adding a parameter.
enum SmoothingProfile { picking, fretting }

/// Per-frame exponential-moving-average filter for hand landmarks, with
/// velocity-based jump-rejection.
final class LandmarkSmoothingFilter {
  LandmarkSmoothingFilter({
    required this.profile,
    this.jumpVelocityThreshold = 0.30,
  });

  /// The smoothing profile.
  final SmoothingProfile profile;

  /// Maximum per-frame normalized distance allowed before the raw input
  /// is rejected as a teleport/jump. Tuned between a real fast strum
  /// (~ 0.08/frame) and a single-frame teleport (~ 0.55+/frame).
  final double jumpVelocityThreshold;

  /// Picking keeps the EMA alpha high so fast strokes survive — measured
  /// amplitude preservation is ≥ 90% on the §6 fast-strum fixture
  /// (`test/features/vision/domain/landmark_smoothing_test.dart`,
  /// "peak-to-peak amplitude preservation ≥ 90%"). The §10 falsification
  /// swap (forcing this constant to [frettingAlpha]) turns that cell red
  /// at ~ 60% — see the brief §10 valódi-sértés próba.
  static const double pickingAlpha = 0.85;

  /// Fretting uses a low alpha to crush the high-frequency jitter the
  /// fretting hand is known to produce — measured high-frequency noise
  /// reduction is ≥ 60% on the §6 noisy fixture
  /// (`test/features/vision/domain/landmark_smoothing_test.dart`,
  /// "high-frequency noise reduction ≥ 60%").
  static const double frettingAlpha = 0.30;

  double get _alpha =>
      profile == SmoothingProfile.picking ? pickingAlpha : frettingAlpha;

  /// Decide whether the raw input for this frame should be REJECTED.
  ///
  /// Returns `false` on the very first frame (no previous to compare
  /// against). The caller is expected to keep the previous smoothed
  /// value unchanged when the raw is rejected — that is what gives the
  /// jump-rejection its "hold the previous position" semantics.
  bool shouldReject({
    required HandLandmarkPoint? raw,
    required HandLandmarkPoint? previous,
    required int frameIndex,
  }) {
    if (raw == null || previous == null) return false;
    return _distance(raw, previous) > jumpVelocityThreshold;
  }

  /// Compute the smoothed value for a single landmark on this frame.
  ///
  /// `previous` is the previous frame's smoothed value (NOT the raw).
  /// On the first frame (`previous == null`) the filter is pass-through.
  /// The caller's responsibility to skip this call when
  /// [shouldReject] returns `true`.
  HandLandmarkPoint filter({
    required HandLandmarkPoint? raw,
    required HandLandmarkPoint? previous,
    required int frameIndex,
  }) {
    if (raw == null) {
      // No raw input — return the previous if available, otherwise a
      // deterministic zero (impossible to construct a HandLandmarkPoint
      // with NaN, but we can produce a zero visibility sentinel).
      if (previous != null) return previous;
      return HandLandmarkPoint(x: 0, y: 0, z: 0, visibility: 0);
    }
    if (previous == null) return raw;
    final alpha = _alpha;
    final x = alpha * raw.x + (1 - alpha) * previous.x;
    final y = alpha * raw.y + (1 - alpha) * previous.y;
    final z = alpha * raw.z + (1 - alpha) * previous.z;
    // Visibility is a 0..1 confidence — keep the MAX of raw and previous
    // (a smoothed value cannot exceed the highest observed confidence).
    final visibility = raw.visibility > previous.visibility
        ? raw.visibility
        : previous.visibility;
    return HandLandmarkPoint(x: x, y: y, z: z, visibility: visibility);
  }

  /// Filter a full landmark map. Landmarks absent from `raw` but present
  /// in `previous` are kept (EMA only, no zero-fill). Landmarks absent
  /// from both are absent.
  Map<HandLandmarkId, HandLandmarkPoint> filterMap({
    required Map<HandLandmarkId, HandLandmarkPoint>? raw,
    required Map<HandLandmarkId, HandLandmarkPoint>? previous,
    required int frameIndex,
  }) {
    if (raw == null) {
      return previous ?? const <HandLandmarkId, HandLandmarkPoint>{};
    }
    if (previous == null) {
      return Map<HandLandmarkId, HandLandmarkPoint>.from(raw);
    }
    final out = <HandLandmarkId, HandLandmarkPoint>{};
    final ids = <HandLandmarkId>{...raw.keys, ...previous.keys};
    for (final id in ids) {
      final r = raw[id];
      final p = previous[id];
      out[id] = filter(raw: r, previous: p, frameIndex: frameIndex);
    }
    return out;
  }

  static double _distance(HandLandmarkPoint a, HandLandmarkPoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}
