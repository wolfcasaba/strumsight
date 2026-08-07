// E05-R14 §6 — PoseLandmarkProvider mapping / cadence / kikapcsolás mátrix.
//
// Négy mérce:
//   1. mapping: a rögzített nyers kimenet → pontosan a 9 megtartott ID;
//   2. cadence: N frame-re a delegált pose-hívások száma a konfigurált arány
//      szerinti, és az arány állítása AZONNAL érvényesül (nem újraindítás után);
//   3. kikapcsolás: `visionPoseTrackingEnabled = false` → a pose provider NEM
//      példányosul, a kéz-pipeline érintetlen;
//   4. a production adapter fail-closed `unavailable` a deferred manifesten.

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/ml/vision_model_manifest.dart';
import 'package:strumsight/features/vision/data/landmarks/hand_landmark_provider.dart';
import 'package:strumsight/features/vision/data/landmarks/native_pose_landmark_provider.dart';
import 'package:strumsight/features/vision/data/landmarks/pose_landmark_provider.dart';
import 'package:strumsight/features/vision/data/landmarks/recorded_hand_landmark_provider.dart';
import 'package:strumsight/features/vision/data/landmarks/recorded_pose_landmark_provider.dart';
import 'package:strumsight/features/vision/domain/landmarks/pose_landmarks.dart';

VisionImage _imageAt(int microseconds) => VisionImage(
  width: 64,
  height: 64,
  pixelFormat: VisionPixelFormat.rgb888,
  bytes: List<int>.filled(8, 0),
  timestamp: HandLandmarkTimestamp(microseconds),
  sourceRect: NormalizedRect.full(),
  mirror: false,
);

/// A reader that returns a caller-supplied report — no disk access.
final class _StubManifestReader implements VisionModelManifestReader {
  _StubManifestReader(this._report);

  final VisionModelManifestReport _report;

  @override
  Future<VisionModelManifestReport> read() async => _report;
}

VisionModelEntry _poseEntry({
  required VisionModelStatus status,
  String outputSchema = poseLandmarksOutputSchema,
}) => VisionModelEntry(
  modelId: 'pose_landmarker',
  version: '1.0.0',
  path: 'assets/ml/pose_landmarker_deferred.tflite',
  sha256: 'b' * 64,
  status: status,
  inputShape: const [256, 256, 3],
  outputSchema: outputSchema,
  licenseSpdx: 'Apache-2.0',
  licenseName: 'MediaPipe Pose',
  minimumDeviceTier: 'basic',
  evaluationReport: 'docs/eval/vision/pose_landmarker.md',
);

void main() {
  group('RecordedPoseLandmarkProvider — 9-point mapping', () {
    test(
      'every retained ID is queryable and face points are dropped',
      () async {
        final provider = RecordedPoseLandmarkProvider.fixtureUpperBody();
        expect(
          (await provider.initialize(const PoseModelConfig())).isSuccess,
          isTrue,
        );

        final result = await provider.infer(_imageAt(1000));
        expect(result.isSuccess, isTrue);
        final pose = result.valueOrNull!;
        expect(pose.observability, PoseObservability.observed);
        expect(pose.timestampUs, 1000);
        for (final id in PoseLandmarkId.values) {
          expect(
            pose.byId(id),
            isNotNull,
            reason: 'retained ID $id is missing',
          );
        }
        expect(pose.count, PoseLandmarkId.values.length);
      },
    );

    test('an empty payload is notObservable, not a failure', () async {
      final provider = RecordedPoseLandmarkProvider.fixtureNoPose();
      await provider.initialize(const PoseModelConfig());
      final result = await provider.infer(_imageAt(10));
      expect(result.isSuccess, isTrue);
      expect(
        result.valueOrNull!.observability,
        PoseObservability.notObservable,
      );
    });

    test('the failure fixture surfaces AppResult.failure', () async {
      final provider = RecordedPoseLandmarkProvider.fixtureFailure(
        code: FailureCode.mlInference,
      );
      await provider.initialize(const PoseModelConfig());
      final result = await provider.infer(_imageAt(10));
      expect(result.isSuccess, isFalse);
    });
  });

  group('CadenceLimitedPoseLandmarkProvider — cadence ratio', () {
    test('12 frames at 1:6 delegate exactly 2 pose inferences', () async {
      final delegate = RecordedPoseLandmarkProvider.fixtureUpperBody();
      final cadence = CadenceLimitedPoseLandmarkProvider(
        delegate,
        everyNthFrame: 6,
      );
      await cadence.initialize(const PoseModelConfig());
      for (var frame = 0; frame < 12; frame++) {
        final result = await cadence.infer(_imageAt(frame * 1000));
        expect(result.isSuccess, isTrue);
      }
      expect(cadence.delegatedCount, 2);
      expect(cadence.skippedCount, 10);
    });

    test('12 frames at 1:3 delegate exactly 4 pose inferences', () async {
      final cadence = CadenceLimitedPoseLandmarkProvider(
        RecordedPoseLandmarkProvider.fixtureUpperBody(),
        everyNthFrame: 3,
      );
      await cadence.initialize(const PoseModelConfig());
      for (var frame = 0; frame < 12; frame++) {
        await cadence.infer(_imageAt(frame * 1000));
      }
      expect(cadence.delegatedCount, 4);
    });

    test('the default cadence is a fraction of the hand rate', () {
      expect(defaultPoseCadenceEveryNthFrame, greaterThan(1));
      final cadence = CadenceLimitedPoseLandmarkProvider(
        RecordedPoseLandmarkProvider.fixtureUpperBody(),
      );
      expect(cadence.everyNthFrame, defaultPoseCadenceEveryNthFrame);
    });

    test('changing the ratio takes effect on the very next call', () async {
      final cadence = CadenceLimitedPoseLandmarkProvider(
        RecordedPoseLandmarkProvider.fixtureUpperBody(),
        everyNthFrame: 6,
      );
      await cadence.initialize(const PoseModelConfig());
      for (var frame = 0; frame < 6; frame++) {
        await cadence.infer(_imageAt(frame * 1000));
      }
      expect(cadence.delegatedCount, 1);

      cadence.everyNthFrame = 2;
      // Six more frames at 1:2 → three more delegated calls, starting with
      // the FIRST call after the change (no restart required).
      final before = cadence.delegatedCount;
      await cadence.infer(_imageAt(6000));
      expect(
        cadence.delegatedCount,
        before + 1,
        reason: 'the new ratio must apply immediately, not after a restart',
      );
      for (var frame = 7; frame < 12; frame++) {
        await cadence.infer(_imageAt(frame * 1000));
      }
      expect(cadence.delegatedCount, 4);
    });

    test(
      'skipped frames return the last accepted pose, never a failure',
      () async {
        final cadence = CadenceLimitedPoseLandmarkProvider(
          RecordedPoseLandmarkProvider.fixtureUpperBody(),
          everyNthFrame: 4,
        );
        await cadence.initialize(const PoseModelConfig());
        final first = (await cadence.infer(_imageAt(0))).valueOrNull!;
        final skipped = (await cadence.infer(_imageAt(1000))).valueOrNull!;
        expect(skipped.timestampUs, first.timestampUs);
        expect(cadence.delegatedCount, 1);
      },
    );

    test('a cadence below 1 is rejected', () {
      expect(
        () => CadenceLimitedPoseLandmarkProvider(
          RecordedPoseLandmarkProvider.fixtureNoPose(),
          everyNthFrame: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('createPoseLandmarkProvider — feature-flag gate', () {
    test('disabled flag → no pose provider is instantiated at all', () {
      var built = 0;
      final provider = createPoseLandmarkProvider(
        poseTrackingEnabled: false,
        build: () {
          built += 1;
          return RecordedPoseLandmarkProvider.fixtureUpperBody();
        },
      );
      expect(provider, isNull);
      expect(built, 0, reason: 'the delegate must not even be constructed');
    });

    test('enabled flag → a cadence-limited provider is returned', () {
      final provider = createPoseLandmarkProvider(
        poseTrackingEnabled: true,
        build: RecordedPoseLandmarkProvider.fixtureUpperBody,
      );
      expect(provider, isA<CadenceLimitedPoseLandmarkProvider>());
      expect(provider!.modelId, 'pose_landmarker');
    });

    test('the disabled pose gate leaves the hand pipeline untouched', () async {
      final poseProvider = createPoseLandmarkProvider(
        poseTrackingEnabled: false,
        build: RecordedPoseLandmarkProvider.fixtureUpperBody,
      );
      expect(poseProvider, isNull);

      final hand = RecordedHandLandmarkProvider.fixtureSingleHand();
      final init = await hand.initialize(
        const HandModelConfig(
          modelId: 'hand_landmarker',
          modelVersion: '1.0.0',
        ),
      );
      expect(init.isSuccess, isTrue);
      final handResult = await hand.infer(_imageAt(500));
      expect(handResult.isSuccess, isTrue);
      expect(handResult.valueOrNull!.hands, hasLength(1));
    });
  });

  group('NativePoseLandmarkProvider — fail-closed', () {
    test(
      'deferred manifest entry → initialize fails (capability unavailable)',
      () async {
        final provider = NativePoseLandmarkProvider(
          manifest: _StubManifestReader(
            VisionModelManifestReport(
              entries: [_poseEntry(status: VisionModelStatus.deferred)],
              issues: const [],
            ),
          ),
        );
        final result = await provider.initialize(const PoseModelConfig());
        expect(result.isSuccess, isFalse);
        expect(provider.modelId, 'pose_landmarker');
      },
    );

    test('dirty manifest → initialize fails', () async {
      final provider = NativePoseLandmarkProvider(
        manifest: _StubManifestReader(
          VisionModelManifestReport(
            entries: const [],
            issues: const ['vision_models must be a non-empty list'],
          ),
        ),
      );
      expect(
        (await provider.initialize(const PoseModelConfig())).isSuccess,
        isFalse,
      );
    });

    test('hand output_schema on the pose entry → initialize fails', () async {
      final provider = NativePoseLandmarkProvider(
        manifest: _StubManifestReader(
          VisionModelManifestReport(
            entries: [
              _poseEntry(
                status: VisionModelStatus.active,
                outputSchema: handLandmarksOutputSchema,
              ),
            ],
            issues: const [],
          ),
        ),
      );
      expect(
        (await provider.initialize(const PoseModelConfig())).isSuccess,
        isFalse,
      );
    });

    test('infer without a successful initialize fails', () async {
      final provider = NativePoseLandmarkProvider(
        manifest: _StubManifestReader(
          VisionModelManifestReport(entries: const [], issues: const []),
        ),
      );
      expect((await provider.infer(_imageAt(1))).isSuccess, isFalse);
      await provider.close();
    });
  });
}
