import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/core/camera/camera_transform.dart';
import 'package:strumsight/core/camera/preview_fit.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final random = math.Random(seed);
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  test(
    'property: inverse compose apply round-trips within the pinned tolerance',
    () {
      for (var trial = 0; trial < 200; trial++) {
        final rotation =
            CameraRotation.values[random.nextInt(CameraRotation.values.length)];
        final sensorSize = SensorSize(
          width: 1 + random.nextDouble() * 4095,
          height: 1 + random.nextDouble() * 4095,
        );
        final viewport = PreviewRect(
          left: random.nextDouble() * 50,
          top: random.nextDouble() * 50,
          width: 1 + random.nextDouble() * 1000,
          height: 1 + random.nextDouble() * 1000,
        );
        final layout = PreviewFit(
          imageSize: sensorSize.rotated(rotation),
          viewport: viewport,
          mode: PreviewFitMode
              .values[random.nextInt(PreviewFitMode.values.length)],
        );
        final transform =
            CameraTransform.sensorToUpright(
                  sensorSize: sensorSize,
                  rotation: rotation,
                )
                .compose(
                  CameraTransform.uprightToNormalized(
                    uprightSize: sensorSize.rotated(rotation),
                  ),
                )
                .compose(layout.toPreview(mirrorPreview: random.nextBool()));
        final point = SensorPoint(
          random.nextDouble() * sensorSize.width,
          random.nextDouble() * sensorSize.height,
        );

        final roundTrip = transform.inverse().apply(transform.apply(point));
        expect(
          (roundTrip.x - point.x).abs() / sensorSize.width,
          lessThanOrEqualTo(cameraTransformRoundTripTolerance),
        );
        expect(
          (roundTrip.y - point.y).abs() / sensorSize.height,
          lessThanOrEqualTo(cameraTransformRoundTripTolerance),
        );
      }
    },
  );

  test('property: twice applying a preview mirror is the identity', () {
    for (var trial = 0; trial < 200; trial++) {
      final viewport = PreviewRect(
        left: random.nextDouble() * 50,
        top: random.nextDouble() * 50,
        width: 1 + random.nextDouble() * 1000,
        height: 1 + random.nextDouble() * 1000,
      );
      final mirror = CameraTransform.previewMirror(viewport);
      final point = PreviewPoint(
        viewport.left + random.nextDouble() * viewport.width,
        viewport.top + random.nextDouble() * viewport.height,
      );

      final result = mirror.apply(mirror.apply(point));
      expect(result.x, closeTo(point.x, cameraTransformRoundTripTolerance));
      expect(result.y, closeTo(point.y, cameraTransformRoundTripTolerance));
    }
  });

  test('property: four clockwise quarter rotations are the identity', () {
    for (var trial = 0; trial < 200; trial++) {
      final sensorSize = SensorSize(
        width: 1 + random.nextDouble() * 4095,
        height: 1 + random.nextDouble() * 4095,
      );
      final point = SensorPoint(
        random.nextDouble() * sensorSize.width,
        random.nextDouble() * sensorSize.height,
      );
      final fourTurns = CameraTransform.sensorQuarterTurn(sensorSize)
          .compose(
            CameraTransform.uprightQuarterTurn(
              sensorSize.rotated(CameraRotation.degrees90),
            ),
          )
          .compose(CameraTransform.sensorQuarterTurn(sensorSize))
          .compose(
            CameraTransform.uprightQuarterTurn(
              sensorSize.rotated(CameraRotation.degrees90),
            ),
          );

      final result = fourTurns.apply(point);
      expect(result.x, closeTo(point.x, cameraTransformRoundTripTolerance));
      expect(result.y, closeTo(point.y, cameraTransformRoundTripTolerance));
    }
  });

  test(
    'property: visible fit and fill preview points map to valid normalized points',
    () {
      for (var trial = 0; trial < 200; trial++) {
        final layout = PreviewFit(
          imageSize: UprightSize(
            width: 1 + random.nextDouble() * 4095,
            height: 1 + random.nextDouble() * 4095,
          ),
          viewport: PreviewRect(
            left: random.nextDouble() * 50,
            top: random.nextDouble() * 50,
            width: 1 + random.nextDouble() * 1000,
            height: 1 + random.nextDouble() * 1000,
          ),
          mode: PreviewFitMode
              .values[random.nextInt(PreviewFitMode.values.length)],
        );
        final visible = layout.visibleContentRect;
        final previewPoint = PreviewPoint(
          visible.left + random.nextDouble() * visible.width,
          visible.top + random.nextDouble() * visible.height,
        );

        final normalized = layout.toNormalized().apply(previewPoint);
        expect(normalized.x, inInclusiveRange(0, 1));
        expect(normalized.y, inInclusiveRange(0, 1));
      }
    },
  );
}
