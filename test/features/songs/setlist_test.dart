import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/songs/model/setlist.dart';
import 'package:music_theory/features/songs/model/song.dart';

void main() {
  const d = StrumDirection.down;
  const downbeats = <StrumDirection?>[d, null, d, null, d, null, d, null];

  const songA = Song(
      id: 'a', name: 'A', chords: ['C', 'G'], pattern: downbeats, bpm: 100);
  const songB =
      Song(id: 'b', name: 'B', chords: ['Am'], pattern: downbeats, bpm: 120);

  test('resolve preserves order and drops missing ids', () {
    const set = Setlist(id: 's', name: 'Set', songIds: ['b', 'ghost', 'a']);
    final resolved = set.resolve([songA, songB]);
    expect(resolved.map((s) => s.id), ['b', 'a']); // ghost dropped, order kept
  });

  test('combine concatenates events with a running beat offset', () {
    const set = Setlist(id: 's', name: 'My Set', songIds: ['a', 'b']);
    final lesson = set.combine([songA, songB]);
    // A = 2 bars, B = 1 bar → 3 bars × 4 struck slots = 12 events, 12 beats.
    expect(lesson.events.length, 12);
    expect(lesson.totalBeats, 12);
    // Chords span both songs in order.
    expect(lesson.chordSequence, ['C', 'G', 'Am']);
    // Single tempo = the first song's.
    expect(lesson.bpm, 100);
    // B's first event is offset past A's 8 beats.
    expect(lesson.events[8].beat, greaterThanOrEqualTo(8));
    expect(lesson.id, 'setlist_s');
  });

  test('combine of an empty set is a harmless empty lesson', () {
    const set = Setlist(id: 's', name: 'Empty', songIds: []);
    final lesson = set.combine([]);
    expect(lesson.events, isEmpty);
    expect(lesson.totalBeats, 0);
  });

  test('JSON round-trip', () {
    const set = Setlist(id: 's', name: 'Set', songIds: ['a', 'b', 'a']);
    expect(Setlist.fromJson(set.toJson()), set);
  });
}
