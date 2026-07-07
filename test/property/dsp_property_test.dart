// Randomized property gate (anti-reward-hacking — HORIZON pattern).
//
// The deterministic DSP tests are the dev loop's visible harness; this suite
// re-checks the same properties on RANDOMIZED inputs so the code cannot be
// (even accidentally) tuned to the fixed fixtures.
//
// Seed: PROPERTY_SEED env var — CI passes the run id (fresh gate every run);
// locally absent → fixed 42, so the dev-loop suite stays deterministic.
// Thresholds are percentage-based to keep the gate meaningful but not flaky.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/chord_matcher.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';
import 'package:music_theory/features/live/engine/dsp/nnls_chroma.dart';
import 'package:music_theory/features/live/engine/dsp/strum_analyzer.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/tuner/engine/dsp/tuner_analyzer.dart';

import '../support/synth.dart';

const sr = DspConfig.defaultSampleRate;
const _pitchClasses = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
];

double _midiToFreq(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

void main() {
  final seed =
      int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final rng = math.Random(seed);
  // Always visible in logs so any failure is reproducible.
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  test('property: random maj/min triads are recognised (≥90% of 20)', () {
    var correct = 0;
    final failures = <String>[];
    for (var t = 0; t < 20; t++) {
      final rootMidi = 40 + rng.nextInt(13); // E2..E3
      final minor = rng.nextBool();
      // Guitar-realistic voicing: below ~A2 the third sits an octave up (a
      // close third at ~90 Hz is 2 bins from the root — inside one Hann main
      // lobe, physically unresolvable AND unplayed on a real guitar).
      final thirdOffset = (minor ? 3 : 4) + (rootMidi < 45 ? 12 : 0);
      final freqs = [
        _midiToFreq(rootMidi),
        _midiToFreq(rootMidi + thirdOffset),
        _midiToFreq(rootMidi + 7),
      ];
      final expected = _pitchClasses[rootMidi % 12] + (minor ? 'm' : '');
      final signal = chordSignal(
        freqs,
        seconds: 1.0,
        amp: 0.1 + rng.nextDouble() * 0.25,
        decayPerSecond: 1.0 + rng.nextDouble() * 1.5,
      );

      final extractor = NnlsChroma(sampleRate: sr, window: DspConfig.nnlsWindow);
      final matcher = ChordMatcher();
      ChordMatch? match;
      for (final frame
          in frames(signal, DspConfig.nnlsWindow, DspConfig.nnlsHop)) {
        final ch = extractor.process(frame);
        final tonal =
            ch != null && extractor.lastTonalness >= DspConfig.chordMinTonalness;
        match = matcher.process(tonal ? ch : null);
      }
      if (match?.chord.label == expected) {
        correct++;
      } else {
        failures.add('trial=$t expected=$expected got=${match?.chord.label}');
      }
    }
    expect(correct, greaterThanOrEqualTo(18),
        reason: 'seed=$seed failures: ${failures.join('; ')}');
  });

  test('property: random strums — one onset, correct direction (20 trials)',
      () {
    var singleOnset = 0;
    var directionChecked = 0;
    var directionCorrect = 0;
    final failures = <String>[];
    for (var t = 0; t < 20; t++) {
      final lowFirst = rng.nextBool();
      final stagger = 6 + rng.nextDouble() * 8; // 6–14 ms per string
      final signal = strumSignal(
        lowFirst: lowFirst,
        staggerMs: stagger,
        seconds: 0.5 + rng.nextDouble() * 0.4,
      );

      final analyzer = StrumAnalyzer(sampleRate: sr);
      final events = <StrumEvent>[];
      for (final frame
          in frames(signal, DspConfig.onsetWindow, DspConfig.onsetHop)) {
        final e = analyzer.process(frame);
        if (e != null) events.add(e);
      }

      if (events.length == 1) singleOnset++;
      final dir = events.isEmpty ? null : events.first.direction;
      if (dir != null) {
        directionChecked++;
        final expected = lowFirst ? StrumDirection.down : StrumDirection.up;
        if (dir == expected) {
          directionCorrect++;
        } else {
          failures.add(
              'trial=$t lowFirst=$lowFirst stagger=${stagger.toStringAsFixed(1)}ms got=$dir');
        }
      }
    }
    expect(singleOnset, greaterThanOrEqualTo(18),
        reason: 'seed=$seed: a strum must merge into ONE onset');
    expect(directionChecked, greaterThanOrEqualTo(15),
        reason: 'seed=$seed: direction should rarely be ambiguous on synth');
    expect(directionCorrect / math.max(1, directionChecked),
        greaterThanOrEqualTo(0.85),
        reason: 'seed=$seed failures: ${failures.join('; ')}');
  });

  // Voice/noise rejection (round 23): the tuner must lock a STABLE, in-range
  // tone but reject a gliding pitch (the way speech behaves).
  test('property: stable tones lock, gliding pitches do not (20 trials)', () {
    bool tunerLocks(Float64List signal) {
      final a = TunerAnalyzer(sampleRate: sr);
      final hop = a.bufferSize ~/ 2;
      for (var s = 0; s + a.bufferSize <= signal.length; s += hop) {
        if (a
            .process(Float64List.sublistView(signal, s, s + a.bufferSize))
            .hasSignal) {
          return true;
        }
      }
      return false;
    }

    var stableLocked = 0;
    var glideLocked = 0;
    for (var t = 0; t < 20; t++) {
      final midi = 40 + rng.nextInt(24); // E2..D#4, all in guitar range
      final stable = harmonicNote(
        freq: _midiToFreq(midi),
        seconds: 0.7,
        amp: 0.15 + rng.nextDouble() * 0.2,
      );
      if (tunerLocks(stable)) stableLocked++;

      // A continuous glide (voice-like): starts in range, sweeps ~1 octave/s.
      final start = 120 + rng.nextDouble() * 120;
      final rate = 1.0 + rng.nextDouble() * 1.5;
      final n = (0.7 * sr).round();
      final glide = Float64List(n);
      for (var i = 0; i < n; i++) {
        final tt = i / sr;
        final ff = start * math.pow(2, rate * tt).toDouble();
        glide[i] = 0.28 * math.sin(2 * math.pi * ff * tt);
      }
      if (tunerLocks(glide)) glideLocked++;
    }
    expect(stableLocked, greaterThanOrEqualTo(17),
        reason: 'seed=$seed: a held in-range tone must lock');
    expect(glideLocked, lessThanOrEqualTo(2),
        reason: 'seed=$seed: a gliding pitch (speech-like) must be rejected');
  });

  test('property: white noise does not fake a chord (20 trials)', () {
    var chordShown = 0;
    for (var t = 0; t < 20; t++) {
      final ex = NnlsChroma(sampleRate: sr, window: DspConfig.nnlsWindow);
      final matcher = ChordMatcher();
      ChordMatch? m;
      final amp = 0.1 + rng.nextDouble() * 0.3;
      for (var w = 0; w < 8; w++) {
        final frame = Float64List(DspConfig.nnlsWindow);
        for (var i = 0; i < frame.length; i++) {
          frame[i] = (rng.nextDouble() * 2 - 1) * amp;
        }
        final chroma = ex.process(frame);
        final tonal = chroma != null &&
            ex.lastTonalness >= DspConfig.chordMinTonalness;
        m = matcher.process(tonal ? chroma : null);
      }
      if (m != null) chordShown++;
    }
    expect(chordShown, lessThanOrEqualTo(2),
        reason: 'seed=$seed: diffuse noise must not accumulate a chord');
  });
}
