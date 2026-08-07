/// Pure-Dart 2D point primitive (E05-R15, SDD §18).
///
/// **Space-neutral math primitive.** This is *not* a camera point and *not*
/// a guitar-space point — those concepts live in `core/camera` and in the
/// `core/geometry/guitar_space` module respectively. `Point2` is the
/// arithmetic primitive they share: coordinates are finite `double`s without
/// any `[0, 1]` or coordinate-system assertion.
///
/// **No `dart:ui`.** The `core/geometry` module is framework-free so the
/// downstream pure-Dart geometric algorithms (homography DLT, polygon
/// predicates, guitar-space mapper) stay testable without a Flutter binding.
///
/// The module deliberately does not import `core/camera` either: a
/// `NormalizedPoint` and a `Point2` are intentionally distinct types so a
/// caller cannot accidentally pass a camera-normalized point into the
/// homography solver or vice versa (see E05-R15 brief §1, calibration model
/// in `features/vision/domain/calibration/`).
library;

import 'dart:math' as math;

/// Immutable 2D point.
///
/// Coordinates are NOT bound to any coordinate system — `Point2` is the
/// shared arithmetic primitive between the camera-space types
/// (`NormalizedPoint` etc. in `core/camera`) and the guitar-space type
/// (`GuitarSpacePoint` in `guitar_space.dart`). Conversion happens at the
/// feature boundary, never inside `core/geometry`.
///
/// `Point2` itself does NOT enforce finiteness — it is a pure container.
/// Each module that consumes a `Point2` (homography solver, polygon
/// predicates, etc.) is responsible for the geometric invariant it cares
/// about. This lets `Homography.solve` return a typed
/// `GeometryFailure.nonFiniteInput` reason for non-finite inputs (brief
/// §5.2) instead of a generic `ArgumentError` from the constructor.
final class Point2 {
  Point2(this.x, this.y);

  final double x;
  final double y;

  Point2 operator +(Point2 other) => Point2(x + other.x, y + other.y);
  Point2 operator -(Point2 other) => Point2(x - other.x, y - other.y);
  Point2 operator *(double scale) => Point2(x * scale, y * scale);

  double distanceTo(Point2 other) {
    final dx = other.x - x;
    final dy = other.y - y;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  bool operator ==(Object other) =>
      other is Point2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Point2($x, $y)';
}
