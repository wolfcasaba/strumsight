import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/songs/model/song.dart';

void main() {
  const d = StrumDirection.down;
  const u = StrumDirection.up;

  const sample = Song(
    id: 'abc',
    name: 'My Riff',
    chords: ['G', 'C', 'D'],
    pattern: [d, null, d, u, null, u, d, null],
    bpm: 96,
  );

  test('JSON round-trip preserves everything, rests included', () {
    final back = Song.fromJson(sample.toJson());
    expect(back, sample);
    expect(back.pattern[1], isNull); // rest survives
    expect(back.pattern[0], d);
    expect(back.pattern[3], u);
  });

  test('toLesson yields a playable lesson with the same chords + tempo', () {
    final lesson = sample.toLesson();
    expect(lesson.bpm, 96);
    expect(lesson.name, 'My Riff');
    expect(lesson.chordSequence, ['G', 'C', 'D']);
    // pattern [d,-,d,u,-,u,d,-] = 5 strokes/bar × 3 bars = 15 events.
    expect(lesson.events.length, 15);
    expect(lesson.id, 'song_abc');
  });

  test('toAnalyzeResult mirrors the chords, tempo and ↓/↑ counts for sharing',
      () {
    const song = Song(
      id: 'x',
      name: 'Riff',
      chords: ['C', 'G'],
      pattern: [d, null, d, u, null, u, d, null], // 3 down + 2 up per bar
      bpm: 120,
    );
    final r = song.toAnalyzeResult();
    // spb = 0.5; 2 bars × 4 beats × 0.5 = 4.0s.
    expect(r.durationSec, closeTo(4.0, 1e-9));
    expect(r.bpm, 120);
    expect(r.chordSummary, 'C · G');
    // 5 strokes/bar × 2 bars: 6 down, 4 up.
    expect(r.downCount, 6);
    expect(r.upCount, 4);
    // First stroke lands at beat 0 → time 0.
    expect(r.strums.first.timeSec, 0);
  });

  test('copyWith keeps the id but swaps fields', () {
    final edited = sample.copyWith(name: 'Renamed', bpm: 120);
    expect(edited.id, 'abc');
    expect(edited.name, 'Renamed');
    expect(edited.bpm, 120);
    expect(edited.chords, sample.chords);
  });
}
