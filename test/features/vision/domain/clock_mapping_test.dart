import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_timestamp.dart';
import 'package:strumsight/features/vision/application/sync_calibration_controller.dart';
import 'package:strumsight/features/vision/domain/sync/clock_mapping.dart';
import 'package:strumsight/features/vision/domain/sync/sync_quality.dart';
import 'package:strumsight/features/vision/domain/sync/vision_clock.dart';

void main() {
  group('clock boundaries', () {
    test('VisionClock preserves CameraTimestamp microseconds', () {
      final clock = VisionClock();

      expect(
        clock.toSessionTime(const CameraTimestamp(42)),
        const SessionTimestamp(42),
      );
    });

    test('AudioClock converts the injected DateTime at its boundary', () {
      final clock = AudioClock(reference: DateTime.utc(2026, 8, 8, 12));

      expect(
        clock.toSessionTime(DateTime.utc(2026, 8, 8, 12, 0, 0, 12)),
        const SessionTimestamp(12_000),
      );
    });

    test('a non-monotonic audio timestamp fails explicitly', () {
      final clock = AudioClock(reference: DateTime.utc(2026, 8, 8, 12));
      clock.toSessionTime(DateTime.utc(2026, 8, 8, 12, 0, 0, 3));

      expect(
        () => clock.toSessionTime(DateTime.utc(2026, 8, 8, 12, 0, 0, 2)),
        throwsA(isA<ClockMappingException>()),
      );
    });

    test('a non-increasing camera timestamp fails explicitly', () {
      final clock = VisionClock();
      clock.toSessionTime(const CameraTimestamp(10));

      expect(
        () => clock.toSessionTime(const CameraTimestamp(10)),
        throwsA(isA<ClockMappingException>()),
      );
    });

    test('mapping-domain sources contain no system wall-clock read', () {
      const sourcePaths = <String>[
        'lib/features/vision/domain/sync/vision_clock.dart',
        'lib/features/vision/domain/sync/clock_mapping.dart',
        'lib/features/vision/application/sync_calibration_controller.dart',
      ];
      final forbidden = ['DateTime', '.now('].join();

      for (final path in sourcePaths) {
        expect(
          File(path).readAsStringSync(),
          isNot(contains(forbidden)),
          reason: '$path must use an injected timestamp boundary only.',
        );
      }
    });
  });

  group('offset and outlier calibration', () {
    for (final offsetUs in <int>[-25_000, -1, 0, 1, 37_000]) {
      test('recovers known offset $offsetUs µs', () {
        final controller = SyncCalibrationController();
        final result = controller.calibrate(_samplesForOffset(offsetUs));

        expect(result.mapping.offsetUs, offsetUs);
        expect(result.mapping.driftPpm, 0);
        expect(result.mapping.confidence, 1);
      });
    }

    test('rejects one large outlier without moving the offset', () {
      final controller = SyncCalibrationController(
        configuration: const CalibrationConfiguration(
          maximumOffsetDeviationUs: 5_000,
        ),
      );
      final result = controller.calibrate(<CalibrationSample>[
        ..._samplesForOffset(12_345),
        CalibrationSample(
          visionMotionPeak: SessionTimestamp(5_000_000),
          audioOnset: SessionTimestamp(500_000),
        ),
      ]);

      expect(result.mapping.offsetUs, 12_345);
      expect(result.statistics.acceptedSamples, 4);
      expect(result.statistics.rejectedSamples, 1);
      expect(result.mapping.confidence, closeTo(0.8, 1e-12));
    });

    test('records average latency components from accepted pairs', () {
      final result = SyncCalibrationController().calibrate(<CalibrationSample>[
        CalibrationSample(
          visionMotionPeak: SessionTimestamp(0),
          audioOnset: SessionTimestamp(1_000),
          latency: LatencyComponents(
            captureToInference: Duration(milliseconds: 4),
            inferenceToObservation: Duration(milliseconds: 6),
          ),
        ),
        CalibrationSample(
          visionMotionPeak: SessionTimestamp(1_000_000),
          audioOnset: SessionTimestamp(1_001_000),
          latency: LatencyComponents(
            captureToInference: Duration(milliseconds: 6),
            inferenceToObservation: Duration(milliseconds: 10),
          ),
        ),
        CalibrationSample(
          visionMotionPeak: SessionTimestamp(2_000_000),
          audioOnset: SessionTimestamp(2_001_000),
          latency: LatencyComponents(
            captureToInference: Duration(milliseconds: 8),
            inferenceToObservation: Duration(milliseconds: 14),
          ),
        ),
      ]);

      expect(
        result.statistics.meanLatency!.captureToInference.inMilliseconds,
        6,
      );
      expect(
        result.statistics.meanLatency!.inferenceToObservation.inMilliseconds,
        10,
      );
      expect(result.statistics.meanLatency!.total.inMilliseconds, 16);
    });
  });

  group('sync quality boundary matrix', () {
    const thresholds = SyncQualityThresholds();

    test('excellent upper boundary is inclusive', () {
      expect(
        thresholds.forAbsoluteErrorUs(thresholds.excellentMaximumErrorUs - 1),
        SyncQuality.excellent,
      );
      expect(
        thresholds.forAbsoluteErrorUs(thresholds.excellentMaximumErrorUs),
        SyncQuality.excellent,
      );
      expect(
        thresholds.forAbsoluteErrorUs(thresholds.excellentMaximumErrorUs + 1),
        SyncQuality.good,
      );
    });

    test('good lower boundary is good on both signed sides', () {
      final lowerGood = thresholds.excellentMaximumErrorUs + 1;

      expect(thresholds.forAbsoluteErrorUs(lowerGood), SyncQuality.good);
      expect(thresholds.forAbsoluteErrorUs(-lowerGood), SyncQuality.good);
      expect(
        thresholds.forAbsoluteErrorUs(thresholds.goodMaximumErrorUs),
        SyncQuality.good,
      );
    });

    test(
      'good and acceptable upper boundaries classify every adjacent cell',
      () {
        expect(
          thresholds.forAbsoluteErrorUs(thresholds.goodMaximumErrorUs + 1),
          SyncQuality.acceptable,
        );
        expect(
          thresholds.forAbsoluteErrorUs(
            thresholds.acceptableMaximumErrorUs - 1,
          ),
          SyncQuality.acceptable,
        );
        expect(
          thresholds.forAbsoluteErrorUs(thresholds.acceptableMaximumErrorUs),
          SyncQuality.acceptable,
        );
        expect(
          thresholds.forAbsoluteErrorUs(
            thresholds.acceptableMaximumErrorUs + 1,
          ),
          SyncQuality.poor,
        );
      },
    );

    test('only good and excellent permit event-level conclusions', () {
      expect(thresholds.isEventLevelReliable(SyncQuality.poor), isFalse);
      expect(thresholds.isEventLevelReliable(SyncQuality.acceptable), isFalse);
      expect(thresholds.isEventLevelReliable(SyncQuality.good), isTrue);
      expect(thresholds.isEventLevelReliable(SyncQuality.excellent), isTrue);
    });
  });

  test('mapping with excessive drift is invalid instead of extrapolated', () {
    final mapping = ClockMapping(
      source: ClockDomain.vision,
      target: ClockDomain.audio,
      offsetUs: 0,
      driftPpm: ClockMapping.defaultMaximumAbsoluteDriftPpm + 1,
      confidence: 1,
    );

    expect(mapping.isValid, isFalse);
    expect(
      () => mapping.map(const SessionTimestamp(1_000)),
      throwsA(isA<ClockMappingException>()),
    );
  });
}

List<CalibrationSample> _samplesForOffset(int offsetUs) => <CalibrationSample>[
  for (final visionUs in <int>[0, 1_000_000, 2_000_000, 3_000_000])
    CalibrationSample(
      visionMotionPeak: SessionTimestamp(visionUs),
      audioOnset: SessionTimestamp(visionUs + offsetUs),
    ),
];
