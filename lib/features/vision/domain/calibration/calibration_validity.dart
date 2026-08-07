/// Kalibráció érvényességi policy (SDD Ch6 §13.4, E05-R10).
///
/// Az SDD hét invalidation-triggers felsorol, de a mérce PONTOSAN öt
/// cellát kér (R6 megerősítés): a hiányzó kettő ma nem mérhető (tracking
/// confidence → R16, instrument change → nincs `Instrument` domain-fogalom),
/// a hetedik (séma breaking change) a migrációs mechanizmus felelőssége.
///
/// A függvény prioritási sorrendet ad, hogy determinisztikus legyen:
/// a legerősebb trigger (`cameraDeviceChanged`) minden mást megelőz,
/// így egy kompromisszum-mentes hibaüzenet jut el a UI-ig.
library;

import '../../../../core/camera/camera_coordinate_space.dart';
import '../vision_setup_profile.dart';
import 'camera_calibration_profile.dart';
import 'guitar_calibration.dart';

/// The five invalidation reasons the calibration matrix exposes.
///
/// The order of declaration matters: it pins the priority used by
/// [CalibrationValidity.evaluate] and is asserted by a test that catches
/// accidental additions.
enum CalibrationInvalidationReason {
  /// The active camera device changed (back ↔ front).
  cameraDeviceChanged,

  /// The active camera rotation changed.
  orientationChanged,

  /// The active zoom moved outside the documented tolerance.
  zoomChangedBeyondTolerance,

  /// The stored calibration timestamp is older than [CalibrationValidity.maxAge].
  timestampExpired,

  /// The stored geometry is too degenerate to trust (anchors too close,
  /// polygon below the minimum vertex count, etc.).
  degenerateGeometry,
}

/// Pure-function validity policy for the camera+guitar calibration bundle.
abstract final class CalibrationValidity {
  /// A kalibráció ezen időnél idősebbnek tekintendő.
  static const Duration maxAge = Duration(days: 30);

  /// A zoom ± ennyi toleranciát enged anélkül, hogy a kalibrációt
  /// érvénytelennek nyilvánítanánk.
  static const double zoomTolerance = 0.1;

  /// A nut és bridge anchorok közötti minimális normalizált távolság.
  /// Ezen alul a geometria degeneráltnak tekintendő.
  static const double minAnchorSeparation = 0.05;

  /// A polygon minimális csúcsszáma (a `GuitarCalibration` konstruktorával
  /// szinkronban).
  static const int minPolygonVertices = 3;

  /// Decide whether the stored [profile] + [guitar] calibration is still
  /// valid for the runtime context, and if not, why.
  ///
  /// Returns `null` when the calibration is still valid. The check is
  /// **priority-ordered**: when multiple triggers are active, the one
  /// returned is the one the user can fix first; a hardware change always
  /// wins over a software one.
  static CalibrationInvalidationReason? evaluate({
    required CameraCalibrationProfile profile,
    required GuitarCalibration guitar,
    required VisionCameraPreference currentCamera,
    required CameraRotation currentOrientation,
    required double currentZoom,
    required DateTime now,
  }) {
    if (profile.camera != currentCamera) {
      return CalibrationInvalidationReason.cameraDeviceChanged;
    }
    if (profile.orientation != currentOrientation) {
      return CalibrationInvalidationReason.orientationChanged;
    }
    if ((currentZoom - profile.zoom).abs() > zoomTolerance) {
      return CalibrationInvalidationReason.zoomChangedBeyondTolerance;
    }
    if (now.difference(profile.createdAt) > maxAge) {
      return CalibrationInvalidationReason.timestampExpired;
    }
    if (_isDegenerate(guitar)) {
      return CalibrationInvalidationReason.degenerateGeometry;
    }
    return null;
  }

  static bool _isDegenerate(GuitarCalibration guitar) {
    if (guitar.neckPolygon.length < minPolygonVertices) return true;
    final dx = guitar.bridgeAnchor.x - guitar.nutAnchor.x;
    final dy = guitar.bridgeAnchor.y - guitar.nutAnchor.y;
    final sepSquared = dx * dx + dy * dy;
    final minSeparation = minAnchorSeparation;
    return sepSquared < (minSeparation * minSeparation);
  }
}
