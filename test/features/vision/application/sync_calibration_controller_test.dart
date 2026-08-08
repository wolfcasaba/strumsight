import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/application/sync_calibration_controller.dart';
import 'package:strumsight/features/vision/domain/sync/clock_mapping.dart';
import 'package:strumsight/features/vision/domain/sync/vision_clock.dart';

void main() {
  test('recalibration preserves already-issued observation provenance', () {
    final controller = SyncCalibrationController();
    controller.calibrate(_samples(offsetUs: 1_000));
    final issuedBeforeRecalibration = controller.mapVisionObservation(
      const SessionTimestamp(2_000_000),
    );

    controller.calibrate(_samples(offsetUs: -2_000));
    final issuedAfterRecalibration = controller.mapVisionObservation(
      const SessionTimestamp(2_000_000),
    );

    expect(
      issuedBeforeRecalibration.mappedTimestamp,
      const SessionTimestamp(2_001_000),
    );
    expect(issuedBeforeRecalibration.mapping.offsetUs, 1_000);
    expect(
      issuedAfterRecalibration.mappedTimestamp,
      const SessionTimestamp(1_998_000),
    );
    expect(issuedAfterRecalibration.mapping.offsetUs, -2_000);
  });

  test('mapping before calibration fails instead of guessing an offset', () {
    final controller = SyncCalibrationController();

    expect(
      () => controller.mapVisionObservation(const SessionTimestamp(0)),
      throwsStateError,
    );
  });
}

List<CalibrationSample> _samples({required int offsetUs}) =>
    <CalibrationSample>[
      for (final visionUs in <int>[0, 1_000_000, 2_000_000])
        CalibrationSample(
          visionMotionPeak: SessionTimestamp(visionUs),
          audioOnset: SessionTimestamp(visionUs + offsetUs),
        ),
    ];
