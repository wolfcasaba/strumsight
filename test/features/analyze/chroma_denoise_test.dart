import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/engine/chroma_denoise.dart';

/// Build a 12-dim chroma frame with the given per-pitch-class values.
Float64List frame(Map<int, double> pcs) {
  final f = Float64List(12);
  pcs.forEach((pc, v) => f[pc] = v);
  return f;
}

void main() {
  group('ChromaDenoise.temporalMedian', () {
    test('removes a single-frame transient spike, preserves the sustained tone',
        () {
      // A chord held on pc=0 across 9 frames. pc=6 spikes hugely in ONLY the
      // middle frame (index 4) — a drum-hit / passing-note transient.
      final frames = <Float64List>[
        for (var i = 0; i < 9; i++)
          frame({0: 1.0, if (i == 4) 6: 50.0}),
      ];

      final out = ChromaDenoise.temporalMedian(frames, window: 5);

      // The transient at the middle frame is outvoted by its neighbours.
      expect(out[4][6], closeTo(0.0, 1e-12));
      // The sustained chord tone survives everywhere.
      for (var i = 0; i < 9; i++) {
        expect(out[i][0], closeTo(1.0, 1e-12));
      }
    });

    test('preserves a value present in a MAJORITY of the window', () {
      // pc=3 is present (value 2.0) in 3 of the 5 window frames around index 2.
      final frames = <Float64List>[
        frame({3: 2.0}),
        frame({3: 2.0}),
        frame({3: 2.0}),
        frame({}),
        frame({}),
      ];

      final out = ChromaDenoise.temporalMedian(frames, window: 5);

      // Window at index 2 covers indices 0..4 → values {2,2,2,0,0}, median 2.
      expect(out[2][3], closeTo(2.0, 1e-12));
    });

    test('window <= 1 returns an unchanged deep copy (input not mutated)', () {
      final original = <Float64List>[
        frame({0: 1.0, 6: 9.0}),
        frame({2: 3.0}),
      ];
      // Snapshot to detect mutation.
      final snapshot = [
        for (final f in original) Float64List.fromList(f),
      ];

      for (final w in [0, 1]) {
        final out = ChromaDenoise.temporalMedian(original, window: w);
        expect(out.length, original.length);
        for (var i = 0; i < original.length; i++) {
          expect(out[i], orderedEquals(original[i]));
          // A copy, not the same instance.
          expect(identical(out[i], original[i]), isFalse);
        }
      }

      // Input frames untouched.
      for (var i = 0; i < original.length; i++) {
        expect(original[i], orderedEquals(snapshot[i]));
      }
    });

    test('does not mutate the input when filtering', () {
      final frames = <Float64List>[
        for (var i = 0; i < 7; i++) frame({0: 1.0, if (i == 3) 5: 40.0}),
      ];
      final snapshot = [
        for (final f in frames) Float64List.fromList(f),
      ];

      ChromaDenoise.temporalMedian(frames, window: 5);

      for (var i = 0; i < frames.length; i++) {
        expect(frames[i], orderedEquals(snapshot[i]),
            reason: 'input frame $i must be untouched');
      }
    });

    test('handles edge frames (clamped window) without crashing', () {
      final frames = <Float64List>[
        frame({0: 5.0}),
        frame({0: 1.0}),
        frame({0: 1.0}),
        frame({0: 1.0}),
        frame({0: 7.0}),
      ];

      final out = ChromaDenoise.temporalMedian(frames, window: 5);

      // Start frame: window clamps to indices 0..2 → {5,1,1}, median 1.
      expect(out[0][0], closeTo(1.0, 1e-12));
      // End frame: window clamps to indices 2..4 → {1,1,7}, median 1.
      expect(out[4][0], closeTo(1.0, 1e-12));
    });

    test('preserves length and returns a fresh list', () {
      final frames = <Float64List>[
        for (var i = 0; i < 11; i++) frame({(i % 12): 1.0}),
      ];

      final out = ChromaDenoise.temporalMedian(frames, window: 5);

      expect(out.length, frames.length);
      expect(identical(out, frames), isFalse);
      for (var i = 0; i < frames.length; i++) {
        expect(out[i].length, 12);
      }
    });

    test('sequence shorter than the window returns an unchanged copy', () {
      final frames = <Float64List>[
        frame({0: 1.0, 6: 9.0}),
        frame({1: 2.0}),
        frame({2: 3.0}),
      ];

      final out = ChromaDenoise.temporalMedian(frames, window: 5);

      expect(out.length, 3);
      for (var i = 0; i < frames.length; i++) {
        expect(out[i], orderedEquals(frames[i]));
        expect(identical(out[i], frames[i]), isFalse);
      }
    });
  });
}
