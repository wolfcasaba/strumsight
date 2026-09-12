// Physically modelled guitar audio, driven by the app's OWN chord data.
//
// Separate from `synth.dart`, which synthesises signals from first principles and
// depends on nothing: this file deliberately reaches into `ChordShapes` and
// `GuitarStrings`, so the chord under test is the chord the app would show a
// learner, fret for fret, including the muted strings.
//
// It exists as one shared definition because the same Karplus-Strong model had
// already been written twice (the modelled-chord recognition measurement and the
// calibration round trip), and a third copy is how two measurements quietly start
// measuring slightly different stimuli — the same failure `docs/LESSONS.md` L269
// records for matching helpers.
//
// ## What this is NOT
//
// Not a real guitar. There is no body resonance, no pick noise, no fret buzz, no
// room, and the strings are perfectly in tune with each other. A measurement built
// on it can fail loudly and usefully; it cannot close a real-audio gap.
import 'dart:math' as math;

import 'package:strumsight/core/music/guitar_strings.dart';
import 'package:strumsight/features/chords/public.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_decision.dart';

const int modelledSampleRate = 44100;

/// One plucked string, physically modelled (Karplus-Strong).
///
/// A burst of noise is pushed into a delay line of length `sampleRate / freq` and
/// averaged with its neighbour on each pass. The averaging is a one-pole low-pass,
/// so each trip round the loop loses more high frequency than low — which is why a
/// real string's tone darkens as it decays, and why this is a far better test of a
/// chroma front-end than steady sine partials.
List<double> pluckedString({
  required double freqHz,
  required double seconds,
  required int seed,
  double damping = 0.996,
  double amplitude = 0.25,
}) {
  final length = (seconds * modelledSampleRate).round();
  final delay = math.max(2, (modelledSampleRate / freqHz).round());
  final random = math.Random(seed);
  final buffer = List<double>.generate(
    delay,
    (_) => random.nextDouble() * 2 - 1,
  );
  // Soften the excitation: a real pick does not inject white noise across the
  // whole spectrum, and an unfiltered burst makes every string sound identical at
  // the attack.
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
  // Fade the tail so the take does not END on a step — a step is a real broadband
  // transient and the onset detector is right to hear it
  // (`onset_double_trigger_diagnosis_test.dart`).
  final fade = (0.03 * modelledSampleRate).round();
  for (var i = 0; i < fade && i < length; i++) {
    out[length - 1 - i] *= i / fade;
  }
  return out;
}

/// Adds a strummed chord to [pcm], starting at [atSec], from the app's own
/// fingering for [label].
///
/// `-1` frets are NOT played, exactly as the diagram says — so an Am really does
/// leave the low E silent, which is part of what makes it an Am rather than a
/// muddier chord. Returns false when there is no shipped fingering.
bool addStrummedChord(
  List<double> pcm,
  String label, {
  required double atSec,
  required double ringSeconds,
  double spreadSec = 0.022,
  bool down = true,
  int seedBase = 1000,
}) {
  final shape = ChordShapes.forLabel(label);
  if (shape == null) return false;
  final strings = GuitarStrings.standard;
  // Fingerings run low-E first; a downstroke meets them in that order.
  final order = [for (var i = 0; i < 6; i++) i];
  final meetOrder = down ? order : order.reversed.toList();

  var voice = 0;
  for (var position = 0; position < meetOrder.length; position++) {
    final stringIndex = meetOrder[position];
    final fret = shape.frets[stringIndex];
    if (fret < 0) continue; // muted: the pick crosses it, it does not sound
    final midi = strings[stringIndex].midi + fret;
    final freq = 440 * math.pow(2, (midi - 69) / 12).toDouble();
    final start = ((atSec + position * spreadSec) * modelledSampleRate).round();
    final tone = pluckedString(
      freqHz: freq,
      seconds: math.max(0.05, ringSeconds - position * spreadSec),
      seed: seedBase + voice * 17,
      // The wound low strings ring longer than the plain high ones.
      damping: midi < 55 ? 0.9975 : 0.9955,
    );
    for (var i = 0; i < tone.length; i++) {
      final at = start + i;
      if (at >= 0 && at < pcm.length) pcm[at] += tone[i];
    }
    voice++;
  }
  return true;
}

/// One strummed chord on its own, as a take of [seconds].
List<double> strumChord(
  String label, {
  double seconds = 3.0,
  double spreadSec = 0.022,
  bool down = true,
}) {
  final pcm = List<double>.filled((seconds * modelledSampleRate).round(), 0);
  addStrummedChord(
    pcm,
    label,
    atSec: 0,
    ringSeconds: seconds,
    spreadSec: spreadSec,
    down: down,
  );
  return pcm;
}

/// A sequence of chords, each struck at an EXACTLY known instant.
///
/// Every chord is struck once at `index * secondsEach` and left to ring for that
/// long. The previous chord is not cut off, because a real player's previous shape
/// does not stop dead when the new one is struck — the new strum simply dominates.
/// That overlap is the whole point when measuring how long a decoder takes to
/// follow a change: cutting the old chord would make the change easier to hear
/// than it is in a room.
List<double> strumSequence(
  List<String> labels, {
  double secondsEach = 2.0,
  double tailSeconds = 1.0,
  double spreadSec = 0.022,
}) {
  final total = labels.length * secondsEach + tailSeconds;
  final pcm = List<double>.filled((total * modelledSampleRate).round(), 0);
  for (var i = 0; i < labels.length; i++) {
    addStrummedChord(
      pcm,
      labels[i],
      atSec: i * secondsEach,
      ringSeconds: secondsEach + tailSeconds,
      spreadSec: spreadSec,
      seedBase: 1000 + i * 211,
    );
  }
  return pcm;
}

/// Onsets the ENGINE reports for [pcm], in seconds on its own clock.
///
/// Read from `strumSeq` increments and `latestStrumTime` — the MEASURED true onset
/// the pipeline publishes, not the moment a frame happened to arrive.
List<double> strumOnsets(List<double> pcm, {int chunk = 1024}) {
  final pipeline = LivePipeline(sampleRate: modelledSampleRate);
  final out = <double>[];
  var lastSeq = 0;
  for (var i = 0; i < pcm.length; i += chunk) {
    final end = math.min(i + chunk, pcm.length);
    for (final frame in pipeline.addChunk(pcm.sublist(i, end))) {
      if (frame.strumSeq > lastSeq) {
        lastSeq = frame.strumSeq;
        out.add(frame.latestStrumTime);
      }
    }
  }
  return out;
}

/// How many strums the engine reports for [pcm].
int strumCount(List<double> pcm) => strumOnsets(pcm).length;

/// One published frame of the real pipeline, with the time it was published.
typedef ChordFrame = ({double atSec, String? label, bool isConfirmed});

/// Every frame the REAL pipeline publishes for [pcm], in order.
///
/// `isConfirmed` reads `chordDecision`, not merely the presence of a label: the
/// pipeline names a candidate well before it confirms one, and the curriculum
/// scores only confirmed decisions.
List<ChordFrame> chordFrames(List<double> pcm, {int chunk = 1024}) {
  final pipeline = LivePipeline(sampleRate: modelledSampleRate);
  final out = <ChordFrame>[];
  for (var i = 0; i < pcm.length; i += chunk) {
    final end = math.min(i + chunk, pcm.length);
    for (final frame in pipeline.addChunk(pcm.sublist(i, end))) {
      out.add((
        atSec: frame.engineTimeSec,
        label: frame.current?.label,
        isConfirmed: frame.chordDecision == RecognitionDecision.confirmed,
      ));
    }
  }
  return out;
}
