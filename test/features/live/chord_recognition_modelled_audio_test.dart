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
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/guitar_strings.dart';
import 'package:strumsight/features/chords/public.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';

const int _sampleRate = 44100;

/// One plucked string, physically modelled (Karplus-Strong).
///
/// A burst of noise is pushed into a delay line of length `sampleRate / freq`
/// and averaged with its neighbour on each pass. The averaging is a one-pole
/// low-pass, so each trip round the loop loses more high frequency than low —
/// which is why a real string's tone darkens as it decays, and why this is a far
/// better test of a chroma front-end than steady sine partials.
List<double> _pluckedString({
  required double freqHz,
  required double seconds,
  required int seed,
  double damping = 0.996,
  double amplitude = 0.25,
}) {
  final length = (seconds * _sampleRate).round();
  final delay = math.max(2, (_sampleRate / freqHz).round());
  final random = math.Random(seed);
  final buffer = List<double>.generate(
    delay,
    (_) => random.nextDouble() * 2 - 1,
  );
  // Soften the excitation: a real pick does not inject white noise across the
  // whole spectrum, and an unfiltered burst makes every string sound identical
  // at the attack.
  for (var pass = 0; pass < 2; pass++) {
    for (var i = 1; i < buffer.length; i++) {
      buffer[i] = (buffer[i] + buffer[i - 1]) / 2;
    }
  }
  final out = List<double>.filled(length, 0);
  var index = 0;
  for (var n = 0; n < length; n++) {
    final current = buffer[index];
    final next = buffer[(index + 1) % delay];
    out[n] = current * amplitude;
    buffer[index] = damping * (current + next) / 2;
    index = (index + 1) % delay;
  }
  // Fade the tail so the recording does not END on a step — a step is a real
  // broadband transient and the detector is right to hear it
  // (`onset_double_trigger_diagnosis_test.dart`).
  final fade = (0.03 * _sampleRate).round();
  for (var i = 0; i < fade && i < length; i++) {
    out[length - 1 - i] *= i / fade;
  }
  return out;
}

/// A strummed chord, from the app's own fingering for [label].
///
/// `-1` frets are NOT played, exactly as the diagram says — so an Am really does
/// leave the low E silent, which is part of what makes it an Am rather than a
/// muddier chord.
List<double> _strumChord(
  String label, {
  double seconds = 3.0,
  double spreadSec = 0.022,
  bool down = true,
}) {
  final shape = ChordShapes.forLabel(label);
  expect(shape, isNotNull, reason: 'no shipped fingering for $label');
  final strings = GuitarStrings.standard;
  final pcm = List<double>.filled((seconds * _sampleRate).round(), 0);

  // Fingerings run low-E first; a downstroke meets them in that order.
  final order = [for (var i = 0; i < 6; i++) i];
  final meetOrder = down ? order : order.reversed.toList();

  var voice = 0;
  for (var position = 0; position < meetOrder.length; position++) {
    final stringIndex = meetOrder[position];
    final fret = shape!.frets[stringIndex];
    if (fret < 0) continue; // muted: the pick crosses it, it does not sound
    final midi = strings[stringIndex].midi + fret;
    final freq = 440 * math.pow(2, (midi - 69) / 12).toDouble();
    final offset = (position * spreadSec * _sampleRate).round();
    final tone = _pluckedString(
      freqHz: freq,
      seconds: seconds - position * spreadSec,
      seed: 1000 + voice * 17,
      // The wound low strings ring longer than the plain high ones.
      damping: midi < 55 ? 0.9975 : 0.9955,
    );
    for (var i = 0; i < tone.length; i++) {
      final at = offset + i;
      if (at < pcm.length) pcm[at] += tone[i];
    }
    voice++;
  }
  return pcm;
}

/// The label the engine settles on: the most frequent CONFIRMED chord over the
/// take, or null when it never confirmed one.
({String? label, int confirmedFrames, int frames}) _decode(List<double> pcm) {
  final pipeline = LivePipeline(sampleRate: _sampleRate);
  final histogram = <String, int>{};
  var frames = 0;
  var confirmed = 0;
  const chunk = 1024;
  for (var i = 0; i < pcm.length; i += chunk) {
    final end = math.min(i + chunk, pcm.length);
    for (final frame in pipeline.addChunk(pcm.sublist(i, end))) {
      frames++;
      final label = frame.current?.label;
      if (label == null) continue;
      confirmed++;
      histogram[label] = (histogram[label] ?? 0) + 1;
    }
  }
  if (histogram.isEmpty) {
    return (label: null, confirmedFrames: 0, frames: frames);
  }
  final best = histogram.entries.reduce((a, b) => b.value > a.value ? b : a);
  return (label: best.key, confirmedFrames: confirmed, frames: frames);
}

void main() {
  // The five chords the beginner course actually scores, plus the two majors
  // whose real-audio behaviour is already known — so a failure here can be told
  // apart from "this whole stimulus is unrealistic".
  const chords = ['Em', 'Am', 'D', 'G', 'C', 'E', 'A'];

  test('MEASURE: the shipped chords, named from modelled audio', () {
    final results = <String, String?>{};
    for (final chord in chords) {
      final decoded = _decode(_strumChord(chord));
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
      final decoded = _decode(_strumChord(chord));
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
      final down = _decode(_strumChord(chord)).label;
      final up = _decode(_strumChord(chord, down: false)).label;
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
