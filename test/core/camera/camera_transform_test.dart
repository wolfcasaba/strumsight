import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/core/camera/camera_transform.dart';
import 'package:strumsight/core/camera/preview_fit.dart';

const _sourceSize = SensorSize(width: 4, height: 3);
const _viewport = PreviewRect(left: 0, top: 0, width: 8, height: 8);
const _sourcePoints = <SensorPoint>[
  SensorPoint(0, 0),
  SensorPoint(2, 1.5),
  SensorPoint(1, 2.25),
];

void main() {
  test('the coordinate-space types cannot be used interchangeably', () {
    const normalized = NormalizedPoint(0.25, 0.75);
    const preview = PreviewPoint(2, 6);

    expect(normalized.space, CameraCoordinateSpace.normalized);
    expect(preview.space, CameraCoordinateSpace.preview);
  });

  test('the overlay uses the preview local coordinate system explicitly', () {
    final overlay = CameraTransform.previewToOverlay().apply(
      const PreviewPoint(2, 6),
    );

    expect(overlay, const OverlayPoint(2, 6));
    expect(overlay.space, CameraCoordinateSpace.overlay);
  });

  test('manual 16-cell rotation, mirror, and fit fixture matrix', () {
    // These expected values are independently calculated in the round brief
    // with the recorded python3 command, rather than via CameraTransform.
    final fixtures = <_Fixture>[
      _f(0, false, PreviewFitMode.fit, [0, 1, 4, 4, 2, 5.5]),
      _f(0, false, PreviewFitMode.fill, [-4 / 3, 0, 4, 4, 4 / 3, 6]),
      _f(0, true, PreviewFitMode.fit, [8, 1, 4, 4, 6, 5.5]),
      _f(0, true, PreviewFitMode.fill, [28 / 3, 0, 4, 4, 20 / 3, 6]),
      _f(90, false, PreviewFitMode.fit, [7, 0, 4, 4, 2.5, 2]),
      _f(90, false, PreviewFitMode.fill, [8, -4 / 3, 4, 4, 2, 4 / 3]),
      _f(90, true, PreviewFitMode.fit, [1, 0, 4, 4, 5.5, 2]),
      _f(90, true, PreviewFitMode.fill, [0, -4 / 3, 4, 4, 6, 4 / 3]),
      _f(180, false, PreviewFitMode.fit, [8, 7, 4, 4, 6, 2.5]),
      _f(180, false, PreviewFitMode.fill, [28 / 3, 8, 4, 4, 20 / 3, 2]),
      _f(180, true, PreviewFitMode.fit, [0, 7, 4, 4, 2, 2.5]),
      _f(180, true, PreviewFitMode.fill, [-4 / 3, 8, 4, 4, 4 / 3, 2]),
      _f(270, false, PreviewFitMode.fit, [1, 8, 4, 4, 5.5, 6]),
      _f(270, false, PreviewFitMode.fill, [0, 28 / 3, 4, 4, 6, 20 / 3]),
      _f(270, true, PreviewFitMode.fit, [7, 8, 4, 4, 2.5, 6]),
      _f(270, true, PreviewFitMode.fill, [8, 28 / 3, 4, 4, 2, 20 / 3]),
    ];

    for (final fixture in fixtures) {
      final rotation = CameraRotation.fromDegrees(fixture.rotationDegrees);
      final sensorToUpright = CameraTransform.sensorToUpright(
        sensorSize: _sourceSize,
        rotation: rotation,
      );
      final uprightToNormalized = CameraTransform.uprightToNormalized(
        uprightSize: _sourceSize.rotated(rotation),
      );
      final layout = PreviewFit(
        imageSize: _sourceSize.rotated(rotation),
        viewport: _viewport,
        mode: fixture.mode,
      );
      final transform = sensorToUpright
          .compose(uprightToNormalized)
          .compose(layout.toPreview(mirrorPreview: fixture.mirrored));

      for (var index = 0; index < _sourcePoints.length; index++) {
        final actual = transform.apply(_sourcePoints[index]);
        expect(actual.x, closeTo(fixture.expected[index * 2], 1e-9));
        expect(actual.y, closeTo(fixture.expected[index * 2 + 1], 1e-9));
      }
    }
  });

  test('round-trip tolerance accepts below and at the inclusive boundary', () {
    final below = _nextDown(cameraTransformRoundTripTolerance);

    expect(CameraTransform.isRoundTripErrorWithinTolerance(below), isTrue);
    expect(
      CameraTransform.isRoundTripErrorWithinTolerance(
        cameraTransformRoundTripTolerance,
      ),
      isTrue,
    );
  });

  test('round-trip tolerance rejects one ULP above its boundary', () {
    final above = _nextUp(cameraTransformRoundTripTolerance);

    expect(CameraTransform.isRoundTripErrorWithinTolerance(above), isFalse);
  });
}

_Fixture _f(
  int rotationDegrees,
  bool mirrored,
  PreviewFitMode mode,
  List<double> expected,
) => _Fixture(rotationDegrees, mirrored, mode, expected);

final class _Fixture {
  const _Fixture(this.rotationDegrees, this.mirrored, this.mode, this.expected);

  final int rotationDegrees;
  final bool mirrored;
  final PreviewFitMode mode;
  final List<double> expected;
}

double _nextUp(double value) {
  final bytes = ByteData(8)..setFloat64(0, value);
  bytes.setUint64(0, bytes.getUint64(0) + 1);
  return bytes.getFloat64(0);
}

double _nextDown(double value) {
  final bytes = ByteData(8)..setFloat64(0, value);
  bytes.setUint64(0, bytes.getUint64(0) - 1);
  return bytes.getFloat64(0);
}
