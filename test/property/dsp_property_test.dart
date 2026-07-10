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
import 'package:music_theory/features/live/engine/dsp/chord_dictionary.dart';
import 'package:music_theory/features/live/engine/dsp/chord_matcher.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';
import 'package:music_theory/features/live/engine/dsp/nnls_chroma.dart';
import 'package:music_theory/features/live/engine/dsp/strum_analyzer.dart';
import 'package:music_theory/features/live/engine/dsp/viterbi_chord_decoder.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/tuner/engine/dsp/tuner_analyzer.dart';

import '../support/synth.dart';

const sr = DspConfig.defaultSampleRate;
const _pitchClasses = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
];

double _midiToFreq(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

/// Run a signal through the full chunk-012 chord chain (NNLS bass/treble →
/// dictionary → online Viterbi) and return the last stable label, or null.
String? _decodeChord(Float64List signal) {
  final nc = NnlsChroma(sampleRate: sr, window: DspConfig.nnlsWindow);
  final decoder = ViterbiChordDecoder(
    selfBonus: DspConfig.chordSelfTransitionBonus,
    dictionary: ChordDictionary(),
  );
  ChordMatch? m;
  for (final frame in frames(signal, DspConfig.nnlsWindow, DspConfig.nnlsHop)) {
    final ch = nc.process(frame);
    final tonal =
        ch != null && nc.lastTonalness >= DspConfig.chordMinTonalness;
    m = tonal
        ? decoder.process(nc.lastBassChroma, nc.lastTrebleChroma)
        : decoder.process(Float64List(12), Float64List(12));
  }
  return m?.chord.label;
}

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

  // chunk 012 — the dictionary+Viterbi engine must nail plain triads (root AND
  // quality) WITHOUT inventing a phantom 7th/sus extension.
  test('property: dictionary engine recognises random triads, no phantom '
      'extension (≥85% of 20)', () {
    var correct = 0;
    final failures = <String>[];
    for (var t = 0; t < 20; t++) {
      final rootMidi = 40 + rng.nextInt(13); // E2..E3
      final minor = rng.nextBool();
      // Same guitar-realistic voicing as the template property above.
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
      final got = _decodeChord(signal);
      if (got == expected) {
        correct++;
      } else {
        failures.add('trial=$t expected=$expected got=$got');
      }
    }
    expect(correct, greaterThanOrEqualTo(17),
        reason: 'seed=$seed failures: ${failures.join('; ')}');
  });

  // chunk 012 — the headline round-26 fix: a low-voiced dominant 7 (7th just
  // above the fifth, as fingered in an open E7/A7/B7 shape) is heard as a 7
  // chord, not collapsed to the bare triad. Roots are drawn from the guitar's
  // real low-root band E2..B2, where the played m7 dominates the root's faint
  // 7th harmonic. (For roots at/above C3 the m7 coincides with the root's own
  // 7th harmonic and NNLS suppresses it — chunk 012's documented honest limit,
  // an ML-era goal, deliberately outside this gate.)
  test('property: low-voiced dominant 7ths (E2..B2) read as 7 chords (15)', () {
    var rootCorrect = 0;
    var seventhExact = 0;
    final failures = <String>[];
    for (var t = 0; t < 15; t++) {
      final rootMidi = 40 + rng.nextInt(8); // E2..B2 — the robust band
      final root = _pitchClasses[rootMidi % 12];
      final freqs = [
        _midiToFreq(rootMidi), // root
        _midiToFreq(rootMidi + 4 + (rootMidi < 45 ? 12 : 0)), // major 3rd
        _midiToFreq(rootMidi + 7), // 5th
        _midiToFreq(rootMidi + 10), // minor 7th, just above the 5th
      ];
      final signal = chordSignal(
        freqs,
        seconds: 1.2,
        amp: 0.1 + rng.nextDouble() * 0.2,
        decayPerSecond: 1.0 + rng.nextDouble() * 1.2,
      );
      final got = _decodeChord(signal) ?? '';
      final gotRoot = got.isEmpty
          ? ''
          : got.substring(0, got.length > 1 && got[1] == '#' ? 2 : 1);
      if (gotRoot == root) rootCorrect++;
      if (got == '${root}7') {
        seventhExact++;
      } else {
        failures.add('trial=$t expected=${root}7 got=$got');
      }
    }
    expect(rootCorrect, greaterThanOrEqualTo(14),
        reason: 'seed=$seed: the root must be right; ${failures.join('; ')}');
    expect(seventhExact, greaterThanOrEqualTo(12),
        reason: 'seed=$seed: low-voiced dom7s should read as 7; '
            '${failures.join('; ')}');
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

  // Round 59 — direction must survive RING-OUT overlap at realistic strumming
  // tempos (the moat's headline case). Absolute sub-band cues collapse when the
  // previous strum is still sounding; onset-relative baseline subtraction
  // isolates each attack. Tempos capped at the hand-strum ceiling (≤160 BPM
  // 16ths); 200 BPM 16ths remains an honest low-confidence limit (chunk 006).
  test('property: overlapping strums keep direction at realistic tempo (20)',
      () {
    var checked = 0;
    var correct = 0;
    final failures = <String>[];
    for (var t = 0; t < 20; t++) {
      final bpm = 90 + rng.nextInt(71); // 90–160 BPM
      final gap = 60.0 / bpm / 4; // 16th-note spacing, seconds
      final dirs = [for (var i = 0; i < 6; i++) rng.nextBool()];
      final signal = overlappingStrums(
        lowFirstPerStrum: dirs,
        gapSeconds: gap,
        ringSeconds: 0.4 + rng.nextDouble() * 0.3,
        staggerMs: 6 + rng.nextDouble() * 6,
      );
      final analyzer = StrumAnalyzer(sampleRate: sr);
      final events = <StrumEvent>[];
      for (final frame
          in frames(signal, DspConfig.onsetWindow, DspConfig.onsetHop)) {
        final e = analyzer.process(frame);
        if (e != null) events.add(e);
      }
      // Match each detected event to the nearest expected strum by time — robust
      // to a missed/extra onset (no brittle index alignment).
      for (final e in events) {
        if (e.direction == null) continue;
        var bestI = 0;
        var bestD = double.infinity;
        for (var i = 0; i < dirs.length; i++) {
          final et = 0.1 + i * gap; // lead 0.1 s + i·gap
          final d = (e.timeSec - et).abs();
          if (d < bestD) {
            bestD = d;
            bestI = i;
          }
        }
        checked++;
        final want = dirs[bestI] ? StrumDirection.down : StrumDirection.up;
        if (e.direction == want) {
          correct++;
        } else {
          failures.add('t=$t bpm=$bpm i=$bestI want=${dirs[bestI]} got=${e.direction}');
        }
      }
    }
    expect(checked, greaterThanOrEqualTo(80),
        reason: 'seed=$seed: most overlapping strums should be detected');
    // Floor set below the measured spread (≈0.77–0.86 across seeds) so the
    // gate is non-flaky, yet well above the pre-round-59 behaviour (absolute
    // cues collapsed to ~0.6 under ring-out). Round 60 (better band design)
    // targets ≥0.85. Note the trained-CRNN up-strum ceiling is ~0.79.
    expect(correct / math.max(1, checked), greaterThanOrEqualTo(0.72),
        reason: 'seed=$seed: ring-out must not corrupt direction; '
            '${failures.join('; ')}');
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
