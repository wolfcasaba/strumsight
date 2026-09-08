// E09-R28a: the padded-row regression. `plugin_camera_capture._copyPlanes`
// concatenates the platform planes verbatim, so the luminance plane arrives
// with whatever `bytesPerRow` the device used. Reading it as `y * width + x`
// shears the picture by `rowStride - width` pixels per row — and the shear is
// invisible, because the buffer is still long enough for every length check.
// 640x480 usually has no padding, which is exactly why this must be pinned.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/data/pipeline/yuv_luminance.dart';

/// A `width x height` ramp laid out with [rowStride] bytes per row.
///
/// Padding bytes are 0xFF so a de-pad failure shows up as a bright pixel
/// instead of a plausible one.
Uint8List _paddedPlane({
  required int width,
  required int height,
  required int rowStride,
  int trailingPad = 0,
}) {
  final bytes = Uint8List(rowStride * height + trailingPad)
    ..fillRange(0, rowStride * height + trailingPad, 0xFF);
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      bytes[y * rowStride + x] = y * width + x;
    }
  }
  return bytes;
}

void main() {
  group('packLuminancePlane', () {
    test('returns the plane unchanged when the rows are not padded', () {
      final bytes = _paddedPlane(width: 4, height: 3, rowStride: 4);

      final plane = packLuminancePlane(
        bytes: bytes,
        width: 4,
        height: 3,
        rowStride: 4,
      );

      expect(plane, isNotNull);
      expect(plane!.length, 12);
      expect(plane, List<int>.generate(12, (index) => index));
    });

    test('drops the padding when rowStride exceeds width', () {
      final bytes = _paddedPlane(width: 4, height: 3, rowStride: 7);

      final plane = packLuminancePlane(
        bytes: bytes,
        width: 4,
        height: 3,
        rowStride: 7,
      );

      expect(plane, isNotNull);
      expect(plane!.length, 12);
      // Every pixel must equal its own index: one leaked padding byte or one
      // wrong row offset breaks this immediately.
      expect(plane, List<int>.generate(12, (index) => index));
      expect(plane, isNot(contains(0xFF)));
    });

    test('reading a padded buffer as unpadded is what shears the image', () {
      final bytes = _paddedPlane(width: 4, height: 3, rowStride: 7);

      final sheared = packLuminancePlane(
        bytes: bytes,
        width: 4,
        height: 3,
        rowStride: 4,
      );

      // The buffer is long enough, so nothing fails — it just silently reads
      // padding as picture. That silence is the defect this round removes.
      expect(sheared, isNotNull);
      expect(sheared, isNot(List<int>.generate(12, (index) => index)));
      expect(sheared, contains(0xFF));
    });

    test('accepts a buffer whose last row stops at the final pixel', () {
      final bytes = Uint8List(2 * 5 + 3);
      for (var y = 0; y < 3; y += 1) {
        for (var x = 0; x < 3; x += 1) {
          bytes[y * 5 + x] = y * 3 + x;
        }
      }

      final plane = packLuminancePlane(
        bytes: bytes,
        width: 3,
        height: 3,
        rowStride: 5,
      );

      expect(plane, List<int>.generate(9, (index) => index));
    });

    test('refuses a buffer that cannot hold the described plane', () {
      expect(
        packLuminancePlane(
          bytes: Uint8List(11),
          width: 4,
          height: 3,
          rowStride: 4,
        ),
        isNull,
      );
    });

    test('refuses a stride narrower than the frame', () {
      expect(
        packLuminancePlane(
          bytes: Uint8List(64),
          width: 8,
          height: 4,
          rowStride: 4,
        ),
        isNull,
      );
    });

    test('refuses non-positive dimensions', () {
      expect(
        packLuminancePlane(
          bytes: Uint8List(16),
          width: 0,
          height: 4,
          rowStride: 4,
        ),
        isNull,
      );
      expect(
        packLuminancePlane(
          bytes: Uint8List(16),
          width: 4,
          height: 0,
          rowStride: 4,
        ),
        isNull,
      );
    });
  });
}
