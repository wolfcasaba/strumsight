import '../model/live_frame.dart';

/// Source of live chord + strum-direction detection.
///
/// v1 ships [MockStrumEngine]. The real on-device C++ DSP core (aubio onset +
/// CQT chroma chord match + sub-band direction) will land behind this SAME
/// interface via Dart FFI, so the UI never changes when it is swapped in.
abstract class StrumEngine {
  /// A stream of frames produced while the engine is running.
  Stream<LiveFrame> get frames;

  /// Begin listening / producing frames.
  Future<void> start();

  /// Stop producing frames (the engine stays reusable — call [start] again).
  Future<void> stop();

  /// Release all resources.
  Future<void> dispose();
}
