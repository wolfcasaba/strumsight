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

  // NNLS chord path (chunk 011). A long window is needed so a semitone is
  // resolvable at low E (~4.8 Hz apart); chords are slow so the latency is ok.
  static const int nnlsWindow = 16384; // ~0.37 s @44.1 kHz
  static const int nnlsHop = 4096; // update ~every 93 ms

  // Fast pipeline — onset/direction (chunk 002).
  static const int onsetWindow = 1024;
  static const int onsetHop = 256;

  // Chromagram (chunk 003).
  static const double chromaMinHz = 60;
  static const double chromaMaxHz = 1600;
  static const double semitoneTolerance = 0.35;
  static const double chromaEmaAlpha = 0.25;

  // Chord matching (chunk 004) — legacy template matcher (still used by the
  // chroma_chord + property tests as a reference).
  static const int chordHysteresisFrames = 3;
  static const double chordInstantSwitchConfidence = 0.8;

  // Chord dictionary + Viterbi decoder (chunk 012) — the live chord path.
  // The self-transition bonus IS the switch threshold (replaces the three
  // hand-tuned hysteresis constants): a rival chord must beat the incumbent's
  // per-frame similarity by more than this and persist to take over. Bass vs
  // treble cosine weighting and the no-chord floor round out the model.
  static const double chordSelfTransitionBonus = 0.22;
  static const double chordBassWeight = 0.35;
  static const double chordTrebleWeight = 0.65;
  static const double chordNoChordScore = 0.55;

  /// Minimum chroma tonalness (chunk 003) for a frame to update the chord.
  /// Below this the frame is diffuse (speech/noise) and is treated as silence
  /// so it can't fake a chord. MEASURED (synth): a clean triad ≈ 0.99, white
  /// noise ≈ 0.55 — 0.7 separates them with margin. May need real-device tuning.
  static const double chordMinTonalness = 0.7;

  // Silence gate (chunk 010).
  static const double silenceRms = 0.008;
}
