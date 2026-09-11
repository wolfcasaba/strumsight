// The whitening rectifier's SPECTRAL FLOOR (E18-R11).
//
// `whiteningSpectralFloor` (beta) replaces the half-wave rectifier's hard zero
// with `max(d, beta * s[j])` — the gain-domain form of the spectral floor that
// Berouti, Schwartz & Makhoul (ICASSP 1979) introduced to stop spectral
// subtraction's hard zero from producing musical noise.
//
// This file guards three things, in descending order of how much they matter:
//
//   1. PARITY. At beta = 0 the arithmetic is `max(d, 0)` — the hard zero — so the
//      dial must be bit-for-bit inert at its default. Everything the E18-R10
//      sweep measured has to stay true, or its numbers become unreadable.
//   2. SAFETY. The NNLS stage assumes a non-negative spectrum: a negative bin
//      makes `D^T s` negative and the multiplicative update flips the
//      activation's sign on every iteration. The floor must never produce one.
//   3. THE MEASURED NEGATIVE RESULT. The floor does NOT save the quiet major
//      third, and the reason is pinned here rather than left to be rediscovered:
//      the third's bin was never zeroed in the first place.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/dsp/dsp_config.dart';
import 'package:strumsight/features/live/engine/dsp/nnls_chroma.dart';

import '../../../support/synth.dart';

const _coefficients = [0.0, 0.25, 0.5, 0.75, 1.0];

/// Open E (022100) with its major third G#3 at 0.08 of the peak — the E18-R01
/// voicing that `spectral_whitening_test.dart` guards.
Float64List _quietThirdE() => voicedChord(const [
  (82.41, 0.60), // E2
  (123.47, 0.97), // B2  the fifth, doubled and loud
  (164.81, 1.00), // E3
  (207.65, 0.08), // G#3 the major third, fretted once
  (246.94, 0.49), // B3
  (329.63, 0.53), // E4
]);

/// Every frame's chroma for [signal], at one whitening setting.
List<List<double>> _chromaSeries(
  Float64List signal, {
  double meanCoefficient = 0.0,
  double? spectralFloor,
}) {
  final nc = spectralFloor == null
      ? NnlsChroma(sampleRate: 44100, whiteningMeanCoefficient: meanCoefficient)
      : NnlsChroma(
          sampleRate: 44100,
          whiteningMeanCoefficient: meanCoefficient,
          whiteningSpectralFloor: spectralFloor,
        );
  final out = <List<double>>[];
  for (final frame in frames(signal, DspConfig.nnlsWindow, DspConfig.nnlsHop)) {
    final chroma = nc.process(frame);
    out.add(chroma == null ? const <double>[] : List<double>.from(chroma));
  }
  return out;
}

void main() {
  test('the shipped default is a hard zero — the dial is off', () {
    expect(NnlsChroma(sampleRate: 44100).whiteningSpectralFloor, 0.0);
  });

  group('PARITY: beta = 0 is the hard zero, bit for bit', () {
    test('passing beta = 0 equals not passing it at all, at every k', () {
      final signal = _quietThirdE();
      for (final k in _coefficients) {
        final withoutDial = _chromaSeries(signal, meanCoefficient: k);
        final withZero = _chromaSeries(
          signal,
          meanCoefficient: k,
          spectralFloor: 0.0,
        );
        expect(withZero, withoutDial, reason: 'k = $k must be untouched');
      }
    });

    test('on the divide-only path the floor is inert at ANY beta', () {
      // k = 0 never subtracts, so there is nothing to rectify and nothing to
      // floor. Guarded because it is the SHIPPED path: a floor that leaked into
      // it would change production behaviour while the sweep said otherwise.
      final signal = _quietThirdE();
      final shipped = _chromaSeries(signal);
      for (final beta in const [0.0, 0.02, 0.2, 0.9, 1.0]) {
        expect(
          _chromaSeries(signal, spectralFloor: beta),
          shipped,
          reason: 'beta = $beta must not reach the divide-only path',
        );
      }
    });
  });

  group('SAFETY: the NNLS stage gets a non-negative spectrum', () {
    test('no chroma component is ever negative, at any beta', () {
      final signal = _quietThirdE();
      for (final k in _coefficients) {
        for (final beta in const [0.0, 0.02, 0.2, 0.5, 1.0]) {
          final nc = NnlsChroma(
            sampleRate: 44100,
            whiteningMeanCoefficient: k,
            whiteningSpectralFloor: beta,
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
            for (final value in nc.lastBassChroma) {
              expect(value, greaterThanOrEqualTo(0.0));
            }
            for (final value in nc.lastTrebleChroma) {
              expect(value, greaterThanOrEqualTo(0.0));
            }
          }
        }
      }
    });

    test('the rectifier is continuous at the threshold', () {
      // `max(d, beta*s)` is a max of two continuous functions, so the chroma has
      // to converge to the hard-zero chroma as beta -> 0+. Measured rather than
      // argued: a discontinuity here would mean a tiny beta could flip a chord.
      final signal = _quietThirdE();
      final hardZero = _chromaSeries(signal, meanCoefficient: 0.75);
      double distance(double beta) {
        final series = _chromaSeries(
          signal,
          meanCoefficient: 0.75,
          spectralFloor: beta,
        );
        var worst = 0.0;
        for (var f = 0; f < hardZero.length; f++) {
          for (var i = 0; i < hardZero[f].length; i++) {
            final delta = (series[f][i] - hardZero[f][i]).abs();
            if (delta > worst) worst = delta;
          }
        }
        return worst;
      }

      expect(distance(1e-9), lessThan(1e-6));
      expect(distance(1e-6), lessThan(1e-4));
      expect(distance(1e-9), lessThanOrEqualTo(distance(1e-3)));
    });

    test('the floor only ever converts a zeroed bin into a kept one', () {
      // The bookkeeping invariant behind the `rescued` number the sweep prints:
      // at any beta > 0, rescued + zeroed is exactly the set of bins the hard
      // zero discarded. If that stops holding, the sweep's rescue fraction is
      // measuring something else.
      final signal = _quietThirdE();
      for (final frame in frames(
        signal,
        DspConfig.nnlsWindow,
        DspConfig.nnlsHop,
      )) {
        final hard = NnlsChroma(
          sampleRate: 44100,
          whiteningMeanCoefficient: 0.75,
        );
        final floored = NnlsChroma(
          sampleRate: 44100,
          whiteningMeanCoefficient: 0.75,
          whiteningSpectralFloor: 0.05,
        );
        if (hard.process(frame) == null) continue;
        floored.process(frame);
        expect(hard.lastWhiteningRescuedFraction, 0.0);
        expect(hard.lastWhiteningZeroedFraction, greaterThan(0.0));
        expect(
          floored.lastWhiteningRescuedFraction +
              floored.lastWhiteningZeroedFraction,
          closeTo(hard.lastWhiteningZeroedFraction, 1e-12),
        );
      }
    });
  });

  group('MEASURED: the floor does not save the quiet major third', () {
    // E18-R11's hypothesis was that the quiet third is weak-but-real energy the
    // hard zero deletes. It is not. The third's own bin is ABOVE its local mean,
    // so the rectifier never clamps it — the mean SUBTRACTION shrinks it, taking
    // a larger relative share from a weak peak than from a loud one. A floor on
    // a clamp that never fires cannot help, and the grid in
    // `docs/research/soft-floor-rectifier-2026-09.md` shows exactly that.
    //
    // Pinned here so the round is not re-run blind on the same idea.
    test('the third bin is never zeroed, so there is nothing to rescue', () {
      final signal = _quietThirdE();
      for (final k in const [0.25, 0.5, 0.75, 1.0]) {
        final nc = NnlsChroma(sampleRate: 44100, whiteningMeanCoefficient: k);
        var sawFrame = false;
        for (final frame in frames(
          signal,
          DspConfig.nnlsWindow,
          DspConfig.nnlsHop,
        )) {
          if (nc.process(frame) == null) continue;
          sawFrame = true;
          expect(
            nc.debugWhitenedRelativeAt(207.65),
            greaterThan(0.0),
            reason:
                'G#3 survives the hard zero at k = $k — it is shrunk, '
                'not deleted',
          );
        }
        expect(sawFrame, isTrue, reason: 'the stimulus must produce frames');
      }
    });

    test('a published-range beta leaves the third bin weight unchanged', () {
      // beta in 0.02..0.20 is the literature's own range (a -34 dB .. -14 dB
      // gain floor). Over it the third's weight does not move at all, which is
      // the quantitative form of "the clamp never fired on this bin".
      final signal = _quietThirdE();
      final frameList = frames(
        signal,
        DspConfig.nnlsWindow,
        DspConfig.nnlsHop,
      ).toList();
      double weightAt(double beta) {
        final nc = NnlsChroma(
          sampleRate: 44100,
          whiteningMeanCoefficient: 0.75,
          whiteningSpectralFloor: beta,
        );
        var sum = 0.0;
        var counted = 0;
        for (final frame in frameList) {
          if (nc.process(frame) == null) continue;
          sum += nc.debugWhitenedRelativeAt(207.65);
          counted++;
        }
        return counted == 0 ? 0 : sum / counted;
      }

      final baseline = weightAt(0.0);
      expect(baseline, greaterThan(0.0));
      for (final beta in const [0.02, 0.05, 0.10, 0.20]) {
        expect(
          weightAt(beta),
          closeTo(baseline, 1e-12),
          reason: 'beta = $beta must not move a bin the clamp never touched',
        );
      }
    });
  });
}
