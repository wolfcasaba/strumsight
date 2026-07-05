/// Shared DSP constants. Single source of truth: docs/rag/chunks — when a
/// value is tuned on real audio, update the chunk AND this file together.
class DspConfig {
  DspConfig._();

  /// Requested capture rate; the REAL engine must use the device's actual
  /// rate (chunk 001) — these constants are sample-count based so they hold.
  static const int defaultSampleRate = 44100;

  // Slow pipeline — chroma/chord (chunk 002).
  static const int chromaWindow = 4096;
  static const int chromaHop = 1024;

  // Fast pipeline — onset/direction (chunk 002).
  static const int onsetWindow = 1024;
  static const int onsetHop = 256;

  // Chromagram (chunk 003).
  static const double chromaMinHz = 60;
  static const double chromaMaxHz = 1600;
  static const double semitoneTolerance = 0.35;
  static const double chromaEmaAlpha = 0.25;

  // Chord matching (chunk 004).
  static const int chordHysteresisFrames = 3;
  static const double chordInstantSwitchConfidence = 0.8;

  // Silence gate (chunk 010).
  static const double silenceRms = 0.008;
}
