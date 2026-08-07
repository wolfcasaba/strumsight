// E05-R12 — RecordedHandLandmarkProvider (fixture adapter, CI-út).
//
// A CI a `RecordedHandLandmarkProvider`-t futtatja (ADR 0185 §Következmények
// 2. pont — a natív inference-t a CI sosem követeli). A fixture-ek az
// E05-R12 §6 mátrix celláit fedik: 0/1/2/>2 kéz, illetve egy
// explicit-failure cella a provider-API hibaútját mutatja.
//
// Minden fixture a domain saját `HandLandmarkId` topológiáját használja
// (21 pont), NEM provider-indexet.

library;

import 'dart:collection';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/vision/data/landmarks/hand_landmark_provider.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_landmarks.dart';

const _defaultModelId = 'hand_landmarker';
const _defaultModelVersion = '1.0.0';

/// A provider that returns a fixed, pre-recorded `HandLandmarkResult` for
/// every `infer` call. The four built-in factories cover the §6 hand-count
/// matrix and the §6 failure-path cell.
final class RecordedHandLandmarkProvider implements HandLandmarkProvider {
  RecordedHandLandmarkProvider({
    required this.modelId,
    required this.modelVersion,
    required this.produce,
  });

  @override
  final String modelId;
  @override
  final String modelVersion;
  final HandLandmarkResult Function(VisionImage image) produce;

  bool _initialized = false;
  bool _closed = false;

  /// One hand, full 21-point topology — the canonical mapping-test fixture.
  factory RecordedHandLandmarkProvider.fixtureSingleHand() =>
      RecordedHandLandmarkProvider(
        modelId: _defaultModelId,
        modelVersion: _defaultModelVersion,
        produce: (image) {
          final landmarks = <HandLandmarkId, HandLandmarkPoint>{};
          for (final id in HandLandmarkId.values) {
            final index = id.index;
            // Deterministic, id-derived coordinates so the mapping test
            // also implicitly verifies that no two IDs collapse.
            landmarks[id] = HandLandmarkPoint(
              x: ((index * 17) % 100) / 100,
              y: ((index * 31) % 100) / 100,
              z: ((index * 11) % 50) / 100 - 0.25,
              visibility: 0.9 - (index % 5) * 0.05,
            );
          }
          return HandLandmarkResult(
            timestampUs: image.timestamp.microsecondsSinceSessionStart,
            observability: HandLandmarkObservability.one,
            hands: <HandObservation>[
              HandObservation(
                handedness: Handedness.right,
                landmarks: UnmodifiableMapView(landmarks),
                confidence: 0.95,
              ),
            ],
          );
        },
      );

  /// Zero hands detected — must yield `notObservable`, no fake fill.
  factory RecordedHandLandmarkProvider.fixtureZeroHands() =>
      RecordedHandLandmarkProvider(
        modelId: _defaultModelId,
        modelVersion: _defaultModelVersion,
        produce: (image) => HandLandmarkResult.empty(
          timestampUs: image.timestamp.microsecondsSinceSessionStart,
          observability: HandLandmarkObservability.notObservable,
        ),
      );

  /// Two hands — left + right, both 21 points. Exercises the
  /// two-handed track-marking cell.
  factory RecordedHandLandmarkProvider.fixtureTwoHands() =>
      RecordedHandLandmarkProvider(
        modelId: _defaultModelId,
        modelVersion: _defaultModelVersion,
        produce: (image) {
          HandObservation handOf(Handedness handedness, double offsetX) {
            final landmarks = <HandLandmarkId, HandLandmarkPoint>{};
            for (final id in HandLandmarkId.values) {
              final index = id.index;
              landmarks[id] = HandLandmarkPoint(
                x: ((index * 17) % 100) / 100 + offsetX,
                y: ((index * 31) % 100) / 100,
                z: ((index * 11) % 50) / 100 - 0.25,
                visibility: 0.85,
              );
            }
            return HandObservation(
              handedness: handedness,
              landmarks: UnmodifiableMapView(landmarks),
              confidence: 0.9,
            );
          }

          return HandLandmarkResult(
            timestampUs: image.timestamp.microsecondsSinceSessionStart,
            observability: HandLandmarkObservability.two,
            hands: <HandObservation>[
              handOf(Handedness.left, 0),
              handOf(Handedness.right, 0.01),
            ],
          );
        },
      );

  /// Three detected hands — must be truncated to two without crashing
  /// (brief §6 >2 cell).
  factory RecordedHandLandmarkProvider.fixtureManyHands() =>
      RecordedHandLandmarkProvider(
        modelId: _defaultModelId,
        modelVersion: _defaultModelVersion,
        produce: (image) {
          HandObservation handOf(Handedness handedness) {
            final landmarks = <HandLandmarkId, HandLandmarkPoint>{};
            for (final id in HandLandmarkId.values) {
              landmarks[id] = HandLandmarkPoint(
                x: ((id.index * 17) % 100) / 100,
                y: ((id.index * 31) % 100) / 100,
                z: 0,
                visibility: 0.8,
              );
            }
            return HandObservation(
              handedness: handedness,
              landmarks: UnmodifiableMapView(landmarks),
              confidence: 0.7,
            );
          }

          // Truncate to the first two — provider-index agnostic, all three
          // carry the full 21-point topology but only the first two
          // survive.
          final all = <HandObservation>[
            handOf(Handedness.left),
            handOf(Handedness.right),
            handOf(Handedness.right),
          ];
          return HandLandmarkResult(
            timestampUs: image.timestamp.microsecondsSinceSessionStart,
            observability: HandLandmarkObservability.two,
            hands: all.take(2).toList(growable: false),
          );
        },
      );

  /// Failure-path cell — returns `AppResult.failure(<code>)` so the
  /// contract surface for `infer` failures is also tested.
  factory RecordedHandLandmarkProvider.fixtureFailure({required String code}) =>
      RecordedHandLandmarkProvider(
        modelId: _defaultModelId,
        modelVersion: _defaultModelVersion,
        produce: (image) => throw StateError(
          'RecordedHandLandmarkProvider.fixtureFailure must be intercepted '
          'by infer() — production path does not throw.',
        ),
      ).._failureCode = code;

  String? _failureCode;

  @override
  Future<AppResult<void>> initialize(HandModelConfig config) async {
    _initialized = true;
    return AppResult<void>.success(null);
  }

  @override
  Future<AppResult<HandLandmarkResult>> infer(VisionImage image) async {
    if (_closed) {
      return AppResult<HandLandmarkResult>.failure(
        const MlFailure(code: FailureCode.mlModelLoad, retryable: false),
      );
    }
    if (!_initialized) {
      return AppResult<HandLandmarkResult>.failure(
        const MlFailure(code: FailureCode.mlModelLoad, retryable: true),
      );
    }
    final failureCode = _failureCode;
    if (failureCode != null) {
      return AppResult<HandLandmarkResult>.failure(
        MlFailure(code: failureCode, retryable: false),
      );
    }
    return AppResult<HandLandmarkResult>.success(produce(image));
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}
