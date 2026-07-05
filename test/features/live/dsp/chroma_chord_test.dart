import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/chord_matcher.dart';
import 'package:music_theory/features/live/engine/dsp/chroma_extractor.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';

import '../../../support/synth.dart';

const sr = DspConfig.defaultSampleRate;
const win = DspConfig.chromaWindow;
const hop = DspConfig.chromaHop;

/// Run signal through extractor+matcher, return the last stable match.
ChordMatch? lastMatch(Float64List signal) {
  final extractor = ChromaExtractor(sampleRate: sr);
  final matcher = ChordMatcher();
  ChordMatch? match;
  for (final frame in frames(signal, win, hop)) {
    match = matcher.process(extractor.process(frame));
  }
  return match;
}

void main() {
  test('C major triad with harmonics is recognised as C', () {
    final match = lastMatch(chordSignal(cMajorFreqs));
    expect(match, isNotNull);
    expect(match!.chord.label, 'C');
    expect(match.confidence, greaterThan(0.5));
  });

  test('A minor triad is recognised as Am', () {
    final match = lastMatch(chordSignal(aMinorFreqs));
    expect(match!.chord.label, 'Am');
  });

  test('G major triad is recognised as G', () {
    final match = lastMatch(chordSignal(gMajorFreqs));
    expect(match!.chord.label, 'G');
  });

  test('silence yields no chord', () {
    final match = lastMatch(Float64List((sr * 0.5).round()));
    expect(match, isNull);
  });

  test('chroma of a C triad peaks on C, E, G pitch classes', () {
    final extractor = ChromaExtractor(sampleRate: sr);
    List<double>? chroma;
    for (final frame in frames(chordSignal(cMajorFreqs), win, hop)) {
      chroma = extractor.process(frame) ?? chroma;
    }
    expect(chroma, isNotNull);
    final ranked = List.generate(12, (i) => i)
      ..sort((a, b) => chroma![b].compareTo(chroma[a]));
    expect(ranked.take(3).toSet(), {0, 4, 7}); // C E G
  });

  test('hysteresis: chord only switches after consecutive frames', () {
    final extractor = ChromaExtractor(sampleRate: sr);
    final matcher = ChordMatcher();

    // Stabilise on C…
    for (final frame in frames(chordSignal(cMajorFreqs), win, hop)) {
      matcher.process(extractor.process(frame));
    }
    // …then feed G; the FIRST frame must not flip the report unless decisive.
    final gFrames = frames(chordSignal(gMajorFreqs), win, hop).toList();
    final first = matcher.process(extractor.process(gFrames.first));
    final immediateFlip = first!.chord.label == 'G' &&
        first.confidence >= DspConfig.chordInstantSwitchConfidence;
    if (!immediateFlip) {
      expect(first.chord.label, 'C', reason: 'no flicker on one weak frame');
    }
    // After the full G signal it must have switched.
    ChordMatch? match;
    for (final frame in gFrames.skip(1)) {
      match = matcher.process(extractor.process(frame));
    }
    expect(match!.chord.label, 'G');
  });

  test('extractor reports RMS and gates noise-floor frames', () {
    final extractor = ChromaExtractor(sampleRate: sr);
    final quiet = Float64List(win); // all zeros
    expect(extractor.process(quiet), isNull);
    expect(extractor.lastRms, lessThan(DspConfig.silenceRms));
  });
}
