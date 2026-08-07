// E05-R14 — PoseLandmarkProvider kontraktus + cadence-szabályozás
// (ADR 0186 §Döntés 3–4, kör-brief §5.3–§5.4).
//
// A bemenet-típusok (`VisionImage`, `HandLandmarkTimestamp`,
// `VisionDeviceTier`) a kéz-oldali `hand_landmark_provider.dart`-ból
// IMPORTÁLTAK, nem újradefiniáltak (ADR 0186 §Döntés 4): egy kameraframe
// mindkét pipeline-t táplálhatja.
//
// A pose a kéz-modellnél RITKÁBBAN fut: a `CadenceLimitedPoseLandmarkProvider`
// wrapper (a `MonotonicHandLandmarkProvider` wrapper-mintáját követve) minden
// N. hívást engedi le a delegálthoz.

library;

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/vision/data/landmarks/hand_landmark_provider.dart'
    show VisionDeviceTier, VisionImage;
import 'package:strumsight/features/vision/domain/landmarks/pose_landmarks.dart';

/// Per-model configuration for a pose provider.
///
/// `modelId` selects the registered `vision_models` entry in the manifest.
final class PoseModelConfig {
  const PoseModelConfig({
    this.modelId = 'pose_landmarker',
    this.modelVersion = '1.0.0',
    this.minimumDeviceTier = VisionDeviceTier.basic,
    this.timeout = const Duration(seconds: 10),
  });

  final String modelId;
  final String modelVersion;
  final VisionDeviceTier minimumDeviceTier;
  final Duration timeout;
}

/// The provider-independent contract every pose-landmark adapter satisfies.
///
/// One `infer` call returns the WHOLE retained upper body (unlike the hand
/// contract, which is per-hand).
abstract interface class PoseLandmarkProvider {
  String get modelId;

  String get modelVersion;

  /// Loads and validates the model asset. Idempotent.
  Future<AppResult<void>> initialize(PoseModelConfig config);

  /// Runs one inference.
  Future<AppResult<PoseLandmarks>> infer(VisionImage image);

  /// Releases all resources. Safe to call multiple times.
  Future<void> close();
}

/// The default pose cadence: one pose inference per 6 camera frames — a
/// fraction of the hand model's per-frame rate (kör-brief §5.4).
const int defaultPoseCadenceEveryNthFrame = 6;

/// A [PoseLandmarkProvider] wrapper that only forwards every Nth `infer`
/// call to the delegate, so the pose model runs at a fraction of the hand
/// model's cadence.
///
/// Skipped calls return the most recent delegate result (or a
/// `notObservable` result stamped with the skipped frame's timestamp when
/// nothing has been produced yet) — never a failure. Changing
/// [everyNthFrame] takes effect on the very next call: the phase counter is
/// restarted so the new ratio is not delayed by the old one.
final class CadenceLimitedPoseLandmarkProvider implements PoseLandmarkProvider {
  CadenceLimitedPoseLandmarkProvider(
    this._delegate, {
    int everyNthFrame = defaultPoseCadenceEveryNthFrame,
  }) : _everyNthFrame = everyNthFrame {
    _assertPositive(everyNthFrame);
  }

  final PoseLandmarkProvider _delegate;

  int _everyNthFrame;
  int _frameIndex = 0;
  int _delegatedCount = 0;
  int _skippedCount = 0;
  PoseLandmarks? _lastResult;

  /// How many camera frames pass per delegated pose inference.
  int get everyNthFrame => _everyNthFrame;

  set everyNthFrame(int value) {
    _assertPositive(value);
    _everyNthFrame = value;
    // Restart the phase so the new ratio applies from the next call.
    _frameIndex = 0;
  }

  /// How many calls actually reached the delegate.
  int get delegatedCount => _delegatedCount;

  /// How many calls were skipped by the cadence gate.
  int get skippedCount => _skippedCount;

  @override
  String get modelId => _delegate.modelId;

  @override
  String get modelVersion => _delegate.modelVersion;

  @override
  Future<AppResult<void>> initialize(PoseModelConfig config) =>
      _delegate.initialize(config);

  @override
  Future<AppResult<PoseLandmarks>> infer(VisionImage image) async {
    final shouldRun = _frameIndex % _everyNthFrame == 0;
    _frameIndex += 1;
    if (!shouldRun) {
      _skippedCount += 1;
      final last = _lastResult;
      return AppResult<PoseLandmarks>.success(
        last ??
            PoseLandmarks.notObservable(
              timestampUs: image.timestamp.microsecondsSinceSessionStart,
            ),
      );
    }
    _delegatedCount += 1;
    final result = await _delegate.infer(image);
    return result.fold(
      onSuccess: (value) {
        _lastResult = value;
        return AppResult<PoseLandmarks>.success(value);
      },
      onFailure: (AppFailure error) => AppResult<PoseLandmarks>.failure(error),
    );
  }

  @override
  Future<void> close() => _delegate.close();

  static void _assertPositive(int value) {
    if (value < 1) {
      throw ArgumentError.value(
        value,
        'everyNthFrame',
        'Pose cadence must be at least 1.',
      );
    }
  }
}

/// Builds the cadence-limited pose provider, or returns `null` when pose
/// tracking is disabled.
///
/// The flag (`FeatureFlags.visionPoseTrackingEnabled`, default `false`) is
/// passed in as a plain argument: this factory is the machine-checked gate
/// that no pose provider is instantiated while pose tracking is off, and it
/// touches nothing on the hand pipeline (kör-brief §5.3, §0.0 R7). The
/// Riverpod wiring that reads the flag is a later round (E05-R24).
PoseLandmarkProvider? createPoseLandmarkProvider({
  required bool poseTrackingEnabled,
  required PoseLandmarkProvider Function() build,
  int everyNthFrame = defaultPoseCadenceEveryNthFrame,
}) {
  if (!poseTrackingEnabled) return null;
  return CadenceLimitedPoseLandmarkProvider(
    build(),
    everyNthFrame: everyNthFrame,
  );
}
