import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/application/sync_calibration_controller.dart';
import 'package:strumsight/features/vision/domain/sync/clock_mapping.dart';
import 'package:strumsight/features/vision/domain/sync/vision_clock.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final random = Random(seed);

  test('linear drift maps within the documented 1% error-rate limit '
      '(PROPERTY_SEED=$seed)', () {
    const trials = 64;
    var incorrectMappings = 0;
    var mappedPoints = 0;

    for (var trial = 0; trial < trials; trial++) {
      final offsetUs = random.nextInt(60_001) - 30_000;
      final driftPpm = random.nextInt(201) - 100;
      final samples = <CalibrationSample>[
        for (var index = 0; index < 8; index++)
          _sampleAt(
            visionUs: index * 1_000_000,
            offsetUs: offsetUs,
            driftPpm: driftPpm,
          ),
      ];
      final result = SyncCalibrationController(
        configuration: const CalibrationConfiguration(
          maximumOffsetDeviationUs: 100_000,
        ),
      ).calibrate(samples, estimateDrift: true);

      for (var index = 0; index <= 10; index++) {
        final visionUs = index * 750_000;
        final expected = _audioUs(
          visionUs: visionUs,
          offsetUs: offsetUs,
          driftPpm: driftPpm,
        );
        final actual = result.mapping
            .map(SessionTimestamp(visionUs))
            .microseconds;
        if ((actual - expected).abs() > 3) incorrectMappings++;
        mappedPoints++;
      }
    }

    final errorRate = incorrectMappings / mappedPoints;
    expect(errorRate, lessThanOrEqualTo(0.01));
  });
}

CalibrationSample _sampleAt({
  required int visionUs,
  required int offsetUs,
  required int driftPpm,
}) => CalibrationSample(
  visionMotionPeak: SessionTimestamp(visionUs),
  audioOnset: SessionTimestamp(
    _audioUs(visionUs: visionUs, offsetUs: offsetUs, driftPpm: driftPpm),
  ),
);

int _audioUs({
  required int visionUs,
  required int offsetUs,
  required int driftPpm,
}) =>
    visionUs +
    offsetUs +
    (visionUs * driftPpm / Duration.microsecondsPerSecond).round();
