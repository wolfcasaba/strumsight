import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/tuner/engine/dsp/tuner_analyzer.dart';
import 'package:music_theory/features/tuner/engine/dsp/yin_pitch_detector.dart';

import '../../../support/synth.dart';

const sr = 44100;

Float64List sine(double freq, {int n = 4096, double amp = 0.4}) {
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amp * math.sin(2 * math.pi * freq * i / sr);
  }
  return out;
}

void main() {
  final yin = YinPitchDetector(sampleRate: sr);

  test('pure 110 Hz sine detected within 0.5 Hz', () {
    expect(yin.detect(sine(110)), closeTo(110, 0.5));
  });

  test('low E2 with rich harmonics: no octave error', () {
    final note = harmonicNote(freq: 82.41, seconds: 0.1, amp: 0.4);
    expect(yin.detect(note.sublist(0, 4096)), closeTo(82.41, 1.0));
  });

  test('silence / noise floor yields no pitch', () {
    expect(yin.detect(Float64List(4096)), isNull);
  });

  test('noteForFrequency maps 445 Hz to A, ~+19.6 cents sharp', () {
    final r = noteForFrequency(445);
    expect(r.note, 'A');
    expect(r.cents, closeTo(19.6, 1.0));
  });

  test('noteForFrequency maps 15-cent-flat G3 to G, ~-15 cents', () {
    final f = 196.0 * math.pow(2, -15 / 1200);
    final r = noteForFrequency(f.toDouble());
    expect(r.note, 'G');
    expect(r.cents, closeTo(-15, 1.5));
  });

  test('TunerAnalyzer: in-tune A2 string reads A within ±3 cents', () {
    final analyzer = TunerAnalyzer(sampleRate: sr);
    final note = harmonicNote(freq: 110, seconds: 0.4, amp: 0.3);
    final reading = analyzer.process(note.sublist(0, analyzer.bufferSize));
    expect(reading.hasSignal, isTrue);
    expect(reading.note, 'A');
    expect(reading.cents.abs(), lessThan(3));
    expect(reading.inTune, isTrue);
  });

  test('TunerAnalyzer: silence gives the silent reading', () {
    final analyzer = TunerAnalyzer(sampleRate: sr);
    final reading = analyzer.process(Float64List(analyzer.bufferSize));
    expect(reading.hasSignal, isFalse);
  });
}
