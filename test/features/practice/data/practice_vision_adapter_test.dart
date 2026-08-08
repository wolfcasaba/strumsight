import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/data/vision/practice_vision_adapter.dart';
import 'package:strumsight/features/vision/public.dart';

void main() {
  const adapter = PracticeVisionAdapter();

  group('PracticeVisionAdapter quality mapping', () {
    for (final entry in <VisionMetricState, VisionPracticeQuality>{
      VisionMetricState.good: VisionPracticeQuality.good,
      VisionMetricState.needsImprovement: VisionPracticeQuality.degraded,
      VisionMetricState.notObservable: VisionPracticeQuality.unavailable,
    }.entries) {
      test(
        'maps VisionQualitySummary.overall ${entry.key} deterministically',
        () {
          final evaluation = adapter.evaluate(
            contract: VisionPracticeContracts.smallStrumMotion,
            availableCapabilities: _allCapabilities,
            session: _session(entry.key),
          );

          expect(evaluation.quality, entry.value);
          expect(
            evaluation.mode,
            entry.value == VisionPracticeQuality.good
                ? PracticeVisionMode.audioAndVision
                : PracticeVisionMode.audioOnly,
          );
          expect(evaluation.isPracticeAvailable, isTrue);
        },
      );
    }

    test('maps a missing session to unavailable audio-only practice', () {
      final evaluation = adapter.evaluate(
        contract: VisionPracticeContracts.smallStrumMotion,
        availableCapabilities: _allCapabilities,
      );

      expect(evaluation.quality, VisionPracticeQuality.unavailable);
      expect(evaluation.mode, PracticeVisionMode.audioOnly);
      expect(evaluation.isPracticeAvailable, isTrue);
    });
  });

  test(
    'every pilot remains available audio-only when its capability is absent',
    () {
      for (final contract in VisionPracticeContracts.pilots) {
        final evaluation = adapter.evaluate(
          contract: contract,
          availableCapabilities: const VisionPracticeCapabilities(),
          session: _session(VisionMetricState.good),
        );

        expect(evaluation.isPracticeAvailable, isTrue, reason: contract.id);
        expect(
          evaluation.mode,
          PracticeVisionMode.audioOnly,
          reason: contract.id,
        );
        expect(
          evaluation.quality,
          VisionPracticeQuality.unavailable,
          reason: contract.id,
        );
      }
    },
  );

  test(
    'pilot contracts use stable vision namespace and required capabilities',
    () {
      expect(
        VisionPracticeContracts.pilots.map((contract) => contract.id),
        containsAll(<String>[
          'vision.pilot.small-strum-motion',
          'vision.pilot.down-up-symmetry',
          'vision.pilot.chord-change-economy',
        ]),
      );
      expect(
        VisionPracticeContracts.smallStrumMotion.requiredCapabilities.picking,
        contains(PickingCapability.guitarRelativeTracking),
      );
      expect(
        VisionPracticeContracts
            .chordChangeEconomy
            .requiredCapabilities
            .fretting,
        containsAll(<FrettingCapability>[
          FrettingCapability.handTracking,
          FrettingCapability.guitarRelativeTracking,
        ]),
      );
    },
  );
}

const VisionPracticeCapabilities _allCapabilities = VisionPracticeCapabilities(
  fretting: <FrettingCapability>{
    FrettingCapability.handTracking,
    FrettingCapability.guitarRelativeTracking,
  },
  picking: <PickingCapability>{PickingCapability.guitarRelativeTracking},
  posture: <PostureCapability>{PostureCapability.poseTracking},
);

VisionSessionResult _session(VisionMetricState overall) => VisionSessionResult(
  session: VisionSession(
    id: VisionSessionId.create('vision-session'),
    startedAt: DateTime.utc(2026),
  ),
  endedAt: DateTime.utc(2026, 1, 1, 0, 1),
  endReason: VisionSessionEndReason.explicitStop,
  qualitySummary: VisionQualitySummary.fromFrames(<VisionFrameQuality>[
    VisionFrameQuality(
      thresholdsVersion: 'test-v1',
      framing: VisionMetricState.good,
      lighting: VisionLighting.good,
      blur: VisionMetricState.good,
      stability: VisionMetricState.good,
      roiCoverage: VisionMetricState.good,
      overall: overall,
      meanLuminance: 100,
      highlightClippingRatio: 0,
      shadowClippingRatio: 0,
      sharpness: 20,
      cameraMotion: 0,
      roiCoverageRatio: 1,
    ),
  ]),
  calibrationState: CalibrationLossState.tracking,
  sessionSummary: const <VisionInsight>[],
  observedFrameCount: 1,
);
