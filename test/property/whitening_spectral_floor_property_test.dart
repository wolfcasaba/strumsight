// Randomized property gate for the whitening spectral floor (E18-R11).
//
// The deterministic guards live in
// `test/features/live/dsp/whitening_spectral_floor_test.dart`; this re-checks the
// same invariants on RANDOM voicings, random levels, random noise and random
// beta, so the rectifier cannot be (even accidentally) correct only on the one
// open-E fixture the round was measured with.
//
// Seed: PROPERTY_SEED env var — CI passes the run id; locally absent → 42.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/dsp/dsp_config.dart';
import 'package:strumsight/features/live/engine/dsp/nnls_chroma.dart';

import '../support/synth.dart';

const _sampleRate = 44100;

double _midiToFreq(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

/// A random 3–6 voice chord-like signal with random per-voice levels, plus a
/// little broadband noise — the shape of input the whitener actually meets.
Float64List _randomVoicing(math.Random rng) {
  final root = 40 + rng.nextInt(20); // E2..B3
  final intervals = <int>{0, 3 + rng.nextInt(2), 7};
  while (intervals.length < 3 + rng.nextInt(4)) {
    intervals.add(rng.nextInt(24));
  }
  final signal = voicedChord([
    for (final interval in intervals)
      (_midiToFreq(root + interval), 0.05 + rng.nextDouble()),
  ], seconds: 1.0);
  final noise = 0.002 * rng.nextDouble();
  for (var i = 0; i < signal.length; i++) {
    signal[i] += noise * (rng.nextDouble() * 2 - 1);
  }
  return signal;
}

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final rng = math.Random(seed);
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  test('property: beta = 0 reproduces the hard zero on random input', () {
    for (var trial = 0; trial < 12; trial++) {
      final signal = _randomVoicing(rng);
      final k = rng.nextDouble();
      final hard = NnlsChroma(
        sampleRate: _sampleRate,
        whiteningMeanCoefficient: k,
      );
      final floored = NnlsChroma(
        sampleRate: _sampleRate,
        whiteningMeanCoefficient: k,
        whiteningSpectralFloor: 0.0,
      );
      for (final frame in frames(
        signal,
        DspConfig.nnlsWindow,
        DspConfig.nnlsHop,
      )) {
        expect(
          floored.process(frame),
          hard.process(frame),
          reason: 'trial $trial, k = $k must be bit-identical at beta = 0',
        );
      }
    }
  });

  test('property: no beta ever yields a negative or non-finite chroma', () {
    for (var trial = 0; trial < 12; trial++) {
      final signal = _randomVoicing(rng);
      final nc = NnlsChroma(
        sampleRate: _sampleRate,
        whiteningMeanCoefficient: rng.nextDouble(),
        whiteningSpectralFloor: rng.nextDouble(),
      );
      for (final frame in frames(
        signal,
        DspConfig.nnlsWindow,
        DspConfig.nnlsHop,
      )) {
        final chroma = nc.process(frame);
        if (chroma == null) continue;
        for (final value in chroma) {
          expect(value, greaterThanOrEqualTo(0.0));
          expect(value.isFinite, isTrue);
        }
      }
    }
  });

  test('property: the floor only converts zeroed bins into kept ones', () {
    // rescued + zeroed at any beta > 0 is exactly the set the hard zero
    // discarded — the invariant the sweep's `rescued` number depends on.
    for (var trial = 0; trial < 12; trial++) {
      final signal = _randomVoicing(rng);
      final k = 0.1 + rng.nextDouble() * 0.9;
      final beta = 0.001 + rng.nextDouble() * 0.5;
      final hard = NnlsChroma(
        sampleRate: _sampleRate,
        whiteningMeanCoefficient: k,
      );
      final floored = NnlsChroma(
        sampleRate: _sampleRate,
        whiteningMeanCoefficient: k,
        whiteningSpectralFloor: beta,
      );
      for (final frame in frames(
        signal,
        DspConfig.nnlsWindow,
        DspConfig.nnlsHop,
      )) {
        if (hard.process(frame) == null) continue;
        floored.process(frame);
        expect(hard.lastWhiteningRescuedFraction, 0.0);
        expect(
          floored.lastWhiteningRescuedFraction +
              floored.lastWhiteningZeroedFraction,
          closeTo(hard.lastWhiteningZeroedFraction, 1e-12),
          reason: 'trial $trial, k = $k, beta = $beta',
        );
        expect(
          floored.lastWhiteningZeroedFraction,
          lessThanOrEqualTo(hard.lastWhiteningZeroedFraction),
        );
      }
    }
  });

  test('property: a bin the rectifier kept is monotone in beta', () {
    // Raising the floor can only raise (or leave) a bin's pre-division value, so
    // the count of surviving bins must never fall as beta rises. A violation
    // would mean the `max` has been written the wrong way round somewhere.
    for (var trial = 0; trial < 8; trial++) {
      final signal = _randomVoicing(rng);
      final k = 0.1 + rng.nextDouble() * 0.9;
      final frameList = frames(
        signal,
        DspConfig.nnlsWindow,
        DspConfig.nnlsHop,
      ).toList();
      var previous = double.infinity;
      for (final beta in const [0.0, 0.01, 0.05, 0.2, 0.6, 1.0]) {
        final nc = NnlsChroma(
          sampleRate: _sampleRate,
          whiteningMeanCoefficient: k,
          whiteningSpectralFloor: beta,
        );
        var worstZeroed = 0.0;
        for (final frame in frameList) {
          if (nc.process(frame) == null) continue;
          worstZeroed = math.max(worstZeroed, nc.lastWhiteningZeroedFraction);
        }
        expect(
          worstZeroed,
          lessThanOrEqualTo(previous + 1e-12),
          reason: 'trial $trial, k = $k: beta = $beta zeroed MORE bins',
        );
        previous = worstZeroed;
      }
    }
  });
}
