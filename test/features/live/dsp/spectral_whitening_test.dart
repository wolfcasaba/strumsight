import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/dsp/chord_dictionary.dart';
import 'package:strumsight/features/live/engine/dsp/chord_matcher.dart';
import 'package:strumsight/features/live/engine/dsp/dsp_config.dart';
import 'package:strumsight/features/live/engine/dsp/nnls_chroma.dart';
import 'package:strumsight/features/live/engine/dsp/viterbi_chord_decoder.dart';

import '../../../support/synth.dart';

/// Spectral whitening (chunk 012, Chordino stage): flatten the spectral
/// envelope before NNLS so timbre/EQ — a phone mic's steep bass roll-off, a
/// guitar body's resonance — can't outvote the actual notes. The measured
/// round-70 failure: a "thin mic" low-shelf cut (fundamentals below 300 Hz
/// attenuated ×0.15) made a C major read as **Em** — the fundamentals
/// vanished under their own harmonics.
Float64List thinMicChord(
  List<double> freqs, {
  double cutHz = 300,
  double atten = 0.15,
}) => mixNotes([
  for (final f in freqs)
    colouredNote(
      freq: f,
      seconds: 1.5,
      gain: (h, hf) => (0.15 / h) * (hf < cutHz ? atten : 1.0),
    ),
]);

/// Decode [signal]; [halfSemitones] overrides the shipped whitening span so
/// a test can state what the OLD span did, not only what the new one does.
String? decode(Float64List signal, {double? halfSemitones}) {
  final nc = halfSemitones == null
      ? NnlsChroma(sampleRate: 44100)
      : NnlsChroma(sampleRate: 44100, whiteningHalfSemitones: halfSemitones);
  final decoder = ViterbiChordDecoder(
    selfBonus: DspConfig.chordSelfTransitionBonus,
    dictionary: ChordDictionary(),
  );
  ChordMatch? last;
  for (final frame in frames(signal, DspConfig.nnlsWindow, DspConfig.nnlsHop)) {
    final chroma = nc.process(frame);
    final tonal =
        chroma != null && nc.lastTonalness >= DspConfig.chordMinTonalness;
    last = tonal
        ? decoder.process(nc.lastBassChroma, nc.lastTrebleChroma)
        : decoder.process(Float64List(12), Float64List(12));
  }
  return last?.chord.label;
}

void main() {
  test('thin-mic C major (bass rolled off below 300 Hz) still reads as C', () {
    expect(decode(thinMicChord(cMajorFreqs)), 'C');
  });

  test('thin-mic A minor still reads as Am', () {
    expect(decode(thinMicChord(aMinorFreqs)), 'Am');
  });

  test('a body resonance (500 Hz bump) does not change the reading', () {
    final signal = mixNotes([
      for (final f in cMajorFreqs)
        colouredNote(
          freq: f,
          seconds: 1.5,
          gain: (h, hf) =>
              (0.15 / h) * (1 + 4 * math.exp(-math.pow((hf - 500) / 120, 2))),
        ),
    ]);
    expect(decode(signal), 'C');
  });

  test('neutral timbre is unaffected (regression guard)', () {
    expect(decode(chordSignal(cMajorFreqs, seconds: 1.5)), 'C');
  });

  // ---------------------------------------------------------------------
  // The OTHER thing the whitening neighbourhood decides: LOCAL level.
  //
  // Whitening divides each log-frequency bin by the RMS of its
  // +/-`whiteningHalfSemitones` neighbourhood, so the span sets what "loud" is
  // measured against. At a WIDE span a bin is normalised against most of an
  // octave and a quiet tone stays quiet relative to its loud neighbours; at a
  // NARROWER span each local peak is normalised by its own neighbourhood and
  // the peaks are pulled toward a common level.
  //
  // That decides real guitar chords, because a guitar voicing is not
  // level-flat: the fifth is doubled across two or three strings while the
  // third is fretted exactly once, so the tone that determines the QUALITY is
  // routinely the quietest thing in the signal. MEASURED on the E18-R01
  // reference recordings: in the open E the third G#3 sat at 0.12 of the peak
  // against the fifth B2 at 0.97, and the decoder returned `Bsus4` -- a
  // profile built wholly on the loud root and fifth, the chord's own third
  // invisible. Narrowing the span took the seven labelled recordings from 4/7
  // to 7/7 correct AND confirmed. ADR 0540 carries the full sweep.
  //
  // HOW FAR THESE CASES REACH -- measured, and less far than one would like.
  // The synthetic note model (a 1/h series, six harmonics) does not put energy
  // where a real string does, and as a probe of the SPAN it is non-monotone: an
  // open-G voicing decodes correctly with a 0.30 third at both +/-6 and +/-3.5
  // yet at NO third level at +/-4, which is the signature of a signal sitting
  // on a decision boundary rather than a smooth measure. So only the open-E
  // case below actually reproduces the shipped fix without audio; the rest of
  // this group is non-regression. The improvement itself rests on the real
  // recordings, and ADR 0540 states that instead of implying the synth carries
  // it.
  group('a quiet chord third still decides the chord', () {
    /// Open E (022100), levels from the reference recording; [third] is G#3.
    List<(double, double)> openE(double third) => [
      (82.41, 0.60), // E2
      (123.47, 0.97), // B2  the fifth, doubled and loud
      (164.81, 1.00), // E3
      (207.65, third), // G#3 the major third, fretted once
      (246.94, 0.49), // B3
      (329.63, 0.53), // E4
    ];

    /// Open A minor (x02210); [third] is C4.
    List<(double, double)> openAm(double third) => [
      (110.00, 0.90), // A2
      (164.81, 1.00), // E3  the fifth
      (220.00, 0.60), // A3
      (261.63, third), // C4  the minor third
      (329.63, 0.50), // E4
    ];

    /// Open E minor (022000); [third] is G3.
    List<(double, double)> openEm(double third) => [
      (82.41, 0.60), // E2
      (123.47, 0.97), // B2  the fifth
      (164.81, 1.00), // E3
      (196.00, third), // G3  the minor third
      (246.94, 0.49), // B3
      (329.63, 0.53), // E4
    ];

    /// The span as built in round 70, for the "what changed" half of a claim.
    const oldHalfOctave = 6.0;

    test('an open E whose third is at 0.08 reads as E - it did not at the old '
        'half-octave span', () {
      // The one case that reproduces the shipped fix without audio.
      expect(
        decode(voicedChord(openE(0.08)), halfSemitones: oldHalfOctave),
        isNot('E'),
        reason: 'the wide span must still show the failure this fix addresses',
      );
      expect(decode(voicedChord(openE(0.08))), 'E');
    });

    test('a clearly present third is unaffected by the span', () {
      // Where the evidence is not marginal both spans agree: the change buys
      // recall at the quiet end, it does not move the ordinary case.
      for (final span in const <double?>[null, oldHalfOctave]) {
        expect(decode(voicedChord(openE(0.40)), halfSemitones: span), 'E');
        expect(decode(voicedChord(openAm(0.40)), halfSemitones: span), 'Am');
        expect(decode(voicedChord(openEm(0.40)), halfSemitones: span), 'Em');
      }
    });

    test('minor chords with a quiet third stay MINOR - no phantom major', () {
      // The inverse risk of lifting quiet tones is manufacturing a major third.
      // It does not happen: an open Em is correct down to 0.08, and nothing
      // here ever reads as the parallel major.
      for (final third in const [0.40, 0.22, 0.16, 0.12, 0.08]) {
        expect(
          decode(voicedChord(openEm(third))),
          'Em',
          reason: 'open Em with its third at $third',
        );
        expect(
          decode(voicedChord(openAm(third))),
          isNot('A'),
          reason: 'open Am with its third at $third must never read A',
        );
      }
      // The floor we DO hold for Am. Below this the synthetic voicing falls to
      // `Esus4` -- a profile on its own fifth, the same class of failure this
      // change fixes elsewhere; at the old span that floor was 0.12 rather than
      // 0.22. Pinned at what is measured so further erosion is caught, with the
      // loss recorded in ADR 0540 rather than hidden here.
      expect(decode(voicedChord(openAm(0.22))), 'Am');
    });

    test(
      'a GENUINE sus4 is still a sus4 (the span does not invent thirds)',
      () {
        expect(
          decode(
            voicedChord(const [
              (146.83, 1.00), // D3
              (220.00, 0.90), // A3  fifth
              (293.66, 0.80), // D4
              (392.00, 0.85), // G4  the fourth, clearly present
            ]),
          ),
          'Dsus4',
        );
      },
    );

    test('a GENUINE dominant 7th does not collapse to its triad', () {
      expect(
        decode(
          voicedChord(const [
            (110.00, 1.00), // A2
            (164.81, 0.85), // E3
            (220.00, 0.70), // A3
            (277.18, 0.80), // C#4 third
            (329.63, 0.60), // E4
            (392.00, 0.85), // G4  the dominant 7th
          ]),
        ),
        'A7',
      );
    });
  });
}
