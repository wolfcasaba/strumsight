/// Stride-correct luminance extraction (E09-R28a).
///
/// This is the single place the Vision pipeline turns a borrowed camera
/// buffer into a tightly packed `width * height` luminance image. Keeping it
/// pure and alone is deliberate: the shear it prevents is invisible.
library;

import 'dart:typed_data';

/// Copies the luminance plane out of a camera buffer, honouring [rowStride].
///
/// Android's Y plane may be padded, so `rowStride` (the plugin's
/// `Plane.bytesPerRow`) can exceed [width] and the flat buffer a capture
/// adapter delivers is then NOT a `width x height` image. Indexing it as one
/// shifts every row by `rowStride - width` pixels and shears the picture —
/// silently, because `GrayscaleFrame.isWellFormed` only checks that the total
/// length is large enough, which a padded buffer always is.
///
/// Returns `null` when the buffer cannot hold the described plane. Callers
/// must treat that as "not observable", never as a black frame: a fabricated
/// image would become fabricated quality evidence.
Uint8List? packLuminancePlane({
  required Uint8List bytes,
  required int width,
  required int height,
  required int rowStride,
}) {
  if (width <= 0 || height <= 0 || rowStride < width) return null;
  // The last row only has to be `width` long: some devices report a buffer
  // that stops at the final pixel instead of padding past it.
  if (bytes.length < (height - 1) * rowStride + width) return null;
  if (rowStride == width) {
    return Uint8List.sublistView(bytes, 0, width * height);
  }
  final plane = Uint8List(width * height);
  for (var row = 0; row < height; row += 1) {
    final target = row * width;
    plane.setRange(target, target + width, bytes, row * rowStride);
  }
  return plane;
}
