import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/model/analyze_result.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/share/screens/strum_reel_screen.dart';
import 'package:music_theory/features/songs/model/song.dart';

/// Round 118 — the r116 devil-advocate's WARNING closed: a shared 3/4 song
/// played its Strum Reel as a 4/4 loop (8 beats for a 6-beat waltz, downbeat
/// punch on beats 0/4 instead of 0/3), because `AnalyzeResult` carried no
/// metre and `Lessons.fromAnalyze` hardcoded 4 beats/bar.
Song _waltz() => Song(
      id: 'w',
      name: 'Waltz',
      chords: const ['C', 'G'],
      pattern: const [
        StrumDirection.down, null, StrumDirection.up, //
        null, StrumDirection.up, null,
      ],
      beatsPerBar: 3,
      bpm: 60,
    );

void main() {
  test('AnalyzeResult JSON round-trips the metre; legacy records → 4/4', () {
    final r = _waltz().toAnalyzeResult();
    expect(r.beatsPerBar, 3);
    expect(AnalyzeResult.fromJson(r.toJson()).beatsPerBar, 3);

    final legacy = r.toJson()..remove('bpb');
    expect(AnalyzeResult.fromJson(legacy).beatsPerBar, 4);
  });

  test('fromAnalyze keeps a shared waltz in 3/4 — 2 bars = 6 beats, not 8',
      () {
    final lesson =
        Lessons.fromAnalyze(_waltz().toAnalyzeResult(), name: 'reel');
    expect(lesson.beatsPerBar, 3);
    expect(lesson.totalBeats, 6.0,
        reason: 'a 2-bar waltz must not gain two empty trailing beats');
  });

  test('the reel downbeat punch kicks on beat 3 in 3/4, not beat 4', () {
    final kickAtThree = StrumReelScreen.punchScale(3.0, beatsPerBar: 3);
    expect(kickAtThree, closeTo(1.05, 1e-9),
        reason: 'beat 3 IS the second bar\'s downbeat in a waltz');
    // In 4/4 the same playhead position is mid-bar — long past the kick.
    expect(StrumReelScreen.punchScale(3.0), lessThan(1.001));
    // The default stays byte-identical to the old 4/4 behaviour.
    expect(StrumReelScreen.punchScale(4.0),
        closeTo(StrumReelScreen.punchScale(0), 1e-9));
  });
}
