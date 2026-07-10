import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/calibration/latency_calibrator.dart';

void main() {
  test('a consistently late tapper measures a positive offset (median)', () {
    final cal = LatencyCalibrator(); // beats at 0.6, 1.2, 1.8 …
    for (var k = 1; k <= 8; k++) {
      cal.registerTap(k * 0.6 + 0.08);
    }
    expect(cal.sampleCount, 8);
    expect(cal.offsetSec, closeTo(0.08, 1e-9));
    expect(cal.jitterSec, closeTo(0, 1e-9));
    expect(cal.isStable, isTrue);
  });

  test('an early tapper (taps before the click) measures NEGATIVE', () {
    final cal = LatencyCalibrator();
    for (var k = 1; k <= 8; k++) {
      cal.registerTap(k * 0.6 - 0.05);
    }
    expect(cal.offsetSec, closeTo(-0.05, 1e-9));
  });

  test('a botched tap (far from every beat) is discarded, not averaged', () {
    final cal = LatencyCalibrator();
    for (var k = 1; k <= 7; k++) {
      cal.registerTap(k * 0.6 + 0.06);
    }
    expect(cal.registerTap(8 * 0.6 + 0.29), isNull); // > maxAbsOffsetSec
    expect(cal.sampleCount, 7);
    expect(cal.offsetSec, closeTo(0.06, 1e-9));
  });

  test('a single wild-but-valid tap cannot drag the median', () {
    final cal = LatencyCalibrator();
    for (var k = 1; k <= 7; k++) {
      cal.registerTap(k * 0.6 + 0.05);
    }
    cal.registerTap(8 * 0.6 + 0.24); // valid but wild
    expect(cal.offsetSec, closeTo(0.05, 1e-9)); // median holds
  });

  test('no result until enough valid samples', () {
    final cal = LatencyCalibrator(minSamples: 5);
    for (var k = 1; k <= 4; k++) {
      cal.registerTap(k * 0.6 + 0.05);
    }
    expect(cal.offsetSec, isNull);
    expect(cal.isStable, isFalse);
    cal.registerTap(5 * 0.6 + 0.05);
    expect(cal.offsetSec, isNotNull);
  });

  test('inconsistent tapping is flagged unstable even with enough taps', () {
    final cal = LatencyCalibrator();
    final wobble = [0.12, -0.10, 0.02, 0.20, -0.15, 0.08, -0.06, 0.16];
    for (var k = 1; k <= wobble.length; k++) {
      cal.registerTap(k * 0.6 + wobble[k - 1]);
    }
    expect(cal.offsetSec, isNotNull);
    expect(cal.isStable, isFalse);
  });

  test('reset clears the run', () {
    final cal = LatencyCalibrator();
    for (var k = 1; k <= 8; k++) {
      cal.registerTap(k * 0.6 + 0.08);
    }
    cal.reset();
    expect(cal.sampleCount, 0);
    expect(cal.offsetSec, isNull);
  });
}
