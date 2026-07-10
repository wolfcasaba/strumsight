import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/metronome/tap_tempo.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12, 0, 0);

  test('needs two taps before it estimates a tempo', () {
    final tt = TapTempo();
    expect(tt.tap(t0), isNull);
    expect(tt.tap(t0.add(const Duration(milliseconds: 500))), 120);
  });

  test('averages several even taps to a steady BPM', () {
    final tt = TapTempo();
    for (var i = 0; i < 4; i++) {
      tt.tap(t0.add(Duration(milliseconds: 500 * i))); // 120 BPM
    }
    expect(tt.bpm, 120);
  });

  test('a long gap resets the running average', () {
    final tt = TapTempo(resetAfter: const Duration(seconds: 2));
    tt.tap(t0);
    tt.tap(t0.add(const Duration(milliseconds: 500))); // 120 so far
    // Gap of 3s → the next tap starts fresh, so no estimate yet.
    final after = tt.tap(t0.add(const Duration(seconds: 4)));
    expect(after, isNull);
    expect(tt.count, 1);
  });

  test('clamps absurdly fast/slow tapping into range', () {
    final fast = TapTempo(maxBpm: 300);
    fast.tap(t0);
    // 50ms apart → 1200 BPM raw → clamped to 300.
    expect(fast.tap(t0.add(const Duration(milliseconds: 50))), 300);

    final slow = TapTempo(minBpm: 40);
    slow.tap(t0);
    // 3s apart is within resetAfter=2s? No — use a shorter reset off.
    final slow2 = TapTempo(minBpm: 40, resetAfter: const Duration(seconds: 10));
    slow2.tap(t0);
    // 2s apart → 30 BPM raw → clamped up to 40.
    expect(slow2.tap(t0.add(const Duration(seconds: 2))), 40);
  });

  test('rolling window drops the oldest tap past maxTaps', () {
    final tt = TapTempo(maxTaps: 3);
    for (var i = 0; i < 5; i++) {
      tt.tap(t0.add(Duration(milliseconds: 400 * i)));
    }
    expect(tt.count, 3);
    expect(tt.bpm, 150); // 400ms spacing → 150 BPM
  });
}
