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

  /// Hint the currently EXPECTED chord (lesson/song target) to the detector,
  /// or clear it with null. The chord path biases ambiguous evidence toward
  /// the target (chunk 016 expected-target prior, round 137); a genuinely
  /// different played chord still wins. Default: no-op (mock/test engines).
  void setExpectedChord(String? label) {}

  /// Lab mode diagnostics (r199): turn a rolling mic-PCM capture on/off. When
  /// ON, the engine retains roughly the last 30 s of microphone audio so the
  /// Live Lab panel can re-run the full ML+DSP analysis on external guitar
  /// audio. When OFF the engine does ZERO extra work — no buffer, no append —
  /// so the default Live experience is untouched. Default: no-op.
  void setDiagnosticsCapture(bool on) {}

  /// The most recently captured PCM (a COPY) and its actual sample rate, for a
  /// Lab-mode capture-and-analyze. Empty (`(<double>[], 0)`) when capture is
  /// off or nothing has been buffered. Default: empty (mock/test engines).
  (List<double>, int) recentPcm() => (const <double>[], 0);

  /// Release all resources.
  Future<void> dispose();
}
