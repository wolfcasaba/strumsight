// E18-R01 emulator finding F10 — the Live input-level meter sat at 0 % or
// 100 % whatever the mic gain, because `rms * 8` spans only a 14 dB window.
// These cells pin the dBFS mapping and the release ballistics of the
// replacement, and a randomized property (HORIZON) checks monotonicity and
// range over random levels so the curve cannot be tuned to the fixtures.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/components/music/ss_signal_quality_indicator.dart';
import 'package:strumsight/features/live/engine/dsp/input_level_meter.dart';

double _rmsForDbfs(double dbfs) => math.pow(10, dbfs / 20).toDouble();

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final rng = math.Random(seed);
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  group('instantaneous mapping', () {
    final meter = InputLevelMeter();

    test('silence reads 0, a hot input reads 1', () {
      expect(meter.instantaneous(0), 0);
      expect(meter.instantaneous(_rmsForDbfs(-60)), 0);
      expect(meter.instantaneous(_rmsForDbfs(-6)), 1);
      expect(meter.instantaneous(_rmsForDbfs(-1)), 1);
    });

    test(
      'the ordinary recording range (−40…−12 dBFS) is spread across the '
      'meter, not pinned at either end — the measured F10 failure',
      () {
        // The old `rms * 8` curve: −18 dBFS and above → 1.0; −32 and below → 0.
        expect(meter.instantaneous(_rmsForDbfs(-12)), closeTo(0.846, 0.01));
        expect(meter.instantaneous(_rmsForDbfs(-18)), closeTo(0.692, 0.01));
        expect(meter.instantaneous(_rmsForDbfs(-25)), closeTo(0.513, 0.01));
        expect(meter.instantaneous(_rmsForDbfs(-32)), closeTo(0.333, 0.01));
        expect(meter.instantaneous(_rmsForDbfs(-40)), closeTo(0.128, 0.01));
      },
    );

    test(
      'the weak-signal threshold lands on the analyzer\'s −40 dBFS "quiet" '
      'line (±1 dB)',
      () {
        final atThreshold = meter.instantaneous(_rmsForDbfs(-40));
        final weak = SsSignalQualityIndicator.defaultWeakThreshold;
        expect(atThreshold, closeTo(weak, 0.02));
        expect(meter.instantaneous(_rmsForDbfs(-41)), lessThan(weak));
        expect(meter.instantaneous(_rmsForDbfs(-39)), greaterThan(weak));
      },
    );

    test('property: monotonic, bounded, linear in dB between the knees', () {
      for (var i = 0; i < 500; i++) {
        final a = -70 + rng.nextDouble() * 70; // −70 … 0 dBFS
        final b = -70 + rng.nextDouble() * 70;
        final la = meter.instantaneous(_rmsForDbfs(a));
        final lb = meter.instantaneous(_rmsForDbfs(b));
        expect(la, inInclusiveRange(0, 1), reason: 'seed=$seed a=$a');
        if (a < b) {
          expect(la, lessThanOrEqualTo(lb), reason: 'seed=$seed a=$a b=$b');
        }
        if (a > InputLevelMeter.defaultFloorDbfs &&
            a < InputLevelMeter.defaultCeilingDbfs) {
          final span =
              InputLevelMeter.defaultCeilingDbfs -
              InputLevelMeter.defaultFloorDbfs;
          expect(
            la,
            closeTo((a - InputLevelMeter.defaultFloorDbfs) / span, 1e-9),
            reason: 'seed=$seed a=$a',
          );
        }
      }
    });
  });

  group('ballistics', () {
    test('instant attack, exponential release per frame', () {
      final meter = InputLevelMeter();
      expect(meter.update(_rmsForDbfs(-6)), 1);
      // The burst is over; the meter releases rather than dropping to 0.
      expect(meter.update(0), closeTo(0.7, 1e-9));
      expect(meter.update(0), closeTo(0.49, 1e-9));
      // A new, louder-than-released frame takes over immediately.
      expect(meter.update(_rmsForDbfs(-20)), closeTo(0.641, 0.001));
    });

    test('releases to exactly 0 within about half a second of silence', () {
      final meter = InputLevelMeter();
      meter.update(_rmsForDbfs(-6));
      var frames = 0;
      while (meter.level > 0 && frames < 100) {
        meter.update(0);
        frames++;
      }
      expect(meter.level, 0);
      // 0.7^n < 0.001 → n ≥ 20 frames ≈ 1.3 s at 15 Hz to the hard zero;
      // the reading is below 5 % after 9 frames (~0.6 s).
      expect(frames, inInclusiveRange(15, 25));
    });

    test('reset returns the meter to 0', () {
      final meter = InputLevelMeter()..update(_rmsForDbfs(-10));
      meter.reset();
      expect(meter.level, 0);
    });
  });
}
