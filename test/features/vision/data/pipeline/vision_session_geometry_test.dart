// E09-R28a: the session finally reads the manual calibration R10/R11
// persists. Before this round `VisionSessionController.beginCalibration()`
// only flipped a status enum and `start()` never loaded the bundle, so the
// session reported `tracking` whether or not a calibration existed.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/features/vision/application/calibration_loss_machine.dart';
import 'package:strumsight/features/vision/data/persistence/vision_calibration_repository.dart';
import 'package:strumsight/features/vision/data/pipeline/vision_session_geometry.dart';
import 'package:strumsight/features/vision/domain/calibration/calibration_validity.dart';
import 'package:strumsight/features/vision/domain/calibration/camera_calibration_profile.dart';
import 'package:strumsight/features/vision/domain/calibration/guitar_calibration.dart';
import 'package:strumsight/features/vision/domain/evidence/evidence_provenance.dart';
import 'package:strumsight/features/vision/domain/vision_setup_profile.dart';

final DateTime _savedAt = DateTime.utc(2026, 9, 1, 10);

CameraCalibrationProfile _profile({
  VisionCameraPreference camera = VisionCameraPreference.back,
  CameraRotation orientation = CameraRotation.degrees0,
  double zoom = 0.5,
  DateTime? createdAt,
}) => CameraCalibrationProfile(
  camera: camera,
  orientation: orientation,
  zoom: zoom,
  setupProfile: VisionSetupProfile.leftHandFocus,
  createdAt: createdAt ?? _savedAt,
  qualityScore: 0.9,
);

GuitarCalibration _guitar() => GuitarCalibration(
  nutAnchor: const NormalizedPoint(0.2, 0.4),
  bridgeAnchor: const NormalizedPoint(0.8, 0.5),
  neckPolygon: const <NormalizedPoint>[
    NormalizedPoint(0.2, 0.35),
    NormalizedPoint(0.8, 0.45),
    NormalizedPoint(0.8, 0.55),
    NormalizedPoint(0.2, 0.45),
  ],
  createdAt: _savedAt,
);

VisionCalibrationRecord _record({CameraCalibrationProfile? profile}) =>
    (profile: profile ?? _profile(), guitar: _guitar());

VisionGeometryContext _context({
  VisionCameraPreference camera = VisionCameraPreference.back,
  CameraRotation orientation = CameraRotation.degrees0,
  double zoom = 0.5,
  DateTime? now,
}) => VisionGeometryContext(
  camera: camera,
  orientation: orientation,
  zoom: zoom,
  now: now ?? DateTime.utc(2026, 9, 2, 10),
);

void main() {
  group('VisionSessionGeometry.resolve', () {
    test('no persisted bundle is lost, with no region of interest', () {
      final geometry = VisionSessionGeometry.resolve(
        record: null,
        context: _context(),
      );

      expect(geometry.state, CalibrationLossState.lost);
      expect(geometry.roi, isNull);
      expect(geometry.isCalibrated, isFalse);
      expect(geometry.invalidationReason, isNull);
    });

    test('a valid bundle tracks from the manual anchors', () {
      final geometry = VisionSessionGeometry.resolve(
        record: _record(),
        context: _context(),
      );

      expect(geometry.state, CalibrationLossState.tracking);
      expect(geometry.source, GeometrySource.manual);
      expect(geometry.invalidationReason, isNull);
      expect(geometry.roi, isNotNull);
    });

    test('the region of interest is the dilated neck bounding box', () {
      final geometry = VisionSessionGeometry.resolve(
        record: _record(),
        context: _context(),
        dilation: 2,
      );

      // Raw box: x in [0.2, 0.8], y in [0.35, 0.55]. Doubling about the
      // centre gives x in [-0.1, 1.1] -> clamped to [0, 1], y in [0.25, 0.65].
      final roi = geometry.roi!;
      expect(roi.left, 0);
      expect(roi.right, 1);
      expect(roi.top, closeTo(0.25, 1e-9));
      expect(roi.bottom, closeTo(0.65, 1e-9));
    });

    test('an undilated region is exactly the anchors bounding box', () {
      final geometry = VisionSessionGeometry.resolve(
        record: _record(),
        context: _context(),
        dilation: 1,
      );

      final roi = geometry.roi!;
      expect(roi.left, closeTo(0.2, 1e-9));
      expect(roi.right, closeTo(0.8, 1e-9));
      expect(roi.top, closeTo(0.35, 1e-9));
      expect(roi.bottom, closeTo(0.55, 1e-9));
    });

    test('the default dilation grows the box without leaving the frame', () {
      final geometry = VisionSessionGeometry.resolve(
        record: _record(),
        context: _context(),
      );

      final roi = geometry.roi!;
      expect(roi.left, lessThan(0.2));
      expect(roi.right, greaterThan(0.8));
      expect(roi.left, greaterThanOrEqualTo(0));
      expect(roi.right, lessThanOrEqualTo(1));
      expect(roi.top, greaterThanOrEqualTo(0));
      expect(roi.bottom, lessThanOrEqualTo(1));
    });

    test('a stale bundle is lost and names why', () {
      final geometry = VisionSessionGeometry.resolve(
        record: _record(),
        context: _context(now: _savedAt.add(const Duration(days: 31))),
      );

      expect(geometry.state, CalibrationLossState.lost);
      expect(geometry.roi, isNull);
      expect(
        geometry.invalidationReason,
        CalibrationInvalidationReason.timestampExpired,
      );
    });

    test('a bundle saved on the other lens is lost', () {
      final profile = _profile(camera: VisionCameraPreference.front);
      final geometry = VisionSessionGeometry.resolve(
        record: _record(profile: profile),
        context: _context(),
      );

      expect(geometry.state, CalibrationLossState.lost);
      expect(
        geometry.invalidationReason,
        CalibrationInvalidationReason.cameraDeviceChanged,
      );
    });

    test('the uncalibrated constant matches a missing bundle', () {
      const geometry = VisionSessionGeometry.uncalibrated();

      expect(geometry.state, CalibrationLossState.lost);
      expect(geometry.source, GeometrySource.manual);
      expect(geometry.roi, isNull);
    });
  });
}
