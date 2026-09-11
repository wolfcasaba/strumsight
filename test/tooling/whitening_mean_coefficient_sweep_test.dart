// SWEEP: how much local mean can whitening subtract before it starts lying?
//
//   REAL_AUDIO_DIR=/path/to/wavs flutter test \
//     test/tooling/whitening_mean_coefficient_sweep_test.dart
//
// At the full reference value the engine hears far more on real recordings and
// also loses a QUIET MAJOR THIRD, reading an open E as `Em`. Major-for-minor is
// the worst error this app can make — those are the chords the beginner course
// teaches — so the question is not "on or off" but "how far can this go before
// it costs a third".
//
// Three criteria are measured on the SAME axis, because a gain on one is only
// worth having if it does not buy a loss on another:
//
//   1. the quiet third — an open E with its third at 0.08 must stay `E`;
//   2. the modelled chords — seven with exact ground truth must stay correct;
//   3. real recordings — named frames, and the share of them that are `sus4`
//      or `aug`, the qualities the probe found over-reported.
//
// The three stimuli now live in `test/support/whitening_sweep.dart`, shared with
// the E18-R11 spectral-floor grid: that grid has to reproduce THIS row exactly
// as its beta = 0 column, and it can only do so if both read the same harness.
import 'package:flutter_test/flutter_test.dart';

import '../support/whitening_sweep.dart';

const _coefficients = [0.0, 0.25, 0.5, 0.75, 1.0];

/// Both kernels, because E18-R12 measured that the kernel and the coefficient
/// are NOT independent: with the flat box the quiet third is lost from k = 0.15
/// upward, while with the shipped Hamming kernel it survives every k in this
/// grid. A sweep of k alone would have read as "mean subtraction always costs a
/// third", which is only true of the kernel that no longer ships.
const _kernels = [false, true];

void main() {
  test('SWEEP the mean coefficient across all three criteria', () {
    final modelledPcm = {
      for (final chord in modelledChords) chord: strumChord(chord),
    };
    final realFiles = realAudioFiles();

    final lines = <String>[];
    for (final hamming in _kernels) {
      for (final coefficient in _coefficients) {
        final setting = WhiteningSetting(
          meanCoefficient: coefficient,
          hammingKernel: hamming,
        );
        final quietTop = quietThird(setting);
        var correct = 0;
        for (final chord in modelledChords) {
          final run = runPipeline(
            modelledPcm[chord]!,
            sweepSampleRate,
            setting,
          );
          if (topChord(run.chords) == chord) correct++;
        }

        var named = 0;
        var colour = 0.0;
        var counted = 0;
        for (final file in realFiles) {
          final decoded = decodeWav(file);
          if (decoded == null) continue;
          final result = runPipeline(decoded.pcm, decoded.sampleRate, setting);
          named += result.confirmed;
          colour += colourShare(result.chords);
          counted++;
        }

        lines.add(
          '${hamming ? "hamming" : "box    "}  '
          'k=${coefficient.toStringAsFixed(2)}  '
          'quiet-third=${quietTop ?? "-"}  '
          'modelled=$correct/${modelledChords.length}  '
          'real: named=$named  '
          'sus4+aug=${counted == 0 ? "-" : (colour / counted * 100).toStringAsFixed(1)}%',
        );
      }
    }

    // ignore: avoid_print
    print('\nWHITENING MEAN-COEFFICIENT SWEEP\n${lines.join("\n")}\n');
    expect(lines, isNotEmpty);
  });
}
