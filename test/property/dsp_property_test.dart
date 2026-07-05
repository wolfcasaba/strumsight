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

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/chord_matcher.dart';
import 'package:music_theory/features/live/engine/dsp/chroma_extractor.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';
import 'package:music_theory/features/live/engine/dsp/strum_analyzer.dart';
import 'package:music_theory/features/live/model/strum.dart';

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

      final extractor = ChromaExtractor(sampleRate: sr);
      final matcher = ChordMatcher();
      ChordMatch? match;
      for (final frame
          in frames(signal, DspConfig.chromaWindow, DspConfig.chromaHop)) {
        match = matcher.process(extractor.process(frame));
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
}
