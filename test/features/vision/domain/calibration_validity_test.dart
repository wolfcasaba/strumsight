/// E05-R10 §6 — Validity-mátrix: öt cella, mind külön tesztelt.
///
/// A `CalibrationValidity.evaluate` a tárolt `CameraCalibrationProfile` és
/// `GuitarCalibration` felett dönti el, hogy az érvőles a jelenlegi
/// runtime-kontextusra (currentCamera / currentOrientation / currentZoom / now).
/// Minden cella ELTÉRŐ invalidation reason-t ad vissza — a tesztek egyenként
/// rögzítik, hogy a hibaüzenet kiolvasható legyen, és ne legyen átfedés.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/features/vision/domain/calibration/calibration_validity.dart';
import 'package:strumsight/features/vision/domain/calibration/camera_calibration_profile.dart';
import 'package:strumsight/features/vision/domain/calibration/guitar_calibration.dart';
import 'package:strumsight/features/vision/domain/vision_setup_profile.dart';

void main() {
  final referenceCreatedAt = DateTime.utc(2026, 8, 7, 12);

  CameraCalibrationProfile profile({
    VisionCameraPreference camera = VisionCameraPreference.back,
    CameraRotation orientation = CameraRotation.degrees0,
    double zoom = 0.5,
    DateTime? createdAt,
    double qualityScore = 0.9,
  }) => CameraCalibrationProfile(
    camera: camera,
    orientation: orientation,
    zoom: zoom,
    setupProfile: VisionSetupProfile.practiceBalanced,
    createdAt: createdAt ?? referenceCreatedAt,
    qualityScore: qualityScore,
  );

  GuitarCalibration geometry({
    double nutX = 0.20,
    double nutY = 0.50,
    double bridgeX = 0.80,
    double bridgeY = 0.50,
  }) => GuitarCalibration(
    nutAnchor: NormalizedPoint(nutX, nutY),
    bridgeAnchor: NormalizedPoint(bridgeX, bridgeY),
    neckPolygon: const [
      NormalizedPoint(0.15, 0.35),
      NormalizedPoint(0.85, 0.35),
      NormalizedPoint(0.85, 0.65),
      NormalizedPoint(0.15, 0.65),
    ],
    createdAt: referenceCreatedAt,
  );

  group('CalibrationValidity — happy path', () {
    test('returns null when stored and runtime match (valid calibration)', () {
      final stored = profile();
      final reason = CalibrationValidity.evaluate(
        profile: stored,
        guitar: geometry(),
        currentCamera: stored.camera,
        currentOrientation: stored.orientation,
        currentZoom: stored.zoom,
        now: stored.createdAt.add(const Duration(days: 1)),
      );
      expect(reason, isNull);
    });
  });

  group('Validity-mátrix — öt cella, mind külön', () {
    test('cell 1 — camera device changed → cameraDeviceChanged', () {
      final stored = profile(camera: VisionCameraPreference.back);
      final reason = CalibrationValidity.evaluate(
        profile: stored,
        guitar: geometry(),
        currentCamera: VisionCameraPreference.front,
        currentOrientation: stored.orientation,
        currentZoom: stored.zoom,
        now: stored.createdAt.add(const Duration(days: 1)),
      );
      expect(reason, CalibrationInvalidationReason.cameraDeviceChanged);
    });

    test('cell 2 — orientation changed → orientationChanged', () {
      final stored = profile(orientation: CameraRotation.degrees0);
      final reason = CalibrationValidity.evaluate(
        profile: stored,
        guitar: geometry(),
        currentCamera: stored.camera,
        currentOrientation: CameraRotation.degrees90,
        currentZoom: stored.zoom,
        now: stored.createdAt.add(const Duration(days: 1)),
      );
      expect(reason, CalibrationInvalidationReason.orientationChanged);
    });

    test(
      'cell 3 — zoom changed beyond tolerance → zoomChangedBeyondTolerance',
      () {
        final stored = profile(zoom: 0.5);
        final reason = CalibrationValidity.evaluate(
          profile: stored,
          guitar: geometry(),
          currentCamera: stored.camera,
          currentOrientation: stored.orientation,
          // 0.5 + 0.5 = 1.0; tolerance 0.1, így az eltérés 0.5 > 0.1.
          currentZoom: 1.0,
          now: stored.createdAt.add(const Duration(days: 1)),
        );
        expect(
          reason,
          CalibrationInvalidationReason.zoomChangedBeyondTolerance,
        );
      },
    );

    test('cell 4 — timestamp expired → timestampExpired', () {
      final stored = profile(createdAt: DateTime.utc(2026, 1, 1));
      // 250 nap = maxAge (30 nap) fölött.
      final now = DateTime.utc(2026, 1, 1).add(const Duration(days: 250));
      final reason = CalibrationValidity.evaluate(
        profile: stored,
        guitar: geometry(),
        currentCamera: stored.camera,
        currentOrientation: stored.orientation,
        currentZoom: stored.zoom,
        now: now,
      );
      expect(reason, CalibrationInvalidationReason.timestampExpired);
    });

    test('cell 5 — degenerate geometry → degenerateGeometry', () {
      // Nut és bridge túl közel: < minAnchorSeparation (0.05) — ez a
      // degenerált geometria egyik konkrét esete.
      final stored = profile();
      final reason = CalibrationValidity.evaluate(
        profile: stored,
        guitar: geometry(nutX: 0.50, nutY: 0.50, bridgeX: 0.51, bridgeY: 0.50),
        currentCamera: stored.camera,
        currentOrientation: stored.orientation,
        currentZoom: stored.zoom,
        now: stored.createdAt.add(const Duration(days: 1)),
      );
      expect(reason, CalibrationInvalidationReason.degenerateGeometry);
    });

    test('a zoom change WITHIN tolerance is still valid', () {
      final stored = profile(zoom: 0.5);
      final reason = CalibrationValidity.evaluate(
        profile: stored,
        guitar: geometry(),
        currentCamera: stored.camera,
        currentOrientation: stored.orientation,
        // 0.55 − 0.5 = 0.05 ≤ 0.1 tolerancia.
        currentZoom: 0.55,
        now: stored.createdAt.add(const Duration(days: 1)),
      );
      expect(reason, isNull);
    });

    test('priority order: camera device beats every later trigger', () {
      // Mind az öt trigger egyszerre aktív — a kamera-váltás a legerősebb,
      // mert a kalibráció a másik lencsére semmiképp nem érvényes.
      final stored = profile(camera: VisionCameraPreference.back);
      final reason = CalibrationValidity.evaluate(
        profile: stored,
        guitar: geometry(nutX: 0.50, bridgeX: 0.51),
        currentCamera: VisionCameraPreference.front,
        currentOrientation: CameraRotation.degrees180,
        currentZoom: 1.0,
        now: stored.createdAt.add(const Duration(days: 365)),
      );
      expect(reason, CalibrationInvalidationReason.cameraDeviceChanged);
    });
  });

  group('CalibrationInvalidationReason enum', () {
    test('a dokumentált öt érték mind jelen van, és nem lett bővítve', () {
      // Az R5/R6 megerősítés: a Validity-mátrix PONTOSAN öt cella, az SDD
      // §13.4 másik két triggere (tracking confidence / instrument change)
      // scope-on kívüli. Ha valaki véletlenül hozzáad egy hatodikat, ez a
      // teszt pirosra vált.
      expect(
        CalibrationInvalidationReason.values,
        unorderedEquals(<CalibrationInvalidationReason>[
          CalibrationInvalidationReason.cameraDeviceChanged,
          CalibrationInvalidationReason.orientationChanged,
          CalibrationInvalidationReason.zoomChangedBeyondTolerance,
          CalibrationInvalidationReason.timestampExpired,
          CalibrationInvalidationReason.degenerateGeometry,
        ]),
      );
    });
  });
}
