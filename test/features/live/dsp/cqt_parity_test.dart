import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/cqt_extractor.dart';

/// Bit-parity golden test for [CqtExtractor] against the Python reference
/// (`ml/chords/cqt.py`, fixture `ml/chords/cqt_fixture.json`) — StrumSight r194.
///
/// The fixture stores the input PCM + numpy's `cqt()` output rounded to 6
/// decimals, so the achievable floor is ~5e-7 from that rounding alone. A
/// faithful port (float32-rounded sparse kernel, same Hann/Q/FMIN/HOP/FFT_LEN,
/// same log1p) reproduces it far tighter than the log-mel path's ~1e-3..1e-2.
/// Tolerance is set at 1e-4 and the ACTUAL max abs diff is asserted/printed —
/// do NOT loosen it to force a pass; fix the Dart math instead.
void main() {
  test('CqtExtractor matches cqt.py golden fixture', () {
    // Resolve the fixture from the repo root regardless of test cwd.
    File findFixture() {
      var dir = Directory.current;
      for (var i = 0; i < 6; i++) {
        final f = File('${dir.path}/ml/chords/cqt_fixture.json');
        if (f.existsSync()) return f;
        dir = dir.parent;
      }
      fail('cqt_fixture.json not found from ${Directory.current.path}');
    }

    final fx = jsonDecode(findFixture().readAsStringSync()) as Map<String, dynamic>;
    final fixtureSr = fx['sr'] as int;
    final expNFrames = fx['n_frames'] as int;
    final expNBins = fx['n_bins'] as int;

    final pcm = Float32List.fromList(
      (fx['pcm'] as List).map((e) => (e as num).toDouble()).toList(),
    );
    final expected = (fx['cqt'] as List)
        .map((row) => (row as List).map((e) => (e as num).toDouble()).toList())
        .toList();

    expect(expNBins, CqtExtractor.nBins);
    expect(expected.length, expNFrames);

    final got = CqtExtractor().extract(pcm, fixtureSr);

    // Shape parity.
    expect(got.length, expected.length,
        reason: 'frame count ${got.length} vs ${expected.length}');
    for (final row in got) {
      expect(row.length, CqtExtractor.nBins);
    }

    // Value parity: max absolute difference across every frame and bin.
    var maxAbs = 0.0;
    var argFrame = -1, argBin = -1;
    for (var i = 0; i < got.length; i++) {
      for (var k = 0; k < CqtExtractor.nBins; k++) {
        final d = (got[i][k] - expected[i][k]).abs();
        if (d > maxAbs) {
          maxAbs = d;
          argFrame = i;
          argBin = k;
        }
      }
    }
    // ignore: avoid_print
    print('CQT parity: max abs diff = $maxAbs at frame $argFrame bin $argBin '
        '(${got.length}x${CqtExtractor.nBins}, fftLen=${CqtExtractor.fftLen})');

    expect(maxAbs, lessThan(1e-4),
        reason: 'max abs diff $maxAbs at frame $argFrame bin $argBin');
    expect(maxAbs.isFinite, isTrue);
    // Sanity: output is non-negative (log1p of a magnitude) and non-trivial.
    var anyNonZero = false;
    for (final row in got) {
      for (final v in row) {
        expect(v, greaterThanOrEqualTo(0.0));
        if (v > 1e-6) anyNonZero = true;
      }
    }
    expect(anyNonZero, isTrue);
  });
}
