// AOT benchmark for the whitening kernels — the cost the app actually pays.
//
//   dart run tool/bench/whitening_bench.dart            # JIT
//   dart compile exe tool/bench/whitening_bench.dart -o <out> && <out>   # AOT
//
// WHY this exists. E18-R12 shipped the Hamming kernel with its per-frame cost
// measured only under the test runner's JIT, and said so. JIT numbers are the
// wrong ones: the app ships AOT-compiled, and tight numeric loops are exactly
// where the two diverge most. This closes that half of the gap. What it still
// cannot say is the ARM figure — this compiles for the host — so the remaining
// unknown is one architecture hop rather than a whole compilation mode.
//
// It measures `NnlsChroma.process` — the real public entry point, a whole
// analysis frame — rather than reaching into the whitening through a test-only
// seam. That is deliberate: a benchmark is not a test, and the analyzer is right
// to object when `tool/` code touches `@visibleForTesting` members. It also
// measures something more useful, the per-frame cost the app actually pays. The
// kernel's own share is still isolated, because box and Hamming runs differ in
// nothing else.
//
// The budget it is measured against is a real constant, not a guess: one
// `nnlsHop` of audio at 44.1 kHz is how long the engine has to produce a frame.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:strumsight/features/live/engine/dsp/dsp_config.dart';
import 'package:strumsight/features/live/engine/dsp/nnls_chroma.dart';

const int _sampleRate = 44100;

double _run({
  required bool hamming,
  required double meanCoefficient,
  required Float64List frame,
  required int iterations,
}) {
  final chroma = NnlsChroma(
    sampleRate: _sampleRate,
    whiteningHammingKernel: hamming,
    whiteningMeanCoefficient: meanCoefficient,
  );
  // Warm up, so the measurement is of steady-state work rather than of the FFT
  // plan, the harmonic dictionary and the first allocations.
  for (var i = 0; i < 20; i++) {
    chroma.process(frame);
  }
  final watch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    chroma.process(frame);
  }
  watch.stop();
  return watch.elapsedMicroseconds / iterations;
}

/// One analysis frame of chord-shaped audio: six partial-rich tones, so the
/// spectrum the whitener sees has the peaks and skirts it copes with in practice.
Float64List _frame() {
  const freqs = [82.41, 123.47, 164.81, 207.65, 246.94, 329.63];
  final out = Float64List(DspConfig.nnlsWindow);
  for (var n = 0; n < out.length; n++) {
    final t = n / _sampleRate;
    var sample = 0.0;
    for (final f in freqs) {
      for (var h = 1; h <= 6; h++) {
        sample += math.sin(2 * math.pi * f * h * t) / (h * h);
      }
    }
    out[n] = sample * 0.05;
  }
  return out;
}

void main() {
  final frame = _frame();
  const iterations = 3000;
  final budgetUs = DspConfig.nnlsHop / _sampleRate * 1e6;

  // ignore: avoid_print
  print('frame budget: ${budgetUs.toStringAsFixed(0)} us (one nnlsHop)');
  for (final (label, hamming, k) in <(String, bool, double)>[
    ('box     divide-only', false, 0.0),
    ('hamming divide-only', true, 0.0),
    ('box     k=0.20', false, 0.20),
    ('hamming k=0.20  (SHIPPED)', true, 0.20),
  ]) {
    final us = _run(
      hamming: hamming,
      meanCoefficient: k,
      frame: frame,
      iterations: iterations,
    );
    // ignore: avoid_print
    print(
      '${label.padRight(26)} ${us.toStringAsFixed(2).padLeft(7)} us'
      '  ${(us / budgetUs * 100).toStringAsFixed(4)}% of budget',
    );
  }
}
