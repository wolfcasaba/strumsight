// E05-R12 §6 — HandLandmarkProvider mapping / hand-count / timestamp mátrix.
//
// Három mátrix:
//   1. mapping (rögzített provider-kimenet → mind a 21 StrumSight ID),
//   2. kéz-szám (0/1/2/>2 — a 0 notObservable, >2 kontrolláltan vágott),
//   3. timestamp (növekvő / azonos / csökkenő — a csökkenő eldobódik, számláló méri).
//
// A `RecordedHandLandmarkProvider` a fixture-út (CI-ben ez fut, ADR 0185
// §Következmények 2. pont); a `MonotonicHandLandmarkProvider` a wrapping
// timestamp-gate.

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/features/vision/data/landmarks/hand_landmark_provider.dart';
import 'package:strumsight/features/vision/data/landmarks/recorded_hand_landmark_provider.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_landmarks.dart';

const _config = HandModelConfig(
  modelId: 'hand_landmarker',
  modelVersion: '1.0.0',
);

VisionImage _imageAt(int microseconds) => VisionImage(
  width: 256,
  height: 256,
  pixelFormat: VisionPixelFormat.rgb888,
  bytes: List<int>.filled(256 * 256 * 3, 0),
  timestamp: HandLandmarkTimestamp(microseconds),
  sourceRect: NormalizedRect.full(),
  mirror: false,
);

void main() {
  group('RecordedHandLandmarkProvider — 21-point mapping', () {
    test(
      'every StrumSight landmark ID is queryable from a single-hand result',
      () async {
        final provider = RecordedHandLandmarkProvider.fixtureSingleHand();
        final init = await provider.initialize(_config);
        expect(init.isSuccess, isTrue);

        final result = await provider.infer(_imageAt(1000));
        expect(result.isSuccess, isTrue);
        final value = result.valueOrNull!;
        expect(value.observability, HandLandmarkObservability.one);
        expect(value.hands, hasLength(1));

        final hand = value.hands.single;
        for (final id in HandLandmarkId.values) {
          expect(
            hand.byId(id),
            isNotNull,
            reason:
                'StrumSight landmark $id must be present in the mapped '
                'fixture (21-point topology)',
          );
        }
      },
    );
  });

  group('Hand-count matrix — 0/1/2/>2', () {
    test('zero hands → observability notObservable, no fake fill', () async {
      final provider = RecordedHandLandmarkProvider.fixtureZeroHands();
      await provider.initialize(_config);

      final result = await provider.infer(_imageAt(2000));
      expect(result.isSuccess, isTrue);
      final value = result.valueOrNull!;
      expect(value.hands, isEmpty);
      expect(value.observability, HandLandmarkObservability.notObservable);
    });

    test('one hand → observability one', () async {
      final provider = RecordedHandLandmarkProvider.fixtureSingleHand();
      await provider.initialize(_config);

      final result = await provider.infer(_imageAt(3000));
      final value = result.valueOrNull!;
      expect(value.hands, hasLength(1));
      expect(value.observability, HandLandmarkObservability.one);
    });

    test('two hands → observability two, each hand track-marked', () async {
      final provider = RecordedHandLandmarkProvider.fixtureTwoHands();
      await provider.initialize(_config);

      final result = await provider.infer(_imageAt(4000));
      final value = result.valueOrNull!;
      expect(value.hands, hasLength(2));
      expect(value.observability, HandLandmarkObservability.two);
      expect(
        value.hands.map((hand) => hand.handedness).toSet(),
        containsAll(<Handedness>[Handedness.left, Handedness.right]),
      );
    });

    test('more than two hands → truncated to two without crashing', () async {
      final provider = RecordedHandLandmarkProvider.fixtureManyHands();
      await provider.initialize(_config);

      final result = await provider.infer(_imageAt(5000));
      expect(result.isSuccess, isTrue);
      final value = result.valueOrNull!;
      expect(value.hands.length, lessThanOrEqualTo(2));
      expect(value.observability, HandLandmarkObservability.two);
    });
  });

  group('Timestamp matrix — monotonic gate', () {
    test('increasing timestamps: every result passes through', () async {
      final base = RecordedHandLandmarkProvider.fixtureSingleHand();
      await base.initialize(_config);
      final gated = MonotonicHandLandmarkProvider(base);

      for (final t in <int>[1000, 2000, 3000, 4000]) {
        final result = await gated.infer(_imageAt(t));
        expect(result.isSuccess, isTrue, reason: 't=$t should pass');
      }
      expect(gated.droppedTimestampCount, 0);
    });

    test('equal timestamps: passes through (not a decrease)', () async {
      final base = RecordedHandLandmarkProvider.fixtureSingleHand();
      await base.initialize(_config);
      final gated = MonotonicHandLandmarkProvider(base);

      for (final t in <int>[1000, 1000, 1000]) {
        final result = await gated.infer(_imageAt(t));
        expect(result.isSuccess, isTrue);
      }
      expect(gated.droppedTimestampCount, 0);
    });

    test('decreasing timestamp: dropped, counter increments', () async {
      final base = RecordedHandLandmarkProvider.fixtureSingleHand();
      await base.initialize(_config);
      final gated = MonotonicHandLandmarkProvider(base);

      await gated.infer(_imageAt(3000));
      await gated.infer(_imageAt(4000));
      final dropped = await gated.infer(_imageAt(2500));
      final trailing = await gated.infer(_imageAt(5000));

      expect(dropped.isSuccess, isTrue);
      expect(trailing.isSuccess, isTrue);
      expect(gated.droppedTimestampCount, 1);

      // After the dropped call, monotonic gate's lastSeen must NOT regress.
      final peek = gated.lastAcceptedTimestampUs;
      expect(peek, 5000);
    });

    test('decreasing before any accept: still dropped, not crash', () async {
      final base = RecordedHandLandmarkProvider.fixtureSingleHand();
      await base.initialize(_config);
      final gated = MonotonicHandLandmarkProvider(base);

      final first = await gated.infer(_imageAt(500));
      final dropped = await gated.infer(_imageAt(100));
      expect(first.isSuccess, isTrue);
      expect(dropped.isSuccess, isTrue);
      expect(gated.droppedTimestampCount, 1);
    });
  });

  group('HandLandmarkProvider — common contract surface', () {
    test('initialize twice is idempotent (returns success)', () async {
      final provider = RecordedHandLandmarkProvider.fixtureSingleHand();
      final first = await provider.initialize(_config);
      final second = await provider.initialize(_config);
      expect(first.isSuccess, isTrue);
      expect(second.isSuccess, isTrue);
    });

    test('close completes without throwing', () async {
      final provider = RecordedHandLandmarkProvider.fixtureSingleHand();
      await provider.initialize(_config);
      await provider.close();
    });
  });

  // Sanity: AppResult.failure is the failure path used by the production
  // adapter (`NativeHandLandmarkProvider` returns AppResult.failure when the
  // asset is deferred). This test ensures the contract carries it.
  test('AppResult.failure carries a stable code through infer()', () async {
    final provider = RecordedHandLandmarkProvider.fixtureFailure(
      code: 'ml.model_load',
    );
    await provider.initialize(_config);
    final result = await provider.infer(_imageAt(7000));
    expect(result.isFailure, isTrue);
    expect(result.failureOrNull!.code, 'ml.model_load');
  });
}
