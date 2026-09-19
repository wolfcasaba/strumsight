// MEASUREMENT: does an audible metronome click poison the recogniser?
//
// ## Why this has to be measured before a click can be shipped
//
// Three of the four curriculum rhythm modes declare `needsMetronome: true` and the
// app already ships a metronome (`lib/features/learn/audio/metronome.dart`), yet the
// rhythm screen is silent — a beginner keeps time from an animation while strumming.
// Wiring the existing click in looks like a one-line join.
//
// It is not, because the click goes into the same room the microphone is scoring.
// Two specific, nameable risks:
//
//   1. **False onsets.** The click is a 35 ms decaying sine: a sharp attack, which
//      is exactly what an onset detector is built to notice. A click counted as a
//      strum would be credited to a slot the learner never played, or would push a
//      real stroke out of its slot — flattering and corrupting in one step.
//   2. **Chroma pollution.** The click is 1000 Hz, and 1000 Hz is about B5
//      (987.77 Hz). B is a chord tone of BOTH E minor (E-G-B) and G (G-B-D) — the
//      course's own first and fourth chords. The accent is 1600 Hz, near G6 (1568),
//      and G is a tone of Em, G and C. So the click does not sit harmlessly outside
//      the music; it lands on pitches the decoder is weighing.
//
// The stimulus is the SHIPPED click — `Metronome.buildClickWav`, the same pure
// function the app plays — not a stand-in, because measuring a different click would
// measure nothing.
//
// What this cannot measure, said plainly: the acoustic path. On a real device the
// click leaves a speaker, crosses a room and re-enters a microphone, losing level
// and gaining room colour and echo, and the platform may duck or echo-cancel it.
// Mixing it straight into the signal is the WORST case for a given level, which is
// the right direction for a safety measurement — and the level at which it starts to
// hurt is the number this file exists to find.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/codec/wav_decoder.dart';
import 'package:strumsight/features/learn/audio/metronome.dart';

import '../../support/modelled_guitar.dart';

const double _bpm = 70; // the course's own quarter tempo
const int _beatsPerBar = 4;
const int _bars = 4;

/// The shipped click, decoded to samples.
List<double> _clickSamples({required bool accent}) {
  final wav = accent
      ? Metronome.buildClickWav(freq: 1600, amp: 0.7)
      : Metronome.buildClickWav(freq: 1000, amp: 0.5);
  final decoded = WavDecoder.decode(Uint8List.fromList(wav));
  expect(
    decoded,
    isNotNull,
    reason: 'the shipped click must be a readable WAV',
  );
  expect(decoded!.$2, modelledSampleRate);
  return decoded.$1;
}

double _peak(List<double> pcm) =>
    pcm.fold<double>(0, (best, s) => math.max(best, s.abs()));

/// Four bars of down-quarters over a held chord, as the course's chord rungs ask.
///
/// The ring deliberately OVERLAPS the next beat, which is right for the question this
/// file asks (does a click change the chord the decoder names?) and wrong for
/// counting onsets. So the `n/16` strum counts this file prints are INFLATED by the
/// stimulus itself — measured at 23 for 16 struck — and they are not the claim here;
/// they are printed for context. The claim rests on chord identity, on confirmed-frame
/// counts, and on the clicks-only takes, which contain no guitar and so cannot
/// overlap. See `modelled_strum_overlap_test.dart` and the rule on
/// `addStrummedChord`. The stimulus is left as it was on purpose: ADR 0546 quotes
/// these numbers, and changing it would make them irreproducible.
List<double> _performance(String chord) {
  final beatSec = 60 / _bpm;
  final total = _bars * _beatsPerBar * beatSec + 1.0;
  final pcm = List<double>.filled((total * modelledSampleRate).round(), 0);
  for (var beat = 0; beat < _bars * _beatsPerBar; beat++) {
    addStrummedChord(
      pcm,
      chord,
      atSec: beat * beatSec,
      ringSeconds: beatSec * 1.6,
      seedBase: 1000 + beat * 37,
    );
  }
  return pcm;
}

/// Mixes a click onto every beat at [gain] relative to full scale.
List<double> _withClicks(List<double> pcm, {required double gain}) {
  final out = List<double>.of(pcm);
  final beatSec = 60 / _bpm;
  final plain = _clickSamples(accent: false);
  final accent = _clickSamples(accent: true);
  for (var beat = 0; beat < _bars * _beatsPerBar; beat++) {
    final click = beat % _beatsPerBar == 0 ? accent : plain;
    final start = (beat * beatSec * modelledSampleRate).round();
    for (var i = 0; i < click.length; i++) {
      final at = start + i;
      if (at < out.length) out[at] += click[i] * gain;
    }
  }
  return out;
}

/// What the engine made of a take: strums heard, and the chord it settled on.
({int strums, String? chord, int confirmedFrames}) _observe(List<double> pcm) {
  final frames = chordFrames(pcm);
  final histogram = <String, int>{};
  var confirmed = 0;
  for (final frame in frames) {
    if (!frame.isConfirmed || frame.label == null) continue;
    confirmed++;
    histogram[frame.label!] = (histogram[frame.label!] ?? 0) + 1;
  }
  final chord = histogram.isEmpty
      ? null
      : histogram.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  return (strums: strumCount(pcm), chord: chord, confirmedFrames: confirmed);
}

void main() {
  const expectedStrums = _bars * _beatsPerBar;

  test(
    'MEASURE: at what level does the click start to corrupt recognition?',
    () {
      // The click is mixed in at a sweep of levels relative to full scale. The
      // guitar's own peak is printed alongside, so the ratio is readable rather
      // than implied.
      for (final chord in const ['Em', 'G', 'Am']) {
        final clean = _performance(chord);
        final guitarPeak = _peak(clean);
        final baseline = _observe(clean);
        // ignore: avoid_print
        print(
          '$chord | guitar peak ${guitarPeak.toStringAsFixed(2)} | '
          'NO CLICK: ${baseline.strums}/$expectedStrums strums, '
          'chord ${baseline.chord ?? "(none)"}, '
          '${baseline.confirmedFrames} confirmed frames',
        );
        for (final gain in const [0.03, 0.1, 0.3, 1.0]) {
          final observed = _observe(_withClicks(clean, gain: gain));
          final dbRelGuitar = 20 * math.log(gain / guitarPeak) / math.ln10;
          // ignore: avoid_print
          print(
            '  click gain ${gain.toStringAsFixed(2)} '
            '(${dbRelGuitar.toStringAsFixed(0)} dB vs guitar): '
            '${observed.strums}/$expectedStrums strums, '
            'chord ${observed.chord ?? "(none)"}, '
            '${observed.confirmedFrames} confirmed frames',
          );
        }
      }
    },
  );

  test('MEASURE: does the click alone, with NO guitar, read as playing?', () {
    // The cleanest form of the false-onset question, and the one that decides
    // whether a click can sound during the count-in: with nothing but clicks, does
    // the engine report strums, or a chord?
    final beatSec = 60 / _bpm;
    final silent = List<double>.filled(
      ((_bars * _beatsPerBar * beatSec + 1.0) * modelledSampleRate).round(),
      0,
    );
    for (final gain in const [0.1, 0.3, 1.0]) {
      final observed = _observe(_withClicks(silent, gain: gain));
      // ignore: avoid_print
      print(
        'clicks only, gain ${gain.toStringAsFixed(2)}: '
        '${observed.strums} strums reported, '
        'chord ${observed.chord ?? "(none)"}, '
        '${observed.confirmedFrames} confirmed frames',
      );
    }
  });

  test('MEASURE: is the click landing on the chroma bins it sounds like?', () {
    // 1000 Hz is ~B5 and 1600 Hz is ~G6. B is a tone of Em and G; G is a tone of
    // Em, G and C. If the click is heard as pitch at all, the chords it biases
    // towards are the course's own — so this prints what the engine names when fed
    // only clicks at a level where it names anything.
    final beatSec = 60 / _bpm;
    final silent = List<double>.filled(
      ((_bars * _beatsPerBar * beatSec + 1.0) * modelledSampleRate).round(),
      0,
    );
    final observed = _observe(_withClicks(silent, gain: 1.0));
    // ignore: avoid_print
    print(
      'clicks at full scale are named: ${observed.chord ?? "(nothing)"} '
      '(${observed.confirmedFrames} confirmed frames)',
    );
  });
}
