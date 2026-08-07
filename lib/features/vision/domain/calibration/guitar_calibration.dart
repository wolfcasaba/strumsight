/// Perzisztált gitárgeometria (SDD Ch6 §13.3, E05-R10).
///
/// A gitár nyak / híd / polygon pontjai kizárólag normalizált
/// `[0, 1] × [0, 1]` térben tárolódnak (R7 §5.4, ADR 0181) — a kalibráció
/// így túléli a felbontásváltást.
///
/// **Pixelkoordináta-tilalom:** a perzisztált modellben SOHA nincs pixel —
/// minden pont `NormalizedPoint`. A release-build assert védelmén túl a
/// codec a saját `requireDouble(min:0, max:1)` helperével is ellenőriz
/// (R2).
///
/// **Polygon-korlát:** 3 ≤ csúcsok ≤ 8 — kevesebb degenerált, több
/// felesleges és a UI-t is elbizonytalanítja.
library;

import '../../../../core/camera/camera_coordinate_space.dart';

/// Hard upper bound on the number of neck-polygon vertices.
///
/// The bound is enforced both by the constructor (assert) and by the codec
/// (R2), so a corrupt record from a downgrade or a hand edit cannot sneak
/// past either layer.
const int maxNeckPolygonVertices = 8;

/// Hard lower bound on the number of neck-polygon vertices.
const int minNeckPolygonVertices = 3;

/// Immutable guitar-geometry calibration.
final class GuitarCalibration {
  const GuitarCalibration({
    required this.nutAnchor,
    required this.bridgeAnchor,
    required this.neckPolygon,
    required this.createdAt,
  }) : assert(neckPolygon.length >= minNeckPolygonVertices),
       assert(neckPolygon.length <= maxNeckPolygonVertices);

  /// Normalizált `[0,1]×[0,1]` pont a nut közelében.
  final NormalizedPoint nutAnchor;

  /// Normalizált `[0,1]×[0,1]` pont a híd / pickup közelében.
  final NormalizedPoint bridgeAnchor;

  /// A nyak-polygon csúcsai — normalizált térben, 3–8 elem.
  final List<NormalizedPoint> neckPolygon;

  /// A geometria rögzítésének UTC időbélyege.
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GuitarCalibration &&
          other.nutAnchor == nutAnchor &&
          other.bridgeAnchor == bridgeAnchor &&
          _listEquals(other.neckPolygon, neckPolygon) &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    nutAnchor,
    bridgeAnchor,
    Object.hashAll(neckPolygon),
    createdAt,
  );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
