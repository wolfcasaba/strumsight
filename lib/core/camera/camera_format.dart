/// Pixel layouts the platform-neutral camera contract can describe.
///
/// Platform adapters translate their own image types into one of these values;
/// no plugin-specific image type crosses the core boundary.
enum CameraPixelFormat { yuv420, nv21, bgra8888, rgba8888, jpeg }

/// Clockwise orientation of the captured image relative to portrait-up.
enum CameraOrientation {
  portraitUp,
  landscapeRight,
  portraitDown,
  landscapeLeft,
}
