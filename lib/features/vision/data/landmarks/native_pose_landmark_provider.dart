// E05-R14 — NativePoseLandmarkProvider (production adapter, deferred).
//
// EBBEN A KÖRBEN fail-closed `unavailable` (ADR 0186 §Döntés 3) — pontosan a
// `NativeHandLandmarkProvider` alakját követve: init-kori manifest-validáció,
// `status = "deferred"` → `AppResult.failure`. A pose-modell binárisának
// beszerzése és a natív bekötés egy JÖVŐBELI aktiváló kör dolga.

library;

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/ml/vision_model_manifest.dart';
import 'package:strumsight/features/vision/data/landmarks/hand_landmark_provider.dart'
    show VisionImage;
import 'package:strumsight/features/vision/data/landmarks/pose_landmark_provider.dart';
import 'package:strumsight/features/vision/domain/landmarks/pose_landmarks.dart';

/// The production pose-landmark provider. In this round every `initialize`
/// fails with `FailureCode.mlModelLoad` once the manifest validates, because
/// the `pose_landmarker` entry is `status = "deferred"`.
final class NativePoseLandmarkProvider implements PoseLandmarkProvider {
  NativePoseLandmarkProvider({required VisionModelManifestReader manifest})
    : manifestReader = manifest;

  /// Reads and validates the on-disk vision manifest. Injected so the
  /// provider can be unit-tested without a real file system.
  final VisionModelManifestReader manifestReader;

  VisionModelEntry? _entry;
  bool _closed = false;

  @override
  String get modelId => _entry?.modelId ?? 'pose_landmarker';

  @override
  String get modelVersion => _entry?.version ?? '1.0.0';

  @override
  Future<AppResult<void>> initialize(PoseModelConfig config) async {
    if (_closed) {
      return AppResult<void>.failure(
        const MlFailure(code: FailureCode.mlModelLoad, retryable: false),
      );
    }
    final report = await manifestReader.read();
    if (!report.isClean) {
      return AppResult<void>.failure(
        MlFailure(
          code: FailureCode.mlModelLoad,
          retryable: false,
          cause: report.issues.join('; '),
        ),
      );
    }
    final entry = report.findById(config.modelId);
    if (entry == null) {
      return AppResult<void>.failure(
        MlFailure(
          code: FailureCode.mlModelLoad,
          retryable: false,
          cause: 'manifest does not declare modelId=${config.modelId}',
        ),
      );
    }
    if (entry.outputSchema != poseLandmarksOutputSchema) {
      return AppResult<void>.failure(
        MlFailure(
          code: FailureCode.mlModelLoad,
          retryable: false,
          cause:
              'vision model ${entry.modelId} declares output_schema '
              '"${entry.outputSchema}", expected "$poseLandmarksOutputSchema"',
        ),
      );
    }
    if (entry.status == VisionModelStatus.deferred) {
      return AppResult<void>.failure(
        MlFailure(
          code: FailureCode.mlModelLoad,
          retryable: false,
          cause:
              'vision model ${entry.modelId}@${entry.version} is deferred '
              '(asset not shipped in this round, ADR 0186)',
        ),
      );
    }
    _entry = entry;
    return AppResult<void>.success(null);
  }

  @override
  Future<AppResult<PoseLandmarks>> infer(VisionImage image) async {
    if (_entry == null) {
      return AppResult<PoseLandmarks>.failure(
        const MlFailure(code: FailureCode.mlModelLoad, retryable: false),
      );
    }
    // Native inference is not wired in this round. Should a caller bypass
    // the capability gate, this is the explicit failure.
    return AppResult<PoseLandmarks>.failure(
      const MlFailure(code: FailureCode.mlInference, retryable: false),
    );
  }

  @override
  Future<void> close() async {
    _closed = true;
    _entry = null;
  }
}
