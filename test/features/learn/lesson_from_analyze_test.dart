import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/engine/clip_analyzer.dart';
import 'package:music_theory/features/analyze/model/analyze_result.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/live/model/strum.dart';

import '../../support/synth.dart';

AnalyzeResult _result() => AnalyzeResult(
      durationSec: 4,
      bpm: 120, // 0.5 s / beat
      chords: const [
        TimelineChord(label: 'C', startSec: 0, endSec: 2),
        TimelineChord(label: 'G', startSec: 2, endSec: 4),
      ],
      strums: [
        TimelineStrum(direction: StrumDirection.down, timeSec: 0.0, confidence: 1),
        TimelineStrum(direction: StrumDirection.up, timeSec: 0.5, confidence: 1),
        TimelineStrum(direction: StrumDirection.down, timeSec: 2.0, confidence: 1),
      ],
    );

void main() {
  test('imports strums as beat-timed events on the sounding chord', () {
    final lesson = Lessons.fromAnalyze(_result(), name: 'My Riff');
    expect(lesson.name, 'My Riff');
    expect(lesson.bpm, 120);
    expect(lesson.events.length, 3);

    // First strum anchors beat 0; 120 BPM → 0.5 s/beat.
    expect(lesson.events[0].beat, 0);
    expect(lesson.events[0].chord, 'C');
    expect(lesson.events[0].direction, StrumDirection.down);

    expect(lesson.events[1].beat, 1); // 0.5 s later
    expect(lesson.events[1].direction, StrumDirection.up);

    expect(lesson.events[2].beat, 4); // 2.0 s later
    expect(lesson.events[2].chord, 'G'); // chord changed by then

    // Length covers the bar containing the last event.
    expect(lesson.totalBeats, greaterThan(lesson.events.last.beat));
    expect(lesson.chordSequence, ['C', 'G']);
  });

  test('falls back to a sane tempo and a one-bar length when sparse', () {
    final r = AnalyzeResult(
      durationSec: 1,
      bpm: 0, // undetected
      chords: const [],
      strums: [
        TimelineStrum(direction: StrumDirection.down, timeSec: 0.3, confidence: 1),
      ],
    );
    final lesson = Lessons.fromAnalyze(r, name: 'x');
    expect(lesson.bpm, greaterThan(0));
    expect(lesson.events.single.beat, 0); // first strum re-anchored to 0
    expect(lesson.events.single.chord, ''); // no chord timeline
    expect(lesson.totalBeats, 4);
  });

  test('an empty result yields a minimal, safe lesson', () {
    final lesson = Lessons.fromAnalyze(AnalyzeResult.empty, name: 'empty');
    expect(lesson.events, isEmpty);
    expect(lesson.totalBeats, 4);
  });

  test('END-TO-END: real audio → analyzer → beats land on the grid (r148)',
      () {
    // The unit tests above use hand-built exact times; this locks the WHOLE
    // chain on synthesized audio. Before the r145 timestamp fix the analyzer
    // fed times 85–165 ms late with ±40 ms jitter — up to ~0.3 beat of error
    // at 120 BPM, silently mangling imported lessons.
    final signal = strumPattern(
      lowFirstPerStrum: List.filled(5, true),
      gapSeconds: 0.5, // 120 BPM quarters
    );
    final result = const ClipAnalyzer().analyze(signal.toList(), 44100);
    final lesson = Lessons.fromAnalyze(result, name: 'e2e');
    expect(lesson.events, hasLength(5));
    for (var i = 0; i < 5; i++) {
      expect((lesson.events[i].beat - i).abs(), lessThan(0.12),
          reason: 'event $i at beat ${lesson.events[i].beat}');
    }
  });
}
