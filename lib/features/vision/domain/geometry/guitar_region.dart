/// Guitar region classifier (E05-R15, SDD §17.2).
///
/// Defines three geometric regions on the guitar plane and a single
/// classifier that returns which one a mapped point lies in. The
/// regions are described in `(u, v)` coordinates (nut→bridge × bass→
/// treble); the `u`-axis cut points come from the brief's well-known
/// guitar layout — the body starts at the 12th fret, the neck extends
/// from the nut to the body join, and the picking zone covers the
/// rightmost third of the body.
///
/// **Conservative defaults.** The cut points are tunables
/// (`neckToBodyU`, `pickingZoneUSpan`) so a future round can override
/// them per-guitar without touching the classifier; the defaults here
/// match a standard 6-string electric/acoustic.
library;

import 'package:strumsight/core/geometry/guitar_space.dart';

/// A geometric region of the guitar plane (E05-R15, SDD §17.2).
enum GuitarRegion { neck, body, pickingZone, outsideGuitar }

/// Configuration for the [GuitarRegionClassifier].
///
/// Defaults describe a standard 6-string guitar: the body starts at
/// the 12th fret (`neckToBodyU ≈ 0.5`), the picking zone covers the
/// outermost third of the body.
final class GuitarRegionThresholds {
  const GuitarRegionThresholds({
    this.neckToBodyU = 12 / 22,
    this.pickingZoneUSpan = 1.0 / 3.0,
  }) : assert(neckToBodyU > 0 && neckToBodyU < 1),
       assert(pickingZoneUSpan > 0 && pickingZoneUSpan <= 1);

  /// The `u` value where the body begins. For a 22-fret guitar,
  /// 12/22 ≈ 0.545 puts the neck→body boundary at the 12th fret.
  final double neckToBodyU;

  /// Fraction of the body (along `u`) that the picking zone covers,
  /// measured from the bridge end. `1/3` matches the area between the
  /// bridge pickup and the saddle on a standard electric.
  final double pickingZoneUSpan;
}

/// Pure-function classifier that maps a [GuitarSpacePoint] into one of
/// the four [GuitarRegion] values.
///
/// The classifier is **side-effect-free** and **total**: every input
/// returns a value. Out-of-plane points (`|v| > 1` or `u` outside the
/// `[0, 1]` guitar plane) fall into [GuitarRegion.outsideGuitar] so
/// downstream code never has to deal with `null`.
abstract final class GuitarRegionClassifier {
  /// The default cut points: 12th-fret neck/body join + picking zone
  /// covering the outermost third of the body.
  static const GuitarRegionThresholds defaults = GuitarRegionThresholds();

  /// Classify a single mapped guitar point.
  static GuitarRegion classify(
    GuitarSpacePoint point, {
    GuitarRegionThresholds thresholds = defaults,
  }) {
    if (point.u < 0 || point.u > 1) return GuitarRegion.outsideGuitar;
    if (point.v < -1 || point.v > 1) return GuitarRegion.outsideGuitar;

    if (point.u <= thresholds.neckToBodyU) {
      return GuitarRegion.neck;
    }
    final pickingStart = 1.0 - thresholds.pickingZoneUSpan;
    if (point.u >= pickingStart) {
      return GuitarRegion.pickingZone;
    }
    return GuitarRegion.body;
  }

  /// Bulk classify — useful for whole-hand mapping (one sweep per frame).
  static Map<GuitarSpacePoint, GuitarRegion> classifyAll(
    Iterable<GuitarSpacePoint> points, {
    GuitarRegionThresholds thresholds = defaults,
  }) {
    final result = <GuitarSpacePoint, GuitarRegion>{};
    for (final p in points) {
      result[p] = classify(p, thresholds: thresholds);
    }
    return result;
  }
}
