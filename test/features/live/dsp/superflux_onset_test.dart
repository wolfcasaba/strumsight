import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/superflux_onset_detector.dart';

import '../../../support/synth.dart';

/// SuperFlux onset detector (docs/plans/ml-track.md P0.2; chunk 015 rec #3).
///
/// The whitened plain flux is the weak link at 16th notes (~8 onsets/s) and
/// fires on vibrato; SuperFlux (log-mel + a maximum filter across bands +
/// trajectory lag) is the field-standard fix. Eval window: ±50 ms (chunk 015).
const _sr = 44100;
const _tolSec = 0.05;

List<double> _detect(Float64List signal, {SuperFluxOnsetDetector? detector}) {
  final d = detector ?? SuperFluxOnsetDetector(sampleRate: _sr);
  final onsets = <double>[];
  for (final frame in frames(signal, d.window, d.hop)) {
    final t = d.processFrame(frame);
    if (t != null) onsets.add(t);
  }
  return onsets;
}

/// True-positive matches between detected and expected within ±[_tolSec];
/// each expected onset can be claimed once.
int _matches(List<double> detected, List<double> expected) {
  final remaining = List<double>.from(expected);
  var hits = 0;
  for (final t in detected) {
    final i = remaining.indexWhere((e) => (e - t).abs() <= _tolSec);
    if (i >= 0) {
      remaining.removeAt(i);
      hits++;
    }
  }
  return hits;
}

void main() {
  group('SuperFluxOnsetDetector', () {
    test('finds all 16th-note strums at 120 BPM within ±50 ms', () {
      const gap = 60 / 120 / 4; // 0.125 s
      final signal = strumPattern(
        lowFirstPerStrum: List.filled(8, true),
        gapSeconds: gap,
      );
      final expected = [for (var i = 0; i < 8; i++) 0.1 + i * gap];
      final onsets = _detect(signal);
      expect(_matches(onsets, expected), 8,
          reason: 'every strum detected within ±50 ms (got $onsets)');
      expect(onsets.length, lessThanOrEqualTo(9),
          reason: 'no more than one spurious extra');
    });

    test('finds all 16th-note strums at 160 BPM within ±50 ms', () {
      const gap = 60 / 160 / 4; // 93.75 ms
      final signal = strumPattern(
        lowFirstPerStrum: List.filled(8, true),
        gapSeconds: gap,
      );
      final expected = [for (var i = 0; i < 8; i++) 0.1 + i * gap];
      final onsets = _detect(signal);
      expect(_matches(onsets, expected), greaterThanOrEqualTo(7),
          reason: '≥7/8 at the hard tempo (got $onsets)');
    });

    test('stays silent on constant-amplitude vibrato (the SuperFlux win)', () {
      final signal = vibratoNote(freq: 440, seconds: 2.0);
      final onsets = _detect(signal);
      expect(onsets.length, lessThanOrEqualTo(1),
          reason: 'only the initial attack may fire (got $onsets)');
    });

    test('silence and a stationary noise floor produce zero onsets', () {
      expect(_detect(Float64List(_sr)), isEmpty);

      final rng = math.Random(7);
      final noise = Float64List.fromList(
        List.generate(_sr, (_) => (rng.nextDouble() * 2 - 1) * 0.003),
      );
      expect(_detect(noise), isEmpty);
    });

    test('overlapping ring-out strums are still separated', () {
      final signal = overlappingStrums(
        lowFirstPerStrum: [true, false, true, false, true, false],
        gapSeconds: 0.15,
        ringSeconds: 0.4, // rings well past the next onset
      );
      final expected = [for (var i = 0; i < 6; i++) 0.1 + i * 0.15];
      final onsets = _detect(signal);
      expect(_matches(onsets, expected), greaterThanOrEqualTo(5),
          reason: '≥5/6 under heavy ring-out (got $onsets)');
    });
  });
}
