import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/ml/crnn_frontend.dart';

/// The Dart ports feeding the CRNN must mirror the Python training pipeline
/// exactly (ml/prepare_dataset.py::_read_wav resample, ml/features.py::
/// window_at) — the r134 parity discipline: feature drift silently kills a
/// trained model.
void main() {
  group('resampleLinear', () {
    test('mirrors np.interp over linspace(0, n-1, round(n*to/from))', () {
      // 8 samples at 4 Hz -> 4 samples at 2 Hz: positions 0, 7/3, 14/3, 7.
      final x = Float64List.fromList(
          [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]);
      final y = CrnnFrontend.resampleLinear(x, 4, 2);
      expect(y, hasLength(4));
      expect(y[0], closeTo(0.0, 1e-12));
      expect(y[1], closeTo(7 / 3, 1e-12));
      expect(y[2], closeTo(14 / 3, 1e-12));
      expect(y[3], closeTo(7.0, 1e-12));
    });

    test('same-rate input is returned unchanged', () {
      final x = Float64List.fromList([0.5, -0.5, 0.25]);
      expect(CrnnFrontend.resampleLinear(x, 16000, 16000), same(x));
    });

    test('preserves a sine well below Nyquist (44.1k -> 16k)', () {
      const sr = 44100;
      final x = Float64List(sr); // 1 s of 440 Hz
      for (var i = 0; i < x.length; i++) {
        x[i] = math.sin(2 * math.pi * 440 * i / sr);
      }
      final y = CrnnFrontend.resampleLinear(x, sr, 16000);
      expect(y.length, 16000);
      // Sample the middle: the resampled sine must track the analytic value.
      for (var i = 4000; i < 4100; i++) {
        final t = i * (x.length - 1) / (y.length - 1) / sr;
        expect(y[i], closeTo(math.sin(2 * math.pi * 440 * t), 0.02));
      }
    });
  });

  group('windowAt', () {
    // 20 fake log-mel frames whose first coefficient encodes the frame index
    // so slicing mistakes are visible.
    final frames = [
      for (var i = 0; i < 20; i++)
        Float64List(128)..[0] = i.toDouble()..[127] = -i.toDouble(),
    ];

    test('cuts PRE=3 before and POST=12 after the onset frame', () {
      // onset 0.1 s @16k/160 hop -> center frame 10 -> rows 7..21
      // (python-verified: frame 19 is the last real row, then zero-pad).
      final w = CrnnFrontend.windowAt(frames, 0.1);
      expect(w, hasLength(15));
      expect(w.first[0], 7);
      expect(w[3][0], 10, reason: 'the onset frame sits at index PRE');
      expect(w[12][0], 19, reason: 'last real frame of the 20-frame fixture');
      expect(w.last[0], 0, reason: 'rows past the end are zero-padded');
    });

    test('zero-pads past both edges like the Python reference', () {
      final early = CrnnFrontend.windowAt(frames, 0.0); // center 0 -> lo -3
      expect(early, hasLength(15));
      expect(early[0][0], 0);
      expect(early[0][127], 0, reason: 'row before frame 0 is all zeros');
      expect(early[3][0], 0, reason: 'onset frame 0 at index PRE');
      expect(early[4][0], 1);

      final late = CrnnFrontend.windowAt(frames, 0.18); // center 18 -> hi 30
      expect(late, hasLength(15));
      expect(late[0][0], 15);
      expect(late[4][0], 19, reason: 'last real frame');
      expect(late[5][0], 0, reason: 'rows past the end are zeros');
      expect(late[14][127], 0);
    });
  });
}
