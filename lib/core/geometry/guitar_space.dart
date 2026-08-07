/// Guitar-space coordinate type (E05-R15, SDD §17.2).
///
/// The guitar plane is described by two coordinates:
///
///   - `u ∈ [0, 1]` — the *nut → bridge* axis (`0` at the nut, `1` at the
///     bridge). Used by every fret-relative metric.
///   - `v ∈ ℝ`     — the *bass → treble* cross axis. Sign carries
///     direction (negative = bass-side, positive = treble-side). The
///     absolute scale of `v` is the **homography-derived half-width** of
///     the neck polygon — i.e. how far from the centerline one full
///     neck width is in guitar-space units. A point with `|v| == 1` lies
///     on the bass/treble edge of the neck.
///
/// **Type-safety rationale (brief §1, R07 mirror).** `GuitarSpacePoint`
/// is a distinct type from `Point2` and from the camera-space
/// `NormalizedPoint`, so a caller cannot pass a camera-normalized
/// `(x, y)` to a `u, v` consumer or vice versa. The mapping is owned
/// by `features/vision/domain/geometry/guitar_landmark_mapper.dart`,
/// not by `core/geometry`.
///
/// **Balkezes / jobbkezes parity (brief §5.5).** The mirror that
/// reverses the cross axis for left-handed players is NOT applied
/// here — `u, v` describe the *guitar plane*, not the camera frame,
/// so left-handed and right-handed players share the same `GuitarSpace`
/// definition. The hand-role assignment lives in `HandTrackAssigner`.
library;

import 'dart:math' as math;

/// A point on the guitar plane.
///
/// `u` is the along-neck axis (nut→bridge), `v` is the cross-neck axis
/// (bass→treble, signed). The half-width of the neck in guitar-space
/// units is `1.0` by convention — see the class doc for the geometric
/// meaning.
final class GuitarSpacePoint {
  GuitarSpacePoint(this.u, this.v) {
    if (!u.isFinite || !v.isFinite) {
      throw ArgumentError(
        'GuitarSpacePoint coordinates must be finite (got ($u, $v)).',
      );
    }
  }

  final double u;
  final double v;

  GuitarSpacePoint operator +(GuitarSpacePoint other) =>
      GuitarSpacePoint(u + other.u, v + other.v);
  GuitarSpacePoint operator -(GuitarSpacePoint other) =>
      GuitarSpacePoint(u - other.u, v - other.v);
  GuitarSpacePoint operator *(double scale) =>
      GuitarSpacePoint(u * scale, v * scale);

  /// Squared distance between two points (cheap, no sqrt).
  double squaredDistanceTo(GuitarSpacePoint other) {
    final du = other.u - u;
    final dv = other.v - v;
    return du * du + dv * dv;
  }

  /// Euclidean distance between two points.
  double distanceTo(GuitarSpacePoint other) =>
      math.sqrt(squaredDistanceTo(other));

  @override
  bool operator ==(Object other) =>
      other is GuitarSpacePoint && other.u == u && other.v == v;

  @override
  int get hashCode => Object.hash(u, v);

  @override
  String toString() => 'GuitarSpacePoint($u, $v)';
}

/// The bounding rectangle of the guitar plane in `(u, v)` coordinates.
///
/// `uMin`/`uMax` are typically `[0, 1]` (nut → bridge); `vMin`/`vMax`
/// describe the full neck width (typically `[-1, 1]`, with `|v| == 1`
/// on the bass/treble edge). Used by `GuitarRegion` to classify a
/// mapped point without rebuilding the homography.
final class GuitarSpaceBounds {
  GuitarSpaceBounds({
    required this.uMin,
    required this.uMax,
    required this.vMin,
    required this.vMax,
  }) {
    if (!(uMin.isFinite && uMax.isFinite && vMin.isFinite && vMax.isFinite)) {
      throw ArgumentError('GuitarSpaceBounds must have finite coordinates.');
    }
    if (uMin > uMax || vMin > vMax) {
      throw ArgumentError(
        'GuitarSpaceBounds requires uMin <= uMax and vMin <= vMax.',
      );
    }
  }

  final double uMin;
  final double uMax;
  final double vMin;
  final double vMax;

  double get uRange => uMax - uMin;
  double get vRange => vMax - vMin;

  /// `true` iff `point` lies inside the bounds (inclusive on all edges).
  bool contains(GuitarSpacePoint point) =>
      point.u >= uMin && point.u <= uMax && point.v >= vMin && point.v <= vMax;

  @override
  bool operator ==(Object other) =>
      other is GuitarSpaceBounds &&
      other.uMin == uMin &&
      other.uMax == uMax &&
      other.vMin == vMin &&
      other.vMax == vMax;

  @override
  int get hashCode => Object.hash(uMin, uMax, vMin, vMax);
}

/// A point in guitar-space together with its propagated confidence.
///
/// The mapper produces these; downstream consumers (region classifier,
/// metric engine) read `confidence` to gate the usage of the point.
final class MappedGuitarPoint {
  MappedGuitarPoint({required this.point, required this.confidence}) {
    if (!(confidence >= 0 && confidence <= 1)) {
      throw ArgumentError.value(
        confidence,
        'confidence',
        'MappedGuitarPoint.confidence must be in [0, 1].',
      );
    }
  }

  final GuitarSpacePoint point;

  /// Confidence in `[0, 1]`. By construction (`GuitarLandmarkMapper`)
  /// this is **always ≤ the input landmark's `visibility`**, and
  /// strictly less on worse-conditioned geometry. The brief §5.3
  /// forbids confidence growth through the geometric step.
  final double confidence;

  @override
  bool operator ==(Object other) =>
      other is MappedGuitarPoint &&
      other.point == point &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(point, confidence);
}
