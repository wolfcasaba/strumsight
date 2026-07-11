import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/model/lesson.dart';

/// Round 110 — three new lessons, one per tier, including the app's first
/// 3/4 lesson ("Waltz Time"): the beatsPerBar path finally gets real
/// curriculum use, not just a default.
void main() {
  test('the new lessons exist in their tiers', () {
    final byId = {for (final l in Lessons.all) l.id: l};
    expect(byId['two-finger-frame']!.difficulty, Difficulty.beginner);
    expect(byId['waltz-time']!.difficulty, Difficulty.intermediate);
    expect(byId['push-and-pull']!.difficulty, Difficulty.advanced);
  });

  test('Waltz Time is genuinely 3/4: three-beat bars, six pattern slots', () {
    final waltz = Lessons.waltzTime;
    expect(waltz.beatsPerBar, 3);
    expect(waltz.totalBeats, waltz.chordSequence.isEmpty ? 0 : 4 * 3.0);
    // Bar 2 starts at beat 3, not 4: the bass stroke of the second chord.
    final barTwoFirst =
        waltz.events.firstWhere((e) => e.beat >= 3.0);
    expect(barTwoFirst.beat, 3.0);
    // The waltz feel: a downstroke bass on beat 1 of every bar.
    for (var bar = 0; bar < 4; bar++) {
      final first = waltz.events.firstWhere((e) => e.beat == bar * 3.0);
      expect(first.isDown, isTrue, reason: 'bar $bar must open with a bass');
    }
  });

  test('every tier still unlocks sequentially to its new last lesson', () {
    expect(Lessons.nextAfter('blues-shuffle')!.id, 'push-and-pull');
    expect(Lessons.nextAfter('push-and-pull'), isNull);
  });

  test('Easy mode keeps the waltz in 3/4 — no silent 4/4 fallback', () {
    // Round 115 (r114 devil-advocate coverage gap): `simplified` must thread
    // beatsPerBar through, or the count-in/bar-grid/metronome of an Easy
    // waltz would all snap back to common time.
    final easy = Lessons.waltzTime.simplified;
    expect(easy.beatsPerBar, 3);
    expect(easy.totalBeats, Lessons.waltzTime.totalBeats);
    expect(easy.events, isNotEmpty);
    for (final e in easy.events) {
      expect(e.isDown, isTrue);
      expect(e.beat % 1.0, 0.0, reason: 'Easy keeps on-beat strokes only');
    }
    // Every bar still opens with its bass downstroke at bar*3.
    for (var bar = 0; bar < 4; bar++) {
      expect(easy.events.any((e) => e.beat == bar * 3.0), isTrue,
          reason: 'bar $bar must keep its downbeat in 3/4');
    }
  });
}
