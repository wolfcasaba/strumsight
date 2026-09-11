// MEASUREMENT: can the engine NAME the chords the beginner course asks for?
//
// The named gap this addresses: no MINOR chord has ever been measured, because
// all seven reference recordings are major. A gap that large under a course
// whose first two chords are Em and Am is not something to leave open.
//
// ## What the stimulus is, and what it is not
//
// Each string is synthesised with Karplus-Strong — a physical model of a plucked
// string, not a stack of sine waves. It produces the real mechanism: a noisy
// excitation circulating in a delay line whose length sets the pitch, low-pass
// filtered on every pass so the high partials die first, exactly as they do on a
// real string. That gives a spectrum that EVOLVES over the note, which is what
// the whitening and the NNLS transcription actually have to cope with.
//
// The notes come from the app's OWN data: `ChordShapes` fingerings and
// `GuitarStrings.standard` tuning. So the chord under test is the chord the app
// would show a learner, fret for fret, including the muted strings.
//
// It is still NOT a real guitar. There is no body resonance, no pick noise, no
// fret buzz, no room, and the strings are perfectly in tune with each other.
// This measurement therefore CANNOT close the real-audio gap — it can only fail
// loudly, which is worth a great deal when the alternative is not measuring
// minors at all.
import 'package:flutter_test/flutter_test.dart';

import '../../support/modelled_guitar.dart';

/// The label the engine settles on: the most frequent CONFIRMED chord over the
/// take, or null when it never confirmed one.
///
/// `confirmedFrames` reads the DECISION rather than the mere presence of a label.
/// MEASURED: on this pipeline the two coincide exactly — moving to the decision
/// reproduced the table below digit for digit (34/43, 36/43, 30/43 …), so `current`
/// is published only once a decision has confirmed. Reading the decision is kept
/// because it is the stricter form and the one the curriculum scores on, so it stays
/// correct if that ever stops being true.
({String? label, int confirmedFrames, int frames}) _decode(List<double> pcm) {
  final histogram = <String, int>{};
  var confirmed = 0;
  final frames = chordFrames(pcm);
  for (final frame in frames) {
    final label = frame.label;
    if (label == null || !frame.isConfirmed) continue;
    confirmed++;
    histogram[label] = (histogram[label] ?? 0) + 1;
  }
  if (histogram.isEmpty) {
    return (label: null, confirmedFrames: 0, frames: frames.length);
  }
  final best = histogram.entries.reduce((a, b) => b.value > a.value ? b : a);
  return (label: best.key, confirmedFrames: confirmed, frames: frames.length);
}

void main() {
  // The five chords the beginner course actually scores, plus the two majors
  // whose real-audio behaviour is already known — so a failure here can be told
  // apart from "this whole stimulus is unrealistic".
  const chords = ['Em', 'Am', 'D', 'G', 'C', 'E', 'A'];

  test('MEASURE: the shipped chords, named from modelled audio', () {
    final results = <String, String?>{};
    for (final chord in chords) {
      final decoded = _decode(strumChord(chord));
      results[chord] = decoded.label;
      // ignore: avoid_print
      print(
        '$chord -> ${decoded.label ?? "(nothing confirmed)"} '
        '(${decoded.confirmedFrames}/${decoded.frames} frames)',
      );
    }
    final correct = results.entries
        .where((entry) => entry.value == entry.key)
        .length;
    // ignore: avoid_print
    print('MEASURED: $correct of ${chords.length} named correctly');

    // Deliberately a floor, not a target: the point of this file is to catch a
    // collapse, and a tight threshold on synthetic audio would fail for reasons
    // that say nothing about a real guitar.
    expect(
      correct,
      greaterThanOrEqualTo(5),
      reason:
          'the engine should name most of the course chords on clean modelled '
          'audio; below this something is wrong with the engine or the stimulus',
    );
  });

  test('MEASURE: the MINOR chords specifically — the never-measured gap', () {
    // Em and Am are the first two chords the course teaches, and no minor has
    // ever been verified on real recordings. This is not a substitute for that
    // measurement; it is the difference between "unknown" and "known on
    // modelled audio".
    for (final chord in ['Em', 'Am']) {
      final decoded = _decode(strumChord(chord));
      // ignore: avoid_print
      print('MINOR $chord -> ${decoded.label ?? "(nothing confirmed)"}');
      expect(
        decoded.label,
        chord,
        reason:
            '$chord is a chord the course asks a beginner to play in its first '
            'lessons; naming it wrong would teach them their correct playing is '
            'wrong',
      );
    }
  });

  test('an upstroke of the same chord names the same chord', () {
    // Direction changes which string is struck first, not which chord it is. If
    // the decoder disagreed between the two, the pattern rung would score the
    // same shape differently on the way down and on the way up.
    for (final chord in ['Em', 'Am', 'G']) {
      final down = _decode(strumChord(chord)).label;
      final up = _decode(strumChord(chord, down: false)).label;
      // ignore: avoid_print
      print('$chord down=$down up=$up');
      expect(
        up,
        down,
        reason: '$chord decoded differently by stroke direction',
      );
    }
  });
}
