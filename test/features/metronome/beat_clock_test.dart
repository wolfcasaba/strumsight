import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/metronome/beat_clock.dart';

/// Round 98 — changing the metronome tempo MID-PLAY must not jump the beat.
/// The old `beat = secs · bpm/60` rescaled the whole elapsed time
/// retroactively (60→240 BPM at 30 s teleported beat 30 → 120). BeatClock
/// anchors the phase at each tempo change instead.
void main() {
  test('advances linearly at a constant tempo', () {
    final clock = BeatClock(bpm: 60);
    expect(clock.beatsAt(0), 0);
    expect(clock.beatsAt(1.0), closeTo(1.0, 1e-9));
    expect(clock.beatsAt(2.5), closeTo(2.5, 1e-9));
  });

  test('a tempo change preserves the current beat phase — no jump', () {
    final clock = BeatClock(bpm: 60);
    // At 2.5 s we are at beat 2.5; double the tempo there.
    clock.setBpm(120, atSecs: 2.5);
    expect(clock.beatsAt(2.5), closeTo(2.5, 1e-9),
        reason: 'the change itself must not move the playhead');
    // From here on, beats accrue at the NEW rate only.
    expect(clock.beatsAt(3.0), closeTo(3.5, 1e-9));
    expect(clock.beatsAt(3.5), closeTo(4.5, 1e-9));
  });

  test('the old formula\'s failure case: 60→240 at 30 s stays continuous',
      () {
    final clock = BeatClock(bpm: 60);
    final before = clock.beatsAt(30.0); // beat 30
    clock.setBpm(240, atSecs: 30.0);
    final after = clock.beatsAt(30.0);
    expect(after, closeTo(before, 1e-9),
        reason: 'old code would report beat 120 here');
  });

  test('slowing down never runs the beat counter backwards', () {
    final clock = BeatClock(bpm: 240);
    clock.setBpm(60, atSecs: 10.0); // beat 40 at the change
    expect(clock.beatsAt(10.0), closeTo(40.0, 1e-9));
    expect(clock.beatsAt(11.0), closeTo(41.0, 1e-9));
  });

  test('reset rewinds to beat zero', () {
    final clock = BeatClock(bpm: 100);
    clock.setBpm(120, atSecs: 5.0);
    clock.reset();
    expect(clock.beatsAt(0), 0);
    expect(clock.beatsAt(0.5), closeTo(1.0, 1e-9)); // 120 BPM kept
  });
}
