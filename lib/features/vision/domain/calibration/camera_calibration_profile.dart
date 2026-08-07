/// Perzisztált kamera-kalibrációs profil (SDD Ch6 §13.3, E05-R10).
///
/// A profil a `VisionCameraPreference`-t (back/front) és a `CameraRotation`
/// (0/90/180/270) és a `VisionSetupProfile`-t (a meglévő, változatlan
/// négyértékű setup enum) fogja egyetlen, immutable rekordba, plusz egy
/// normalizált zoom-értéket és egy minőségi score-t.
///
/// A domain framework-mentes (AGENTS.md §6): nincs Flutter / Riverpod /
/// storage import. A `createdAt` UTC ISO-8601 sztringként perzisztálódik,
/// dekódoláskor UTC-ként kapjuk vissza.
///
/// **Pixelkoordináta-tilalom:** a `zoom` normalizált `[0, 1]` (R7 §5.4) —
/// fizikai zoom-tartományra a kamera-rétegben fordulunk.
library;

import '../../../../core/camera/camera_coordinate_space.dart';
import '../vision_setup_profile.dart';

/// Immutable camera calibration profile.
final class CameraCalibrationProfile {
  const CameraCalibrationProfile({
    required this.camera,
    required this.orientation,
    required this.zoom,
    required this.setupProfile,
    required this.createdAt,
    required this.qualityScore,
  }) : assert(zoom >= 0 && zoom <= 1),
       assert(qualityScore >= 0 && qualityScore <= 1);

  /// Back vagy front — a meglévő `VisionCameraPreference` (R5 analóg).
  final VisionCameraPreference camera;

  /// A kamera fizikai tájolása (a `CameraRotation` típusnál van).
  final CameraRotation orientation;

  /// Normalizált zoom `[0, 1]` (a fizikai zoom-tartományra a kamera adapter
  /// képez le; ez a kalibráció a normalizált értéket hordozza).
  final double zoom;

  /// A meglévő, változatlan négyértékű setup enum (R5).
  final VisionSetupProfile setupProfile;

  /// A kalibráció készítésének UTC időbélyege.
  final DateTime createdAt;

  /// Normalizált minőségi pontszám `[0, 1]` (1.0 = teljesen megbízható).
  final double qualityScore;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraCalibrationProfile &&
          other.camera == camera &&
          other.orientation == orientation &&
          other.zoom == zoom &&
          other.setupProfile == setupProfile &&
          other.createdAt == createdAt &&
          other.qualityScore == qualityScore;

  @override
  int get hashCode => Object.hash(
    camera,
    orientation,
    zoom,
    setupProfile,
    createdAt,
    qualityScore,
  );
}