/// Pure-Dart polygon predicates for the guitar-coordinates layer
/// (E05-R15, SDD §17.3 + §18.3).
///
/// The module deliberately exposes a small, complete predicate set:
///   - `signedArea` (shoelace; sign carries orientation),
///   - `isConvex`   (every cross product of consecutive edges has the same sign),
///   - `contains`   (ray-casting, signed-area convention).
///
/// Degenerate polygons (collinear or zero-area) are signalled by an explicit
/// `PolygonDegenerateReason` rather than by returning a quiet `false`: the
/// caller decides whether to ignore them or to fail, but the silent-numeric-
/// garbage rule (SDD §17.3, E05-R15 brief §5.2) forbids returning "just
/// false" for a case that was actually a runtime bug.
library;

import 'point2.dart';

/// Why a polygon's geometric predicate is not safe to use.
enum PolygonDegenerateReason {
  /// Fewer than 3 vertices — not a polygon.
  tooFewVertices,

  /// Signed area is exactly zero — vertices are collinear / coincident.
  zeroSignedArea,
}

/// Result of validating a polygon for geometric predicates.
final class PolygonValidity {
  const PolygonValidity._(this.isValid, this.reason);

  /// The polygon can be used by `isConvex`/`contains`/orientation logic.
  factory PolygonValidity.valid() => const PolygonValidity._(true, null);

  /// The polygon cannot be used; [reason] carries the priority-ordered cause.
  factory PolygonValidity.degenerate(PolygonDegenerateReason reason) =>
      PolygonValidity._(false, reason);

  final bool isValid;
  final PolygonDegenerateReason? reason;
}

/// Shared polygon predicates.
///
/// All methods accept a list of vertices that already passed
/// `validatePolygon`. Callers that bypass that step must reproduce the
/// same checks themselves; the brief forbids silent numeric garbage.
abstract final class Polygon2 {
  /// Shoelace signed area. Positive when vertices are counter-clockwise.
  static double signedArea(List<Point2> vertices) {
    if (vertices.length < 3) return 0;
    var sum = 0.0;
    for (var i = 0; i < vertices.length; i++) {
      final a = vertices[i];
      final b = vertices[(i + 1) % vertices.length];
      sum += (a.x * b.y) - (b.x * a.y);
    }
    return sum / 2;
  }

  /// Priority-ordered polygon validity check.
  ///
  /// Order: `tooFewVertices` first (structural), then `zeroSignedArea` (the
  /// most common numerical sign of a bad polygon). Matches the
  /// `CalibrationInvalidationReason` priority pattern in
  /// `features/vision/domain/calibration/calibration_validity.dart`.
  static PolygonValidity validate(List<Point2> vertices) {
    if (vertices.length < 3) {
      return PolygonValidity.degenerate(PolygonDegenerateReason.tooFewVertices);
    }
    final area = signedArea(vertices);
    if (area.abs() <= polygonDegenerateAreaTolerance) {
      return PolygonValidity.degenerate(PolygonDegenerateReason.zeroSignedArea);
    }
    return PolygonValidity.valid();
  }

  /// True iff every interior angle is ≤ 180° and vertices are not
  /// degenerate. Returns `false` (not throws) for degenerate polygons so a
  /// caller can branch on a single boolean — but a `false` answer that is
  /// actually caused by degeneracy MUST be paired with a separate
  /// [validate] check so the failure mode is explicit.
  static bool isConvex(List<Point2> vertices) {
    final validity = validate(vertices);
    if (!validity.isValid) return false;
    var previousSign = 0;
    final n = vertices.length;
    for (var i = 0; i < n; i++) {
      final a = vertices[i];
      final b = vertices[(i + 1) % n];
      final c = vertices[(i + 2) % n];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross.abs() <= polygonDegenerateCrossTolerance) continue;
      final sign = cross.isNegative ? -1 : 1;
      if (previousSign == 0) {
        previousSign = sign;
      } else if (sign != previousSign) {
        return false;
      }
    }
    return previousSign != 0;
  }

  /// Ray-casting point-in-polygon. Uses the same orientation convention
  /// as [signedArea]: positive ⇒ counter-clockwise winding.
  static bool contains(List<Point2> vertices, Point2 point) {
    if (!validate(vertices).isValid) return false;
    var inside = false;
    final n = vertices.length;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      final a = vertices[i];
      final b = vertices[j];
      final intersects =
          ((a.y > point.y) != (b.y > point.y)) &&
          (point.x <
              (b.x - a.x) * (point.y - a.y) / ((b.y - a.y).abs() + 1e-300) +
                  a.x);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  /// Orientation by sign of the signed area. `null` when the polygon is
  /// degenerate so a caller never confuses "flat" with a direction.
  static PolygonOrientation? orientation(List<Point2> vertices) {
    final area = signedArea(vertices);
    if (area.abs() <= polygonDegenerateAreaTolerance) return null;
    return area.isNegative
        ? PolygonOrientation.clockwise
        : PolygonOrientation.counterClockwise;
  }
}

/// Winding direction of a non-degenerate polygon.
enum PolygonOrientation { clockwise, counterClockwise }

/// Below this absolute signed area the polygon is treated as flat.
const double polygonDegenerateAreaTolerance = 1e-12;

/// Below this absolute cross-product magnitude consecutive edges are
/// treated as collinear (used by the convexity predicate so the test
/// does not classify a numerical-noise spike as a reflex angle).
const double polygonDegenerateCrossTolerance = 1e-12;

/// Smallest valid vertex count.
const int polygonMinVertices = 3;
