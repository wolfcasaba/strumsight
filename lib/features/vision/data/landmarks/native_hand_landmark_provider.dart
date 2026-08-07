// E05-R12 — NativeHandLandmarkProvider (production adapter, deferred).
//
// EBBEN A KÖRBEN fail-closed `unavailable` (ADR 0185 §Döntés 2 —
// eldöntötte az orchestrátor a pre-flightban, nem az implementer
// választása). A production asset beszerzése és a natív bekötés
// (`tflite_flutter` + MediaPipe Hands, ADR 0185 §Döntés 1) egy
// JÖVŐBELI aktiváló kör dolga.
//
// A mostani adapter három dolgot csinál:
//   1. Az `initialize()` a `VisionModelManifest` `vision_models` bejegyzését
//      ellenőrzi (checksum + output_schema + licenc), és hiba esetén
//      `AppResult.failure(MlFailure)`-t ad vissza. Ez a §5.4 manifest-őr
//      initkori ellenőrzése.
//   2. Ha a manifest rendben van, de a bejegyzés `status = "deferred"`,
//      `initialize()` `AppResult.failure(MlFailure(code: mlModelLoad))`-t
//      ad — capability `unavailable` (brief §5.5, §6).
//   3. Az `infer()` soha nem hívódik meg initialize-siker esetén (az
//      alkalmazás-réteg capability-gate-en át sem jut), ezért itt
//      kivételt dobunk, ha mégis hívnák.

library;

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/ml/vision_model_manifest.dart';
import 'package:strumsight/features/vision/data/landmarks/hand_landmark_provider.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_landmarks.dart';

/// The production hand-landmark provider. In this round it is a
/// fail-closed stub: every `initialize` returns an `AppResult.failure`
/// with `FailureCode.mlModelLoad` once the manifest has been validated,
/// because the model asset is `status = "deferred"` (ADR 0185 §Döntés 2).
final class NativeHandLandmarkProvider implements HandLandmarkProvider {
  NativeHandLandmarkProvider({required VisionModelManifestReader manifest})
    : manifestReader = manifest;

  /// Reads and validates the on-disk vision manifest. Injected so the
  /// provider can be unit-tested without a real file system.
  final VisionModelManifestReader manifestReader;

  VisionModelEntry? _entry;
  bool _closed = false;

  @override
  String get modelId => _entry?.modelId ?? 'hand_landmarker';

  @override
  String get modelVersion => _entry?.version ?? '1.0.0';

  @override
  Future<AppResult<void>> initialize(HandModelConfig config) async {
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
    if (entry.status == VisionModelStatus.deferred) {
      return AppResult<void>.failure(
        MlFailure(
          code: FailureCode.mlModelLoad,
          retryable: false,
          cause:
              'vision model ${entry.modelId}@${entry.version} is deferred '
              '(asset not shipped in this round, ADR 0185)',
        ),
      );
    }
    _entry = entry;
    return AppResult<void>.success(null);
  }

  @override
  Future<AppResult<HandLandmarkResult>> infer(VisionImage image) async {
    if (_entry == null) {
      return AppResult<HandLandmarkResult>.failure(
        const MlFailure(code: FailureCode.mlModelLoad, retryable: false),
      );
    }
    // Native inference is not wired in this round. Should a caller bypass
    // the capability gate, this is the explicit failure.
    return AppResult<HandLandmarkResult>.failure(
      const MlFailure(code: FailureCode.mlInference, retryable: false),
    );
  }

  @override
  Future<void> close() async {
    _closed = true;
    _entry = null;
  }
}
