import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/tuner/model/guitar_strings.dart';

/// GuitarTuna-class tuner UX (round 84): show the six standard-tuning
/// strings and highlight the one being tuned — a beginner shouldn't have to
/// know that "D3" means the 4th string.
void main() {
  test('exact string frequencies map to their string', () {
    expect(GuitarStrings.nearest(82.41)?.label, 'E2');
    expect(GuitarStrings.nearest(110.0)?.label, 'A2');
    expect(GuitarStrings.nearest(146.83)?.label, 'D3');
    expect(GuitarStrings.nearest(196.0)?.label, 'G3');
    expect(GuitarStrings.nearest(246.94)?.label, 'B3');
    expect(GuitarStrings.nearest(329.63)?.label, 'E4');
  });

  test('a detuned string still maps to the nearest string', () {
    expect(GuitarStrings.nearest(105.0)?.label, 'A2'); // flat A
    expect(GuitarStrings.nearest(90.0)?.label, 'E2'); // sharp low E
  });

  test('midpoints resolve by log distance (geometric mean boundary)', () {
    // Geometric mean of A2 (110) and D3 (146.83) ≈ 127.1.
    expect(GuitarStrings.nearest(126.0)?.label, 'A2');
    expect(GuitarStrings.nearest(128.5)?.label, 'D3');
  });

  test('the A4 reference scales every string', () {
    // A=432 → A2 = 108; 108 must be dead-on A2, and 110 still nearest A2.
    final s = GuitarStrings.nearest(108.0, a4: 432);
    expect(s?.label, 'A2');
    expect(GuitarStrings.nearest(108.0, a4: 432)!.frequencyHz(432),
        closeTo(108.0, 0.01));
  });

  test('silence / nonsense frequencies map to nothing', () {
    expect(GuitarStrings.nearest(0), isNull);
    expect(GuitarStrings.nearest(-5), isNull);
  });

  test('far-out-of-range pitches (voice, whistle) are not claimed', () {
    expect(GuitarStrings.nearest(1200), isNull,
        reason: 'more than ~5 semitones above E4 is not a string being tuned');
    expect(GuitarStrings.nearest(40), isNull);
  });
}
