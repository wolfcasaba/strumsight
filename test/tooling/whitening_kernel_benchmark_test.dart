// MICROBENCHMARK: what the Hamming whitening kernel costs per frame.
//
//   flutter test test/tooling/whitening_kernel_benchmark_test.dart
//
// WHY this exists rather than a hand-wave. The flat box kernel is O(1) per bin
// (prefix sum); a weighted kernel has no prefix-sum shortcut, so the Hamming
// form is a direct convolution — at the shipped settings 19 taps × 147
// log-frequency bins, twice over on the mean-subtracting path. That is "almost
// certainly fine", and "almost certainly fine" is exactly the claim that belongs
// in a measurement and not in a code comment, because this is the LIVE on-device
// audio path: the chord framer hops `DspConfig.nnlsHop` samples, so one frame's
// entire budget is hop/sampleRate ≈ 92.9 ms at 44.1 kHz and whitening is one
// stage of several inside it.
//
// The numbers below are wall-clock on the host and are PRINTED, not asserted:
// a timing threshold in the dev-loop suite is a flake generator on a shared
// machine (a peer round runs tests concurrently on this box). The budget check
// that IS asserted is a generous order-of-magnitude one — a regression that
// turned whitening from microseconds into milliseconds would be a design
// change, and that is worth failing on.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/dsp/dsp_config.dart';
import 'package:strumsight/features/live/engine/dsp/nnls_chroma.dart';

/// A spectrum shaped like a real one: six plucked-string partial stacks over a
/// decaying noise floor, deterministic from a fixed seed so the two kernels are
/// timed on exactly the same input.
Float64List _spectrumLike(int bins) {
  final random = math.Random(20260911);
  final s = Float64List(bins);
  for (var j = 0; j < bins; j++) {
    s[j] = 0.02 * random.nextDouble() * math.exp(-j / (bins * 0.8));
  }
  // Note centres at 3 bins per semitone; an open E voicing's scale degrees.
  for (final semitone in const [0, 7, 12, 16, 19, 24]) {
    for (var harmonic = 1; harmonic <= 6; harmonic++) {
      final j = (semitone * 3 + 36 * (math.log(harmonic) / math.ln2)).round();
      if (j >= 0 && j < bins) s[j] += 1.0 / harmonic;
    }
  }
  return s;
}

({double micros, double checksum}) _time(
  NnlsChroma chroma,
  Float64List spectrum,
  int iterations,
) {
  // Warm up the JIT on the same code path before the measured loop, or the
  // first kernel timed pays for compiling both.
  var checksum = 0.0;
  for (var i = 0; i < iterations ~/ 4 + 1; i++) {
    final out = chroma.debugWhitenSpectrum(spectrum);
    checksum += out[spectrum.length ~/ 2];
  }
  final watch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    final out = chroma.debugWhitenSpectrum(spectrum);
    checksum += out[spectrum.length ~/ 2];
  }
  watch.stop();
  return (micros: watch.elapsedMicroseconds / iterations, checksum: checksum);
}

void main() {
  const iterations = 4000;

  test('BENCH: per-frame whitening cost, box vs Hamming, both paths', () {
    NnlsChroma build({required bool hamming, required double meanK}) =>
        NnlsChroma(
          sampleRate: DspConfig.defaultSampleRate,
          window: DspConfig.nnlsWindow,
          whiteningHammingKernel: hamming,
          whiteningMeanCoefficient: meanK,
        );

    final probe = build(hamming: false, meanK: 0);
    final spectrum = _spectrumLike(probe.debugBinCount);
    final frameBudgetMicros =
        DspConfig.nnlsHop / DspConfig.defaultSampleRate * 1e6;

    final cases = <String, NnlsChroma>{
      'divide-only   box    ': build(hamming: false, meanK: 0),
      'divide-only   hamming': build(hamming: true, meanK: 0),
      'mean-subtract box     (k=0.2)': build(hamming: false, meanK: 0.2),
      'mean-subtract hamming (k=0.2)': build(hamming: true, meanK: 0.2),
    };

    final lines = <String>[
      'bins=${probe.debugBinCount}  '
          'taps=${2 * probe.whiteningHalfWindow + 1}  '
          'frame budget=${frameBudgetMicros.toStringAsFixed(0)} us '
          '(hop ${DspConfig.nnlsHop} @ ${DspConfig.defaultSampleRate} Hz)  '
          'iterations=$iterations',
    ];
    final measured = <String, double>{};
    for (final entry in cases.entries) {
      final result = _time(entry.value, spectrum, iterations);
      measured[entry.key] = result.micros;
      lines.add(
        '  ${entry.key.padRight(30)} '
        '${result.micros.toStringAsFixed(2).padLeft(7)} us/frame   '
        '${(result.micros / frameBudgetMicros * 100).toStringAsFixed(3)}% '
        'of the frame budget',
      );
    }

    // ignore: avoid_print
    print('\nWHITENING KERNEL MICROBENCHMARK\n${lines.join("\n")}\n');

    // The asserted budget is deliberately loose: 5% of one frame's wall-clock
    // budget for a single DSP stage is still an order of magnitude above what
    // any of these measure, so this fails only on a design-level regression and
    // not on a busy machine.
    for (final entry in measured.entries) {
      expect(
        entry.value,
        lessThan(frameBudgetMicros * 0.05),
        reason:
            '${entry.key} whitening took ${entry.value} us of a '
            '$frameBudgetMicros us frame budget',
      );
    }
  });
}
