// SWEEP (E18-R11): does a SPECTRAL FLOOR on the whitening rectifier buy the
// real-audio gains without the major-for-minor error?
//
//   REAL_AUDIO_DIR=/path/to/wavs flutter test \
//     test/tooling/whitening_spectral_floor_sweep_test.dart
//
// E18-R10 measured that subtracting the local mean and HALF-WAVE RECTIFYING
// helps hard real audio a great deal and costs a quiet major third — an open E
// whose third sits at 0.08 of the peak reads as `Em`. Every cost traced to the
// same place: the hard zero throws away weak-but-real energy.
//
// That is a named, solved failure in speech enhancement. "Subtract an estimate,
// clamp the negatives to zero" is spectral subtraction, and its textbook
// artefact is musical noise; Berouti, Schwartz & Makhoul (ICASSP 1979) fixed it
// by flooring the output at a small fraction instead of zero. The dial is
// `whiteningSpectralFloor` (beta), gain-domain: `max(d, beta * s[j])`.
//
// This is a 2-D grid over (k, beta), at one or two exponents. The beta = 0
// column MUST reproduce `whitening_mean_coefficient_sweep_test.dart` exactly —
// at beta = 0 the arithmetic is `max(d, 0)`, i.e. the hard zero — and if it does
// not, the harness is wrong and nothing else in the grid may be read.
//
// The grid is overridable so a promising cell can be refined without editing
// this file (comma-separated):
//
//   FLOOR_SWEEP_K=0.5,0.75  FLOOR_SWEEP_BETA=0.03,0.04  FLOOR_SWEEP_W=0.7,1.0
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/whitening_sweep.dart';

const _defaultK = [0.25, 0.5, 0.75, 1.0];
const _defaultBeta = [0.0, 0.02, 0.05, 0.10, 0.20];
const _defaultW = [0.7];

List<double> _axis(String variable, List<double> fallback) {
  final raw = Platform.environment[variable];
  if (raw == null || raw.trim().isEmpty) return fallback;
  final parsed = <double>[];
  for (final part in raw.split(',')) {
    final value = double.tryParse(part.trim());
    if (value != null) parsed.add(value);
  }
  return parsed.isEmpty ? fallback : parsed;
}

String _percent(double? share) =>
    share == null ? 'silent' : '${(share * 100).round()}%';

void main() {
  test('SWEEP the spectral floor against the mean coefficient', () {
    final ks = _axis('FLOOR_SWEEP_K', _defaultK);
    final betas = _axis('FLOOR_SWEEP_BETA', _defaultBeta);
    final ws = _axis('FLOOR_SWEEP_W', _defaultW);

    final modelledPcm = {
      for (final chord in modelledChords) chord: strumChord(chord),
    };
    final realFiles = realAudioFiles();

    // Decode once: the WAVs are re-run at every cell, and re-decoding them per
    // cell made the grid IO-bound rather than DSP-bound.
    final recordings = <({String name, List<double> pcm, int sampleRate})>[];
    for (final file in realFiles) {
      final decoded = decodeWav(file);
      if (decoded == null) continue;
      recordings.add((
        name: file.uri.pathSegments.last,
        pcm: decoded.pcm,
        sampleRate: decoded.sampleRate,
      ));
    }

    // The shipped row, printed first so every cell below is read against it
    // rather than against memory.
    final shipped = const WhiteningSetting();
    final header = <String>[
      'SHIPPED (k=0, divide only): quiet-third=${quietThird(shipped) ?? "-"}',
    ];

    final lines = <String>[];
    for (final w in ws) {
      for (final k in ks) {
        for (final beta in betas) {
          final setting = WhiteningSetting(
            meanCoefficient: k,
            spectralFloor: beta,
            exponent: w,
          );

          // Criterion 1: the blocker. The shipped fixture's own voicing and
          // decode path.
          final quietTop = quietThird(setting);

          // Criterion 2: seven chords with exact ground truth.
          var correct = 0;
          for (final chord in modelledChords) {
            final run = runPipeline(
              modelledPcm[chord]!,
              sweepSampleRate,
              setting,
            );
            if (topChord(run.chords) == chord) correct++;
          }

          // Criterion 3: the ten recordings.
          var named = 0;
          var colour = 0.0;
          var counted = 0;
          var rescued = 0.0;
          var zeroed = 0.0;
          double? bMinor;
          double? fMinor;
          for (final recording in recordings) {
            final run = runPipeline(
              recording.pcm,
              recording.sampleRate,
              setting,
            );
            named += run.confirmed;
            colour += colourShare(run.chords);
            rescued += run.rescuedFraction;
            zeroed += run.zeroedFraction;
            counted++;
            final tonic = tonicFromName(recording.name);
            if (tonic == null) continue;
            final share = inKeyShare(run.chords, tonic);
            // Two files carry a key in their name: B minor (the one that
            // decodes well, 82 % in key as shipped) and F minor (the one that
            // names nothing at all as shipped). They are the two most
            // meaningful real-audio numbers available, so they are reported
            // individually rather than averaged into anything.
            if (tonic == 11) bMinor = share;
            if (tonic == 5) fMinor = share;
          }

          lines.add(
            'w=${w.toStringAsFixed(1)} '
            'k=${k.toStringAsFixed(2)} '
            'beta=${beta.toStringAsFixed(2)}  '
            'quiet-third=${(quietTop ?? "-").padRight(6)} '
            'modelled=$correct/${modelledChords.length}  '
            'named=${named.toString().padLeft(4)}  '
            'sus4+aug=${counted == 0 ? "-" : (colour / counted * 100).toStringAsFixed(1).padLeft(5)}%  '
            'Bm-in-key=${_percent(bMinor).padLeft(6)}  '
            'Fm-in-key=${_percent(fMinor).padLeft(6)}  '
            'rescued=${counted == 0 ? "-" : (rescued / counted * 100).toStringAsFixed(1).padLeft(5)}% '
            'zeroed=${counted == 0 ? "-" : (zeroed / counted * 100).toStringAsFixed(1).padLeft(5)}%',
          );
        }
      }
    }

    // ignore: avoid_print
    print(
      '\nWHITENING SPECTRAL-FLOOR GRID\n'
      '${header.join("\n")}\n${lines.join("\n")}\n',
    );
    expect(lines, isNotEmpty);
  });

  // WHY a cell fails, not just that it does. The decoded label cannot tell a
  // DELETED third from an under-weighted one, and the whole spectral-floor
  // hypothesis is that the hard zero deletes it — so read the bin itself.
  test('MECHANISM: the quiet third bin weight against the floor', () {
    final lines = <String>[];
    for (final w in _axis('FLOOR_SWEEP_W', const [0.7])) {
      for (final k in _axis('FLOOR_SWEEP_K', const [0.0, 0.25, 0.75])) {
        for (final beta in _axis('FLOOR_SWEEP_BETA', const [
          0.0,
          0.02,
          0.05,
          0.20,
          0.50,
          0.90,
          1.0,
        ])) {
          final setting = WhiteningSetting(
            meanCoefficient: k,
            spectralFloor: beta,
            exponent: w,
          );
          lines.add(
            'w=${w.toStringAsFixed(1)} '
            'k=${k.toStringAsFixed(2)} '
            'beta=${beta.toStringAsFixed(2)}  '
            'G#3 bin weight='
            '${(quietThirdBinWeight(setting) * 100).toStringAsFixed(3).padLeft(7)}'
            '% of peak  '
            'decoded=${quietThird(setting) ?? "-"}',
          );
        }
      }
    }
    // ignore: avoid_print
    print('\nQUIET-THIRD BIN WEIGHT\n${lines.join("\n")}\n');
    expect(lines, isNotEmpty);
  });
}
