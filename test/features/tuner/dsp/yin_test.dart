import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/tuner/engine/dsp/tuner_analyzer.dart';
import 'package:music_theory/features/tuner/engine/dsp/yin_pitch_detector.dart';
import 'package:music_theory/features/tuner/model/tuner_reading.dart';

import '../../../support/synth.dart';

const sr = 44100;

Float64List sine(double freq, {int n = 4096, double amp = 0.4}) {
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amp * math.sin(2 * math.pi * freq * i / sr);
  }
  return out;
}

/// Feed a sustained signal through the analyzer frame-by-frame (like the real
/// engine) and return the last locked reading. The stability gate needs several
/// consistent frames before it shows a note.
TunerReading readSustained(TunerAnalyzer a, Float64List signal) {
  var last = TunerReading.silent;
  final hop = a.bufferSize ~/ 2;
  for (var s = 0; s + a.bufferSize <= signal.length; s += hop) {
    final r = a.process(Float64List.sublistView(signal, s, s + a.bufferSize));
    if (r.hasSignal) last = r;
  }
  return last;
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
    final note = harmonicNote(freq: 110, seconds: 0.6, amp: 0.3);
    final reading = readSustained(analyzer, note);
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

  test('TunerAnalyzer: a single clear frame does NOT lock (needs stability)',
      () {
    final analyzer = TunerAnalyzer(sampleRate: sr);
    final note = harmonicNote(freq: 110, seconds: 0.4, amp: 0.3);
    // One frame is not enough evidence — a real note is held for many frames,
    // a transient/glide is not.
    final reading = analyzer.process(note.sublist(0, analyzer.bufferSize));
    expect(reading.hasSignal, isFalse);
  });

  test('TunerAnalyzer: a gliding pitch (voice-like) never locks', () {
    final analyzer = TunerAnalyzer(sampleRate: sr);
    // A continuous ~1 octave/sec sweep 150→300 Hz — well within range and
    // periodic, but never stable, so the stability gate keeps it silent.
    final n = (0.7 * sr).round();
    final sweep = Float64List(n);
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      final f = 150 * math.pow(2, t).toDouble(); // exponential glide
      sweep[i] = 0.3 * math.sin(2 * math.pi * f * t);
    }
    expect(readSustained(analyzer, sweep).hasSignal, isFalse);
  });

  test('noteForFrequency respects a custom A4 reference (432 Hz)', () {
    // 432 Hz is a perfectly in-tune A when A4 = 432…
    final r432 = noteForFrequency(432, a4: 432);
    expect(r432.note, 'A');
    expect(r432.cents.abs(), lessThan(1));
    // …but ~-31.8 cents flat against the 440 standard.
    final r440 = noteForFrequency(432);
    expect(r440.cents, closeTo(-31.8, 1.5));
  });

  test('TunerAnalyzer applies its A4 to the note/cents mapping', () {
    final a440 = TunerAnalyzer(sampleRate: sr);
    final a432 = TunerAnalyzer(sampleRate: sr, a4: 432);
    final tone = harmonicNote(freq: 432, seconds: 0.6, amp: 0.3);

    final r432 = readSustained(a432, tone);
    final r440 = readSustained(a440, tone);

    expect(r432.note, 'A');
    expect(r432.inTune, isTrue); // in tune at A4 = 432
    expect(r440.inTune, isFalse); // but flat at A4 = 440
  });
}
