import 'dart:math' as math;

/// Per-frame facts used by [SignalQualityMath.frameMetrics] callers to build
/// noise-floor, silence and tonalness readings without re-walking the PCM.
final class FrameMetrics {
  const FrameMetrics({
    required this.rmsDbfs,
    required this.linearRms,
    required this.spectralFlatness,
  });

  final double rmsDbfs;
  final double linearRms;

  /// `geometric_mean(magnitude) / arithmetic_mean(magnitude)` of the frame's
  /// windowed spectrum, in `(0, 1]`. Near 0 = tonal, near 1 = noise-like.
  final double spectralFlatness;
}

/// Pure, deterministic signal-quality formulas — no stage/state. Every
/// formula, window and threshold used here is documented in
/// `docs/rag/chunks/019-signal-quality-metrics.md`.
abstract final class SignalQualityMath {
  /// `20 * log10(amplitude)`, clamped to `[floorDbfs, ceilingDbfs]`. Silence
  /// (`amplitude <= 0`) maps to `floorDbfs`, never `-Infinity` or `NaN`.
  static double linearToDbfs(
    double amplitude, {
    required double floorDbfs,
    required double ceilingDbfs,
  }) {
    if (amplitude <= 0 || !amplitude.isFinite) return floorDbfs;
    final db = 20.0 * (math.log(amplitude) / math.ln10);
    if (db.isNaN) return floorDbfs;
    if (db < floorDbfs) return floorDbfs;
    if (db > ceilingDbfs) return ceilingDbfs;
    return db;
  }

  static double peakDbfs(
    List<double> samples, {
    required double floorDbfs,
    required double ceilingDbfs,
  }) {
    var peak = 0.0;
    for (final sample in samples) {
      final abs = sample.abs();
      if (abs.isFinite && abs > peak) peak = abs;
    }
    return linearToDbfs(peak, floorDbfs: floorDbfs, ceilingDbfs: ceilingDbfs);
  }

  static double rmsOf(List<double> samples) {
    if (samples.isEmpty) return 0.0;
    var sumSquares = 0.0;
    for (final sample in samples) {
      sumSquares += sample * sample;
    }
    return math.sqrt(sumSquares / samples.length);
  }

  static double rmsDbfs(
    List<double> samples, {
    required double floorDbfs,
    required double ceilingDbfs,
  }) => linearToDbfs(
    rmsOf(samples),
    floorDbfs: floorDbfs,
    ceilingDbfs: ceilingDbfs,
  );

  /// Fraction of samples whose absolute value is `>= threshold` (inclusive).
  static double clippedSampleRatio(
    List<double> samples, {
    required double threshold,
  }) {
    if (samples.isEmpty) return 0.0;
    var clipped = 0;
    for (final sample in samples) {
      if (sample.abs() >= threshold) clipped++;
    }
    return clipped / samples.length;
  }

  /// One [FrameMetrics] per frame of [frameSize] samples, hopping by
  /// [hopSize] (the last, possibly shorter, frame is still measured over its
  /// own length — no zero padding for the RMS/flatness reduction itself).
  static List<FrameMetrics> frameMetrics(
    List<double> samples, {
    required int frameSize,
    required int hopSize,
    required double floorDbfs,
    required double ceilingDbfs,
  }) {
    if (samples.isEmpty) return const <FrameMetrics>[];
    final frames = <FrameMetrics>[];
    for (var start = 0; start < samples.length; start += hopSize) {
      final end = math.min(start + frameSize, samples.length);
      final frame = samples.sublist(start, end);
      final linearRms = rmsOf(frame);
      frames.add(
        FrameMetrics(
          rmsDbfs: linearToDbfs(
            linearRms,
            floorDbfs: floorDbfs,
            ceilingDbfs: ceilingDbfs,
          ),
          linearRms: linearRms,
          spectralFlatness: _spectralFlatness(frame, frameSize),
        ),
      );
      if (end == samples.length) break;
    }
    return frames;
  }

  /// Linear-interpolated percentile ("R-7"), `p` in `[0, 1]`. Deterministic
  /// and independent of any threshold — see the noise-floor rationale in
  /// chunk 019 (percentile, not mean).
  static double percentile(List<double> values, double p) {
    if (values.isEmpty) {
      throw ArgumentError.value(values, 'values', 'must not be empty');
    }
    final sorted = List<double>.of(values)..sort();
    if (sorted.length == 1) return sorted.first;
    final rank = p * (sorted.length - 1);
    final lowerIndex = rank.floor();
    final upperIndex = rank.ceil();
    if (lowerIndex == upperIndex) return sorted[lowerIndex];
    final weight = rank - lowerIndex;
    return sorted[lowerIndex] * (1 - weight) + sorted[upperIndex] * weight;
  }

  /// Fraction of frames whose RMS dBFS is `<= silentThresholdDbfs` (inclusive).
  static double silentFrameRatio(
    List<double> frameRmsDbfsValues, {
    required double silentThresholdDbfs,
  }) {
    if (frameRmsDbfsValues.isEmpty) return 0.0;
    var silent = 0;
    for (final value in frameRmsDbfsValues) {
      if (value <= silentThresholdDbfs) silent++;
    }
    return silent / frameRmsDbfsValues.length;
  }

  /// Energy-weighted `1 - flatness` across frames (weight = linear frame
  /// RMS), so digitally-silent frames — whose flatness is ~1 only because of
  /// the epsilon floor, not measured noise — do not dominate the result.
  /// Returns `0.0` when every frame has zero weight (pure silence).
  static double weightedTonalness(
    List<double> flatnessPerFrame,
    List<double> weightPerFrame,
  ) {
    if (flatnessPerFrame.length != weightPerFrame.length) {
      throw ArgumentError('flatness and weight arrays must be the same length');
    }
    if (flatnessPerFrame.isEmpty) return 0.0;
    var weightedSum = 0.0;
    var totalWeight = 0.0;
    for (var i = 0; i < flatnessPerFrame.length; i++) {
      weightedSum += (1.0 - flatnessPerFrame[i]) * weightPerFrame[i];
      totalWeight += weightPerFrame[i];
    }
    if (totalWeight <= 0) return 0.0;
    final result = weightedSum / totalWeight;
    return result.clamp(0.0, 1.0);
  }

  static const double _flatnessMagnitudeFloor = 1e-9;

  /// `geometric_mean(magnitude) / arithmetic_mean(magnitude)` of a
  /// Hann-windowed, zero-padded-to-[frameSize] FFT magnitude spectrum, over
  /// bins `1..frameSize/2` (DC excluded). `frameSize` must be a power of two.
  static double _spectralFlatness(List<double> frame, int frameSize) {
    final windowed = List<double>.filled(frameSize, 0.0);
    final denominator = frame.length > 1 ? frame.length - 1 : 1;
    for (var i = 0; i < frame.length; i++) {
      final w = 0.5 - 0.5 * math.cos(2 * math.pi * i / denominator);
      windowed[i] = frame[i] * w;
    }
    final re = List<double>.of(windowed);
    final im = List<double>.filled(frameSize, 0.0);
    _fft(re, im);

    final bins = frameSize ~/ 2;
    if (bins <= 1) return 1.0;
    var sumLogMagnitude = 0.0;
    var sumMagnitude = 0.0;
    for (var bin = 1; bin <= bins; bin++) {
      final magnitude = math.sqrt(re[bin] * re[bin] + im[bin] * im[bin]);
      final floored = magnitude < _flatnessMagnitudeFloor
          ? _flatnessMagnitudeFloor
          : magnitude;
      sumLogMagnitude += math.log(floored);
      sumMagnitude += floored;
    }
    final count = bins;
    final geometricMean = math.exp(sumLogMagnitude / count);
    final arithmeticMean = sumMagnitude / count;
    if (arithmeticMean <= 0) return 1.0;
    final flatness = geometricMean / arithmeticMean;
    return flatness.clamp(0.0, 1.0);
  }

  /// In-place iterative radix-2 Cooley-Tukey FFT. `re.length` must be a
  /// power of two; `im` starts as all zeros for a real-valued input.
  static void _fft(List<double> re, List<double> im) {
    final n = re.length;
    var j = 0;
    for (var i = 1; i < n; i++) {
      var bit = n >> 1;
      while (j & bit != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;
      if (i < j) {
        final tempRe = re[i];
        re[i] = re[j];
        re[j] = tempRe;
        final tempIm = im[i];
        im[i] = im[j];
        im[j] = tempIm;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final half = len ~/ 2;
      final angle = -2 * math.pi / len;
      final wRe = math.cos(angle);
      final wIm = math.sin(angle);
      for (var start = 0; start < n; start += len) {
        var curWRe = 1.0;
        var curWIm = 0.0;
        for (var k = 0; k < half; k++) {
          final aIndex = start + k;
          final bIndex = aIndex + half;
          final vRe = re[bIndex] * curWRe - im[bIndex] * curWIm;
          final vIm = re[bIndex] * curWIm + im[bIndex] * curWRe;
          final uRe = re[aIndex];
          final uIm = im[aIndex];
          re[aIndex] = uRe + vRe;
          im[aIndex] = uIm + vIm;
          re[bIndex] = uRe - vRe;
          im[bIndex] = uIm - vIm;
          final nextWRe = curWRe * wRe - curWIm * wIm;
          final nextWIm = curWRe * wIm + curWIm * wRe;
          curWRe = nextWRe;
          curWIm = nextWIm;
        }
      }
    }
  }
}
