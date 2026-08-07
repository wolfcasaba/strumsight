// E05-R12 §6 — HandLandmarks domain: 21-point topology, hand-count matrix,
// point accessor by stable StrumSight ID.
//
// A `HandObservation` a StrumSight saját `HandLandmarkId` enumjával címkézett
// 21 pontot hordoz — a provider-index szivárgása a domainbe NEM elfogadható
// (ADR 0180 §Döntés 3). A `byId` accessor a domain-szintű egyetlen lekérési
// út; ez a teszt azt méri, hogy a domain-modell az enum-ot, nem a tömbindexet
// szolgálja ki.

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_landmarks.dart';

void main() {
  group('HandLandmarkId — 21 stable StrumSight IDs', () {
    test('enumerates exactly 21 landmarks in the canonical topology', () {
      expect(HandLandmarkId.values.length, 21);
      // Canonical topology per ADR 0185 §Döntés 4 — wrist + 4 ujj × 4 ízület.
      expect(HandLandmarkId.values.first, HandLandmarkId.wrist);
      expect(HandLandmarkId.values, contains(HandLandmarkId.thumbCmc));
      expect(HandLandmarkId.values, contains(HandLandmarkId.thumbTip));
      expect(HandLandmarkId.values, contains(HandLandmarkId.indexTip));
      expect(HandLandmarkId.values, contains(HandLandmarkId.middleTip));
      expect(HandLandmarkId.values, contains(HandLandmarkId.ringTip));
      expect(HandLandmarkId.values, contains(HandLandmarkId.pinkyTip));
      expect(HandLandmarkId.values.last, HandLandmarkId.pinkyTip);
    });

    test('each finger contributes exactly four joints', () {
      const fingers = <(String, List<HandLandmarkId>)>[
        (
          'thumb',
          [
            HandLandmarkId.thumbCmc,
            HandLandmarkId.thumbMcp,
            HandLandmarkId.thumbIp,
            HandLandmarkId.thumbTip,
          ],
        ),
        (
          'index',
          [
            HandLandmarkId.indexMcp,
            HandLandmarkId.indexPip,
            HandLandmarkId.indexDip,
            HandLandmarkId.indexTip,
          ],
        ),
        (
          'middle',
          [
            HandLandmarkId.middleMcp,
            HandLandmarkId.middlePip,
            HandLandmarkId.middleDip,
            HandLandmarkId.middleTip,
          ],
        ),
        (
          'ring',
          [
            HandLandmarkId.ringMcp,
            HandLandmarkId.ringPip,
            HandLandmarkId.ringDip,
            HandLandmarkId.ringTip,
          ],
        ),
        (
          'pinky',
          [
            HandLandmarkId.pinkyMcp,
            HandLandmarkId.pinkyPip,
            HandLandmarkId.pinkyDip,
            HandLandmarkId.pinkyTip,
          ],
        ),
      ];
      for (final (finger, joints) in fingers) {
        expect(joints, hasLength(4), reason: '$finger must have 4 joints');
      }
    });
  });

  group('HandObservation — domain-level landmark access', () {
    final wrist = HandLandmarkPoint(x: 0.1, y: 0.2, z: 0, visibility: 0.95);
    final indexTip = HandLandmarkPoint(
      x: 0.5,
      y: 0.4,
      z: -0.05,
      visibility: 0.9,
    );
    final pinkyTip = HandLandmarkPoint(
      x: 0.55,
      y: 0.7,
      z: -0.05,
      visibility: 0.85,
    );
    final landmarks = <HandLandmarkId, HandLandmarkPoint>{
      HandLandmarkId.wrist: wrist,
      HandLandmarkId.indexTip: indexTip,
      HandLandmarkId.pinkyTip: pinkyTip,
    };

    test('byId returns the stored point for every present landmark', () {
      final observation = HandObservation(
        handedness: Handedness.right,
        landmarks: landmarks,
        confidence: 0.9,
      );
      expect(observation.byId(HandLandmarkId.wrist), wrist);
      expect(observation.byId(HandLandmarkId.indexTip), indexTip);
      expect(observation.byId(HandLandmarkId.pinkyTip), pinkyTip);
    });

    test(
      'byId returns null for absent landmarks (no provider-index leakage)',
      () {
        final observation = HandObservation(
          handedness: Handedness.left,
          landmarks: landmarks,
          confidence: 0.8,
        );
        // The caller asks by StrumSight ID — domain must not require indices.
        expect(observation.byId(HandLandmarkId.thumbTip), isNull);
        expect(observation.byId(HandLandmarkId.middleMcp), isNull);
      },
    );

    test('count reflects exactly the populated landmarks', () {
      final observation = HandObservation(
        handedness: Handedness.right,
        landmarks: landmarks,
        confidence: 0.9,
      );
      expect(observation.count, 3);
    });
  });

  group('HandLandmarkPoint — value guards', () {
    test('rejects NaN coordinates', () {
      expect(
        () => HandLandmarkPoint(x: double.nan, y: 0.5, z: 0, visibility: 1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects out-of-range visibility', () {
      expect(
        () => HandLandmarkPoint(x: 0.5, y: 0.5, z: 0, visibility: -0.01),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => HandLandmarkPoint(x: 0.5, y: 0.5, z: 0, visibility: 1.01),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('HandLandmarkResult — observability encoding', () {
    test('notObservable when zero hands are detected', () {
      final result = HandLandmarkResult.empty(
        timestampUs: 0,
        observability: HandLandmarkObservability.notObservable,
      );
      expect(result.hands, isEmpty);
      expect(result.observability, HandLandmarkObservability.notObservable);
    });

    test('one hand observation is distinct from two', () {
      final one = HandLandmarkResult.empty(
        timestampUs: 1000,
        observability: HandLandmarkObservability.one,
      );
      final two = HandLandmarkResult.empty(
        timestampUs: 1000,
        observability: HandLandmarkObservability.two,
      );
      expect(one.observability, HandLandmarkObservability.one);
      expect(two.observability, HandLandmarkObservability.two);
    });
  });
}
