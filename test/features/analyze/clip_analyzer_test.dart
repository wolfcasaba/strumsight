import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/engine/clip_analyzer.dart';
import 'package:music_theory/features/analyze/model/analyze_result.dart';
import 'package:music_theory/features/live/model/strum.dart';

import '../../support/synth.dart';

void main() {
  const analyzer = ClipAnalyzer();

  test('empty / invalid input yields the empty result', () {
    expect(analyzer.analyze([], 44100).durationSec, 0);
    expect(analyzer.analyze([0.1, 0.2], 0).durationSec, 0);
  });

  test('a SILENT clip is honest — real duration, but no fabricated content',
      () {
    // The degenerate user path: tap Record, sit in silence, tap Stop. The
    // analyzer must report the true length yet invent NO chords or strums
    // (the integration-level twin of the "white noise ≠ chord" property).
    final silence = List<double>.filled(44100 * 2, 0.0); // 2 s of digital 0
    final result = analyzer.analyze(silence, 44100);
    expect(result.durationSec, closeTo(2.0, 0.001),
        reason: 'the clip length is real even when its content is empty');
    expect(result.chords, isEmpty, reason: 'silence is not a chord');
    expect(result.strums, isEmpty, reason: 'silence has no strums');
    expect(result.bpm, 0);
  });

  test('a clip shorter than one analysis window does not crash', () {
    // Stop tapped almost instantly → a handful of samples, fewer than the
    // NNLS window. Must return cleanly, not throw a range error.
    final tiny = chordSignal(cMajorFreqs, seconds: 0.005).toList(); // ~220 smp
    final result = analyzer.analyze(tiny, 44100);
    expect(result.chords, isEmpty);
    expect(result.durationSec, greaterThan(0));
  });

  test('analyzes a strum pattern into an ordered strum timeline', () {
    final pcm = strumPattern(
      lowFirstPerStrum: [true, false, true, false], // down, up, down, up
    ).toList();

    final result = analyzer.analyze(pcm, 44100);

    expect(result.strums.length, greaterThanOrEqualTo(3));
    expect(result.downCount, greaterThan(0));
    expect(result.upCount, greaterThan(0));
    // Strum marks are in chronological order and inside the clip.
    for (var i = 1; i < result.strums.length; i++) {
      expect(result.strums[i].timeSec,
          greaterThanOrEqualTo(result.strums[i - 1].timeSec));
    }
    expect(result.strums.last.timeSec, lessThanOrEqualTo(result.durationSec));
  });

  test('derives a plausible tempo from a 0.5 s strum spacing (~120 BPM)', () {
    final pcm = strumPattern(
      lowFirstPerStrum: [true, false, true, false, true],
      gapSeconds: 0.5,
    ).toList();
    final result = analyzer.analyze(pcm, 44100);
    expect(result.bpm, closeTo(120, 25));
  });

  test('analyzes a two-chord clip into a chord timeline', () {
    final c = chordSignal(cMajorFreqs, seconds: 1.5).toList();
    final g = chordSignal(gMajorFreqs, seconds: 1.5).toList();
    final result = analyzer.analyze([...c, ...g], 44100);

    expect(result.chords, isNotEmpty);
    expect(result.durationSec, closeTo(3.0, 0.3));
    // Chord segments are contiguous and ordered.
    for (var i = 1; i < result.chords.length; i++) {
      expect(result.chords[i].startSec,
          greaterThanOrEqualTo(result.chords[i - 1].startSec));
    }
  });

  test('AnalyzeResult survives a JSON round-trip (Library persistence)', () {
    const r = AnalyzeResult(
      durationSec: 2.5,
      bpm: 120,
      chords: [TimelineChord(label: 'C', startSec: 0, endSec: 1.2)],
      strums: [
        TimelineStrum(
            direction: StrumDirection.down, timeSec: 0.5, confidence: 0.8),
        TimelineStrum(
            direction: StrumDirection.up, timeSec: 1.0, confidence: 0.4),
      ],
    );

    final back =
        AnalyzeResult.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);

    expect(back.durationSec, 2.5);
    expect(back.bpm, 120);
    expect(back.chords.single.label, 'C');
    expect(back.strums.first.direction, StrumDirection.down);
    expect(back.downCount, 1);
    expect(back.upCount, 1);
    expect(back.chordSummary, 'C');
  });
}
