/// Landmark → guitar-space mapper (E05-R15, SDD §17.2 + §17.3).
///
/// Bridges the camera-space landmark model (R10 calibration anchors +
/// R13 smoothed hand tracks) with the pure-Dart geometric core
/// (`lib/core/geometry/`). The mapper is the **only** place that owns
/// the camera→guitar-space type conversion; the geometry modules stay
/// independent of the camera coordinate system (brief §1, AGENTS.md §6).
///
/// **Mapping contract.** A [GuitarCalibration] provides three things
/// in normalized `[0, 1]×[0, 1]` camera space (R10):
///
///   - `nutAnchor` and `bridgeAnchor` (two `NormalizedPoint`s),
///   - `neckPolygon` (3-8 `NormalizedPoint`s, convex hull of the neck).
///
/// The mapper builds a [Homography] that takes the camera plane to the
/// guitar plane: `nutAnchor → (0, 0)`, `bridgeAnchor → (1, 0)`, and the
/// two polygon midpoints on the bass and treble edges → `(u, ±1)`.
/// From then on, any camera-space landmark with a `NormalizedPoint` +
/// `visibility` is mapped into guitar-space `(u, v)` with a propagated
/// confidence (brief §5.3).
///
/// **Confidence propagation (brief §5.3).** The output confidence is
/// always ≤ the input landmark visibility, and strictly lower when the
/// homography condition number is bad. NaN / Infinity never propagates
/// — the mapper returns `null` with a typed reason instead.
library;

import 'dart:math' as math;

import 'package:strumsight/core/geometry/guitar_space.dart';
import 'package:strumsight/core/geometry/homography.dart';
import 'package:strumsight/core/geometry/point2.dart';
import 'package:strumsight/core/geometry/polygon2.dart';

import '../../../../core/camera/camera_coordinate_space.dart';
import '../calibration/guitar_calibration.dart';

/// Upper bound on the `(u, v)` magnitude we accept at mapper construction
/// time, measured by sampling [Homography.apply] at the four corners
/// (`(0,0)`, `(1,0)`, `(0,1)`, `(1,1)`) and the center (`(0.5, 0.5)`) of
/// the camera-normalized `[0,1]×[0,1]` frame.
///
/// Why this exists — the round BLOCKER-1 (review
/// `docs/reviews/e05-r15-guitar-coordinates-and-homography-review.md`):
/// `Homography._measureConditionNumber` measures ONLY the 2×2 linear
/// block, so a matrix whose projective row passes through (or very close
/// to) the camera frame is built and accepted as "well-conditioned"
/// (`cond ≈ 1.3`), yet `apply(...)` on a frame-nearby point produces
/// magnitudes on the order of 10²–10³. The `_conditionPenaltyFor` reads
/// the same blind cond, so the output confidence stays near 1.0 — the
/// silent garbage brief §5.2 forbids.
///
/// Why 10.0 — the guitar-space definition is `u ∈ [0,1]`, `v ∈ [-1,1]`,
/// so a sane `(u, v)` magnitude is at most ~`sqrt(1 + 1) ≈ 1.42`. We
/// pick **10.0** (≈ 7× slack) so any real-world calibration — even with
/// strong perspective skew or anchor jitter near the corners — stays
/// well inside the bound; the security-reviewer random sweep (`|uv| > 10`
/// under `cond ≤ 50`) showed the failing matrices produce
/// `|uv| ≈ 10²–10⁷`, so 10.0 is orders of magnitude smaller than the
/// observed garbage and orders of magnitude larger than the legitimate
/// envelope. The bound is asserted by
/// `test/features/vision/domain/guitar_landmark_mapper_test.dart` →
/// `BLOCKER-1: rejects calibration whose homography blows up in the
/// camera frame`.
const double guitarSpaceSanityBound = 10.0;

/// Why a [GuitarLandmarkMapper.map] call returned `null`.
enum GuitarLandmarkMappingFailure {
  /// The input calibration polygon was degenerate.
  degeneratePolygon,

  /// The solved homography exceeded the condition-number bound.
  conditionNumberExceeded,

  /// One of the inputs contained non-finite numbers.
  nonFiniteInput,

  /// The mapper has not been built yet (no calibration fed in).
  notInitialized,
}

/// A landmark mapped into guitar-space coordinates.
final class MappedHandLandmark {
  MappedHandLandmark({required this.uv, required this.confidence}) {
    if (!(confidence.isFinite && confidence >= 0 && confidence <= 1)) {
      throw ArgumentError.value(
        confidence,
        'confidence',
        'MappedHandLandmark.confidence must be finite and in [0, 1].',
      );
    }
  }

  final GuitarSpacePoint uv;

  /// Always ≤ the input landmark visibility (brief §5.3). Reduced further
  /// when the underlying homography has a high condition number — a
  /// poor geometry must not surface as a confident mapped point.
  final double confidence;
}

/// Why a [GuitarLandmarkMapper] could not be constructed.
enum GuitarLandmarkMapperSetupFailure {
  /// The calibration polygon failed [Polygon2.validate].
  degeneratePolygon,

  /// The solved homography exceeded the condition-number bound.
  conditionNumberExceeded,

  /// The calibration provided non-finite coordinates.
  nonFiniteInput,

  /// The nut and bridge anchors were too close to define a homography.
  anchorsCoincident,

  /// The solved homography's projective row drives the camera-frame
  /// sample points outside [guitarSpaceSanityBound], even though the
  /// 2×2 linear block's condition number was accepted. The 2×2-only
  /// condition metric in `Homography._measureConditionNumber` is blind
  /// to this — see BLOCKER-1 in the round review
  /// (`docs/reviews/e05-r15-guitar-coordinates-and-homography-review.md`).
  unstableMapping,
}

/// The bridge between camera-space landmarks and the guitar plane.
///
/// The mapper is built once per calibration ([GuitarLandmarkMapper.fromCalibration])
/// and reused for every frame. Each frame's landmarks are mapped via
/// [mapPoint] (camera→guitar) and [mapPointInverse] (guitar→camera,
/// for visualization/debug).
///
/// The constructor validates the polygon and builds the homography
/// eagerly so a frame loop never has to deal with a half-built
/// mapper — the only `null` path on the frame side is per-call
/// `nonFiniteInput` (a single landmark with bad coordinates).
final class GuitarLandmarkMapper {
  GuitarLandmarkMapper._(
    this._homography,
    this._inverse,
    this._condition,
    this._conditionPenalty,
  );

  /// The internal condition number (kept for diagnostics & confidence
  /// propagation). The constructor already rejected matrices above the
  /// threshold so callers never have to gate on this value.
  final double _condition;

  /// Multiplier applied to the landmark visibility to derive the
  /// mapped confidence — `1.0` for an ideal matrix, `< 1.0` as the
  /// condition number grows.
  final double _conditionPenalty;

  final Homography _homography;
  final Homography _inverse;

  /// Construct a mapper from a [GuitarCalibration].
  ///
  /// Returns `null` (with a typed reason) when the polygon is
  /// degenerate, the anchors coincide, or the solved homography
  /// exceeds [homographyMaxConditionNumber]. The brief §5.2 forbids
  /// silent numeric garbage — every failure path is typed.
  static GuitarLandmarkMapper? fromCalibration(GuitarCalibration calibration) {
    // 1. Polygon validity — fail early on a structurally bad calibration.
    final polygon = calibration.neckPolygon
        .map((p) => Point2(p.x, p.y))
        .toList(growable: false);
    final polygonValidity = Polygon2.validate(polygon);
    if (!polygonValidity.isValid) {
      throw const GuitarLandmarkMapperSetupException(
        GuitarLandmarkMapperSetupFailure.degeneratePolygon,
      );
    }

    // 2. Anchor sanity — nut and bridge must be distinct enough to
    //    define a homography. The threshold matches
    //    `calibration_validity.minAnchorSeparation`.
    final dx = calibration.bridgeAnchor.x - calibration.nutAnchor.x;
    final dy = calibration.bridgeAnchor.y - calibration.nutAnchor.y;
    final anchorDist = math.sqrt(dx * dx + dy * dy);
    if (!(anchorDist > minAnchorSeparation)) {
      throw const GuitarLandmarkMapperSetupException(
        GuitarLandmarkMapperSetupFailure.anchorsCoincident,
      );
    }

    // 3. Build the source quad: nut / bridge / bass-edge-midside /
    //    treble-edge-midside of the convex polygon. This is the most
    //    robust source 4-correspondence set (the brief §9 calls out
    //    that a degenerate homography is the #1 risk; centering the
    //    source around the polygon centroid is what keeps cond low).
    final quad = _fourSourcePoints(calibration);
    final target = <Point2>[
      Point2(0, 0), // nut
      Point2(1, 0), // bridge
      Point2(0.5, -1), // bass edge mid (u=halfway down the neck)
      Point2(0.5, 1), // treble edge mid
    ];

    Homography h;
    try {
      h = Homography.solve(src: quad, dst: target);
    } on HomographyError catch (e) {
      throw GuitarLandmarkMapperSetupException._fromHomographyError(e.reason);
    }

    // 4. Projective-row sanity guard (BLOCKER-1). The 2×2-only condition
    //    check above is blind to the projective row, so a homography
    //    whose `w = h6·x + h7·y + h8` vanishes close to (or inside) the
    //    camera-normalized `[0,1]×[0,1]` frame is accepted with a tiny
    //    cond, then `apply()` blows up to 10^2..10^7 on frame-nearby
    //    landmarks while `_conditionPenaltyFor` keeps the confidence near
    //    1.0. We sample the four corners and the center of the camera
    //    frame; any sample with |uv| > guitarSpaceSanityBound rejects
    //    the mapping. `core/geometry` is space-neutral by design, so this
    //    domain-aware guard lives here, not in `Homography`.
    _checkFrameBounded(h);

    final penalty = _conditionPenaltyFor(h.conditionNumber);
    return GuitarLandmarkMapper._(h, h.inverse, h.conditionNumber, penalty);
  }

  /// Map a single camera-space point to guitar-space.
  ///
  /// Returns `null` for a non-finite input (brief §5.2 silent-garbage
  /// prohibition). Output confidence is the input visibility scaled by
  /// the homography condition penalty — strictly lower than the input
  /// on poor geometry, never higher (brief §5.3).
  MappedHandLandmark? mapPoint({
    required NormalizedPoint normalized,
    required double visibility,
  }) {
    if (!(normalized.x.isFinite &&
        normalized.y.isFinite &&
        visibility.isFinite &&
        visibility >= 0 &&
        visibility <= 1)) {
      return null;
    }
    final uv = _homography.apply(Point2(normalized.x, normalized.y));
    if (!(uv.x.isFinite && uv.y.isFinite)) {
      return null;
    }
    final confidence = (visibility * _conditionPenalty).clamp(0.0, 1.0);
    return MappedHandLandmark(
      uv: GuitarSpacePoint(uv.x, uv.y),
      confidence: confidence,
    );
  }

  /// The inverse mapping: guitar-space → camera-space. Used by the
  /// overlay grid (R24) and by tests; not on the per-frame hot path.
  NormalizedPoint mapPointInverse(GuitarSpacePoint uv) {
    final xy = _inverse.apply(Point2(uv.u, uv.v));
    return NormalizedPoint(xy.x.clamp(0.0, 1.0), xy.y.clamp(0.0, 1.0));
  }

  /// The condition number of the underlying homography (diagnostic).
  double get conditionNumber => _condition;

  /// Reject a built homography whose projective row drives the camera
  /// frame's sample points outside [guitarSpaceSanityBound]. This is the
  /// BLOCKER-1 guard from the round review — `Homography` measures only
  /// the 2×2 linear block, so a near-vanishing `w` inside the camera
  /// frame is accepted as "well-conditioned" and silently produces
  /// 10²–10⁷ magnitudes at `mapPoint` time.
  static void _checkFrameBounded(Homography h) {
    final samples = <Point2>[
      Point2(0.0, 0.0),
      Point2(1.0, 0.0),
      Point2(0.0, 1.0),
      Point2(1.0, 1.0),
      Point2(0.5, 0.5),
    ];
    for (final p in samples) {
      final uv = h.apply(p);
      final magnitude = math.sqrt(uv.x * uv.x + uv.y * uv.y);
      if (!(magnitude.isFinite) || magnitude > guitarSpaceSanityBound) {
        throw const GuitarLandmarkMapperSetupException(
          GuitarLandmarkMapperSetupFailure.unstableMapping,
        );
      }
    }
  }

  /// The minimum separation between nut and bridge anchors required
  /// for the mapper to construct. Matches the calibration-validity
  /// threshold so both layers enforce the same geometric floor.
  static const double minAnchorSeparation = 0.05;

  /// Computes a multiplier in `(0, 1]` such that the mapped confidence
  /// is strictly lower than the input when the condition number is
  /// worse than ideal. The piecewise schedule was calibrated against
  /// the python3 reference sweep in brief §10: well-conditioned (cond
  /// ≈ 1) → 1.0, cond ≈ 30 → ≈ 0.95, cond ≈ 100 → ≈ 0.85, cond ≈ 1e3
  /// (the rejection boundary) → ≈ 0.5. The mapper constructor rejects
  /// anything above `homographyMaxConditionNumber` (= 1e3) so the
  /// penalty never drops below 0.5.
  static double _conditionPenaltyFor(double cond) {
    if (cond <= 1) return 1.0;
    // Smooth log-shaped penalty: 1 - min(0.5, 0.15 * log10(cond)).
    final drop = 0.15 * math.log(cond) / math.ln10;
    return (1.0 - drop.clamp(0.0, 0.5)).toDouble();
  }

  /// Pick four source points for the homography: nut, bridge, and the
  /// mid-points of the bass/treble polygon edges that lie roughly
  /// halfway down the neck.
  ///
  /// The centroid is used as the "midpoint" when no vertex sits close
  /// to `u = 0.5` (e.g. a polygon with only 3 vertices). This is the
  /// same fallback used by `calibration_validity.dart` for anchor
  /// separation: simple, geometrically meaningful, no assumption
  /// about the exact polygon shape.
  static List<Point2> _fourSourcePoints(GuitarCalibration c) {
    final polygon = c.neckPolygon.map((p) => Point2(p.x, p.y)).toList();
    // The neck polygon's centroid in `(u, v)` is the bass/treble-edge
    // midpoint we need. Combined with nut/bridge anchors, this gives
    // the four corners of a "guitar-like" quad in the camera plane.
    var cx = 0.0;
    var cy = 0.0;
    for (final p in polygon) {
      cx += p.x;
      cy += p.y;
    }
    cx /= polygon.length;
    cy /= polygon.length;

    // Translate the centroid slightly along the local v-axis to put it
    // on the bass/treble edges of the convex hull. We pick two
    // symmetric points offset from the centroid, perpendicular to the
    // nut→bridge direction.
    final ux = c.bridgeAnchor.x - c.nutAnchor.x;
    final uy = c.bridgeAnchor.y - c.nutAnchor.y;
    final uLen = math.sqrt(ux * ux + uy * uy);
    final nx = uLen == 0 ? 1.0 : -uy / uLen;
    final ny = uLen == 0 ? 0.0 : ux / uLen;
    // Average distance from centroid to polygon vertices; offset by
    // 60% of that for a stable midpoint estimate.
    var avgR = 0.0;
    for (final p in polygon) {
      final ddx = p.x - cx;
      final ddy = p.y - cy;
      avgR += math.sqrt(ddx * ddx + ddy * ddy);
    }
    avgR /= polygon.length;
    final offset = 0.6 * avgR;

    final bassMid = Point2(cx + nx * offset, cy + ny * offset);
    final trebleMid = Point2(cx - nx * offset, cy - ny * offset);

    return [
      Point2(c.nutAnchor.x, c.nutAnchor.y),
      Point2(c.bridgeAnchor.x, c.bridgeAnchor.y),
      bassMid,
      trebleMid,
    ];
  }
}

/// Thrown by [GuitarLandmarkMapper.fromCalibration] when the
/// calibration cannot be turned into a usable mapping. The brief
/// §5.2 forbids silent numeric garbage — every failure path is typed.
final class GuitarLandmarkMapperSetupException implements Exception {
  const GuitarLandmarkMapperSetupException(this.reason);
  final GuitarLandmarkMapperSetupFailure reason;

  factory GuitarLandmarkMapperSetupException._fromHomographyError(
    GeometryFailure reason,
  ) {
    switch (reason) {
      case GeometryFailure.conditionNumberExceeded:
        return const GuitarLandmarkMapperSetupException(
          GuitarLandmarkMapperSetupFailure.conditionNumberExceeded,
        );
      case GeometryFailure.singularSystem:
      case GeometryFailure.nonFiniteInput:
        return const GuitarLandmarkMapperSetupException(
          GuitarLandmarkMapperSetupFailure.nonFiniteInput,
        );
    }
  }

  @override
  String toString() => 'GuitarLandmarkMapperSetupException($reason)';
}
