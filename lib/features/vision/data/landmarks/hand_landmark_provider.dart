// E05-R12 — HandLandmarkProvider contract + VisionImage input shape.
//
// Az SDD §15.1 szerinti providerfüggetlen kontraktus:
//   - `infer()` hívásonkénti, Future-alapú (NEM Stream, brief §0.0 R5);
//   - a domain NEM függ a provider natív típusától (ADR 0180 §3, ADR 0185
//     §Döntés 2);
//   - `VisionImage` (SDD §15.1 paraméter) itt van definiálva, a meglévő R06
//     `CameraFrame` pixel-buffere + R07 `NormalizedRect` normalizált tere
//     fölött (brief §0.0 R4).
//
// A `MonotonicHandLandmarkProvider` a timestamp-monotonitás őre: a domain
// hívója ezen a wrapperen át éri el a providert, így a csökkenő timestamp
// eldobódik és számláló méri (brief §5.3, §6).

library;

import 'dart:typed_data';

import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_landmarks.dart';

/// Pixel layout of a `VisionImage`.
///
/// Mirrors the camera-platform-neutral subset the model needs; plugin-
/// specific image types never cross this boundary.
enum VisionPixelFormat { rgb888, rgba8888, grayscale }

/// The input to a hand-landmark `infer` call.
///
/// `bytes` is a defensive copy of the source pixel buffer; the caller may
/// release the original `CameraFrame` immediately after constructing this
/// object. `timestamp` is the microseconds-since-session-start monotonic
/// timestamp of the source frame, propagated into the resulting
/// `HandLandmarkResult.timestampUs` unchanged.
final class VisionImage {
  VisionImage({
    required this.width,
    required this.height,
    required this.pixelFormat,
    required List<int> bytes,
    required this.timestamp,
    required this.sourceRect,
    required this.mirror,
  }) : bytes = Uint8List.fromList(bytes) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('VisionImage dimensions must be positive.');
    }
    if (timestamp.microsecondsSinceSessionStart < 0) {
      throw ArgumentError.value(
        timestamp,
        'timestamp',
        'Must be non-negative.',
      );
    }
  }

  final int width;
  final int height;
  final VisionPixelFormat pixelFormat;
  final Uint8List bytes;

  /// Monotonic source-frame timestamp — propagated into the result so the
  /// `MonotonicHandLandmarkProvider` wrapper can enforce ordering.
  final HandLandmarkTimestamp timestamp;

  /// Region of interest in the non-mirrored normalized frame space.
  final NormalizedRect sourceRect;

  /// Whether the source frame was horizontally mirrored (R07 metadata). The
  /// model input is non-mirrored; the caller must pre-normalize.
  final bool mirror;
}

/// Monotonic microseconds-since-session-start timestamp for vision inputs.
///
/// Defined here (not aliased to `CameraTimestamp`) so the vision domain
/// does not pull in the camera module. Same shape, same invariants.
final class HandLandmarkTimestamp implements Comparable<HandLandmarkTimestamp> {
  const HandLandmarkTimestamp(this.microsecondsSinceSessionStart)
    : assert(microsecondsSinceSessionStart >= 0);

  final int microsecondsSinceSessionStart;

  @override
  int compareTo(HandLandmarkTimestamp other) => microsecondsSinceSessionStart
      .compareTo(other.microsecondsSinceSessionStart);

  @override
  bool operator ==(Object other) =>
      other is HandLandmarkTimestamp &&
      other.microsecondsSinceSessionStart == microsecondsSinceSessionStart;

  @override
  int get hashCode => microsecondsSinceSessionStart.hashCode;

  @override
  String toString() =>
      'HandLandmarkTimestamp($microsecondsSinceSessionStart µs)';
}

/// Per-model configuration the caller can tune at initialization time.
///
/// `modelId` selects the registered model entry in `VisionModelManifest`;
/// `minimumDeviceTier` is enforced by the production adapter at boot time.
final class HandModelConfig {
  const HandModelConfig({
    required this.modelId,
    required this.modelVersion,
    this.minimumDeviceTier = VisionDeviceTier.basic,
    this.timeout = const Duration(seconds: 10),
  });

  final String modelId;
  final String modelVersion;
  final VisionDeviceTier minimumDeviceTier;
  final Duration timeout;
}

/// Minimal device capability classes the production adapter uses to gate
/// deferred asset activation. The mapping is defined by the model card
/// (ADR 0185 Döntés 5); the domain value is here so the provider contract
/// is self-contained.
enum VisionDeviceTier { basic, mid, flagship }

/// The provider-independent contract every hand-landmark adapter must
/// satisfy.
///
/// Implementations live in `data/landmarks/` and are swapped by the
/// application layer (Riverpod provider). The contract is intentionally
/// minimal so the production adapter (`NativeHandLandmarkProvider`) and
/// the CI-recorded adapter (`RecordedHandLandmarkProvider`) can share it.
abstract interface class HandLandmarkProvider {
  /// The model ID this provider was built against (matches the manifest).
  String get modelId;

  /// The model schema version this provider expects.
  String get modelVersion;

  /// Loads and validates the model asset. Idempotent — a second call
  /// succeeds without re-loading.
  Future<AppResult<void>> initialize(HandModelConfig config);

  /// Runs one inference. MUST be safe to call concurrently only when the
  /// implementation documents it; the default contract is single-flight.
  Future<AppResult<HandLandmarkResult>> infer(VisionImage image);

  /// Releases all native resources. Safe to call multiple times.
  Future<void> close();
}

/// A `HandLandmarkProvider` wrapper that drops results carrying a
/// `timestamp` lower than the most recent accepted one.
///
/// This is a wrapper, not a contract method, because the underlying
/// provider is stateless across calls (SDD §15.1) — ordering is a
/// transport-level concern (brief §5.3).
///
/// On a dropped call the wrapper returns the previous accepted result
/// (so the caller still sees a successful `AppResult.success`), and
/// increments [droppedTimestampCount]. [lastAcceptedTimestampUs] reflects
/// the most recent accepted microseconds — it never regresses.
final class MonotonicHandLandmarkProvider implements HandLandmarkProvider {
  MonotonicHandLandmarkProvider(this._delegate);

  final HandLandmarkProvider _delegate;

  int _lastAcceptedUs = -1;
  HandLandmarkResult? _lastAcceptedResult;
  int _dropped = 0;

  /// How many calls were dropped because their timestamp regressed.
  int get droppedTimestampCount => _dropped;

  /// Most recent accepted timestamp in microseconds, or `-1` if none.
  int get lastAcceptedTimestampUs => _lastAcceptedUs;

  @override
  String get modelId => _delegate.modelId;

  @override
  String get modelVersion => _delegate.modelVersion;

  @override
  Future<AppResult<void>> initialize(HandModelConfig config) =>
      _delegate.initialize(config);

  @override
  Future<AppResult<HandLandmarkResult>> infer(VisionImage image) async {
    final result = await _delegate.infer(image);
    return result.fold(
      onSuccess: (value) {
        final ts = value.timestampUs;
        if (_lastAcceptedUs >= 0 && ts < _lastAcceptedUs) {
          _dropped += 1;
          return AppResult<HandLandmarkResult>.success(
            _lastAcceptedResult ?? value,
          );
        }
        _lastAcceptedUs = ts;
        _lastAcceptedResult = value;
        return AppResult<HandLandmarkResult>.success(value);
      },
      onFailure: (AppFailure error) =>
          AppResult<HandLandmarkResult>.failure(error),
    );
  }

  @override
  Future<void> close() => _delegate.close();
}
