/// Versioned, Live-specific thresholds for [LiveSignalQualityAnalyzer]
/// (ADR 0507 D3). The FORMULAS are reused from
/// `package:strumsight/features/audio_analysis/public.dart`'s
/// `SignalQualityMath`; these numbers only tune what the Live streaming
/// analyzer does with the results — they never replace or duplicate the math.
///
/// Every value here is sourced and justified in
/// `docs/rag/chunks/live-signal-quality.md`, calibrated against the real
/// `SignalQualityMath` primitives on synthetic fixtures (same commit, HORIZON
/// rule).
final class LiveQualityThresholds {
  const LiveQualityThresholds({
    required this.version,
    required this.frameSize,
    required this.frameHop,
    required this.historyBlocks,
    required this.enterFrames,
    required this.exitFrames,
    required this.statsStride,
    required this.tonalnessStride,
    required this.tonalnessWindowSamples,
    required this.quietRmsDbfs,
    required this.loudPeakDbfs,
    required this.clippedRatioThreshold,
    required this.unstableRmsStdDevDb,
    required this.noisyTonalnessMax,
    required this.speechTonalnessMax,
  });

  static const LiveQualityThresholds standard = LiveQualityThresholds(
    version: 'live-quality-v2',
    frameSize: 4096,
    frameHop: 4096,
    historyBlocks: 4,
    enterFrames: 5,
    exitFrames: 8,
    statsStride: 64,
    tonalnessStride: 4,
    tonalnessWindowSamples: 4096,
    quietRmsDbfs: -40.0,
    loudPeakDbfs: -2.0,
    clippedRatioThreshold: 0.001,
    unstableRmsStdDevDb: 15.0,
    noisyTonalnessMax: 0.25,
    speechTonalnessMax: 0.5,
  );

  final String version;

  /// Analysis block size in samples (non-overlapping: [frameHop] == [frameSize]).
  final int frameSize;
  final int frameHop;

  /// How many recent blocks feed the noise-floor / silence-ratio / stability
  /// statistics. The buffer must hold this many blocks before the analyzer
  /// leaves [SignalQualityState.unknown] (ADR 0507 D5).
  final int historyBlocks;

  /// Consecutive raw classifications required to confirm a transition INTO a
  /// non-good state (fast attack).
  final int enterFrames;

  /// Consecutive raw classifications required to confirm a transition INTO
  /// [SignalQualityState.good] (slow release) — this also gates the very
  /// first `unknown` → `good` confirmation (ADR 0507 D5).
  final int exitFrames;

  /// Recompute EVERY metric — the per-block level (`peakDbfs`, `rmsDbfs`,
  /// `clippedSampleRatio`) AND the rolling-window stats (`silentRatio`,
  /// `activeRegionRatio`, `noiseFloorDbfs`, the stability std-dev behind
  /// [SignalQualityState.unstable]) — only every Nth completed block, reusing
  /// the last value in between. Measured necessary against the CPU-cost
  /// acceptance cell (brief §6/6.1 row 6): even the "cheap" level primitives
  /// each do their own O(block) pass, and summed over a whole stream that
  /// exceeded the budget on its own. A live quality indicator does not need
  /// sub-block-period reaction time.
  final int statsStride;

  /// Run the `tonalness` FFT only every Nth completed block THAT [statsStride]
  /// already selected — ADR 0507 D9. Effective cadence is
  /// `lcm(statsStride, tonalnessStride)` blocks; with the standard values
  /// (64 and 4, where 4 divides 64) that is simply every `statsStride`
  /// blocks — `tonalness` piggybacks on the same recompute, it is never MORE
  /// frequent than the level/history stats. `tonalness` is the only
  /// primitive that runs an FFT, and by far the most expensive call here.
  final int tonalnessStride;

  /// How many of the MOST RECENT samples (tail of the rolling history, may
  /// span more than one block) feed each `tonalness` call. Smaller than the
  /// full [historyBlocks] window on purpose (every extra sample flattened in
  /// multiplies the FFT cost of this already-throttled call), but wide
  /// enough to span more than one internal 2048-sample analysis frame — a
  /// single-frame snapshot measured unreliable on envelope-modulated audio
  /// (an infrequent sample can land in a near-silent trough by chance).
  /// Measured against both the CPU-cost and classification-accuracy
  /// acceptance cells (brief §6/6.1 rows 1 and 6).
  final int tonalnessWindowSamples;

  /// Block RMS at/below this is [SignalQualityState.tooQuiet].
  final double quietRmsDbfs;

  /// Block peak at/above this (and not clipping) is [SignalQualityState.tooLoud].
  final double loudPeakDbfs;

  /// Block `clippedSampleRatio` at/above this is [SignalQualityState.clipping]
  /// (inclusive — matches `QualityThresholds.standard.clippedRatioWarning`).
  final double clippedRatioThreshold;

  /// Standard deviation, in dB, of block RMS across [historyBlocks] at/above
  /// this is [SignalQualityState.unstable].
  final double unstableRmsStdDevDb;

  /// Tonalness at/below this (once level/stability checks pass) is
  /// [SignalQualityState.tooNoisy].
  final double noisyTonalnessMax;

  /// Tonalness above [noisyTonalnessMax] and at/below this is
  /// [SignalQualityState.speechLike]; above this is [SignalQualityState.good].
  final double speechTonalnessMax;
}
