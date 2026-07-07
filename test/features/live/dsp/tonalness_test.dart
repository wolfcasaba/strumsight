import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/chroma_extractor.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';
import 'package:music_theory/features/live/engine/dsp/live_pipeline.dart';

import '../../../support/synth.dart';

void main() {
  test('a clean triad is tonal, white noise is diffuse', () {
    final chordEx = ChromaExtractor(sampleRate: 44100);
    final chord = chordSignal(cMajorFreqs, seconds: 1.0);
    for (final f in frames(chord, chordEx.window, chordEx.window)) {
      chordEx.process(f);
    }
    expect(chordEx.lastTonalness,
        greaterThan(DspConfig.chordMinTonalness));

    // Loud white noise passes the level gate but must read as diffuse.
    final noiseEx = ChromaExtractor(sampleRate: 44100);
    final rnd = math.Random(7);
    final noise = Float64List(noiseEx.window * 4);
    for (var i = 0; i < noise.length; i++) {
      noise[i] = (rnd.nextDouble() * 2 - 1) * 0.3;
    }
    double? lastTonal;
    for (final f in frames(noise, noiseEx.window, noiseEx.window)) {
      if (noiseEx.process(f) != null) lastTonal = noiseEx.lastTonalness;
    }
    expect(lastTonal, isNotNull); // noise did pass the silence gate…
    expect(lastTonal, lessThan(DspConfig.chordMinTonalness)); // …but is diffuse
  });

  test('LivePipeline reports a chord for a triad but NOT for white noise', () {
    // Triad → a chord appears.
    final p1 = LivePipeline(sampleRate: 44100);
    final chord = chordSignal(cMajorFreqs, seconds: 1.5).toList();
    String? chordLabel;
    for (var i = 0; i < chord.length; i += 2048) {
      final end = math.min(i + 2048, chord.length);
      for (final fr in p1.addChunk(chord.sublist(i, end))) {
        if (fr.current != null) chordLabel = fr.current!.label;
      }
    }
    expect(chordLabel, isNotNull);

    // White noise → the tonalness gate keeps the chord null.
    final p2 = LivePipeline(sampleRate: 44100);
    final rnd = math.Random(11);
    final noise = [
      for (var i = 0; i < 44100 * 2; i++) (rnd.nextDouble() * 2 - 1) * 0.3,
    ];
    var sawChord = false;
    for (var i = 0; i < noise.length; i += 2048) {
      final end = math.min(i + 2048, noise.length);
      for (final fr in p2.addChunk(noise.sublist(i, end))) {
        if (fr.current != null) sawChord = true;
      }
    }
    expect(sawChord, isFalse);
  });
}
