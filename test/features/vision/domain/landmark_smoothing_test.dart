// E05-R13 §6 — LandmarkSmoothingFilter acceptance matrix.
//
// Two behavioural matrices:
//
//   1. Smoothing matrix (picking vs fretting on the fast-strum fixture):
//        picking  → amplitude preservation ≥ 90% (hard floor);
//        fretting → high-frequency noise reduction ≥ 60% (documented).
//   2. Jump-rejection matrix (real fast strum vs single-frame teleport):
//        fast strum → output stays close to the input (no rejection);
//        teleport   → the offending frame is dropped, output reverts to
//                    the previous frame's smoothed value.
//
// All measurements are reported with explicit numbers in the asserts —
// amplitude ratio, noise ratio, and frame counts.

library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_landmarks.dart';
import 'package:strumsight/features/vision/domain/landmarks/landmark_smoothing.dart';

import '../../../fixtures/vision/tracks/track_fixtures.dart';

void main() {
  group('LandmarkSmoothingFilter — picking profile on a fast strum', () {
    test('peak-to-peak amplitude preservation ≥ 90% of the raw input', () {
      final filter = LandmarkSmoothingFilter(profile: SmoothingProfile.picking);
      final trajectory = fastStrumTrack(
        handedness: Handedness.right,
        frames: 30,
        amplitude: 0.10,
        cyclesAcross: 2.5,
        seed: 13,
      );

      final rawXs = <double>[];
      final smoothedXs = <double>[];
      HandLandmarkPoint? previous;
      for (final result in trajectory) {
        final hand = result.hands.single;
        final rawX = hand.byId(HandLandmarkId.wrist)!.x;
        rawXs.add(rawX);
        final smoothed = filter.filter(
          raw: hand.byId(HandLandmarkId.wrist),
          previous: previous,
          frameIndex: rawXs.length - 1,
        );
        smoothedXs.add(smoothed.x);
        previous = smoothed;
      }

      // Skip the first two frames — the filter is initialising.
      final tailRawRange = _range(rawXs.sublist(2));
      final tailSmoothedRange = _range(smoothedXs.sublist(2));
      final ratio = tailSmoothedRange / tailRawRange;

      // Hard floor — the brief forbids weakening the 90% bound.
      expect(
        ratio,
        greaterThanOrEqualTo(0.90),
        reason:
            'picking filter must preserve ≥ 90% of the raw '
            'amplitude on a fast strum; measured ratio was '
            '${(ratio * 100).toStringAsFixed(1)}% '
            '(raw peak-to-peak=$tailRawRange, smoothed=$tailSmoothedRange)',
      );

      // Sanity: the input has a meaningful range — without this the test
      // could pass vacuously on a constant input.
      expect(tailRawRange, greaterThan(0.05));
    });
  });

  group('LandmarkSmoothingFilter — fretting profile on a noisy trajectory', () {
    test('high-frequency noise reduction ≥ 60% (documented floor)', () {
      final filter = LandmarkSmoothingFilter(
        profile: SmoothingProfile.fretting,
      );
      // Slow drift + small high-frequency noise — exactly the case the
      // fretting profile is tuned for (hand is roughly still, sensor
      // jitters).
      final trajectory = continuousNoisyTrack(
        handedness: Handedness.right,
        frames: 60,
        startX: 0.30,
        stepPerFrame: 0.001,
        noiseAmplitude: 0.020,
        seed: 42,
      );

      final rawXs = <double>[];
      final smoothedXs = <double>[];
      HandLandmarkPoint? previous;
      for (final result in trajectory) {
        final hand = result.hands.single;
        final rawX = hand.byId(HandLandmarkId.wrist)!.x;
        rawXs.add(rawX);
        final smoothed = filter.filter(
          raw: hand.byId(HandLandmarkId.wrist),
          previous: previous,
          frameIndex: rawXs.length - 1,
        );
        smoothedXs.add(smoothed.x);
        previous = smoothed;
      }

      // Measure high-frequency content as the per-frame delta RMS, then
      // compare raw vs smoothed. The slow drift cancels out in the delta.
      final rawDeltaRms = _deltaRms(rawXs);
      final smoothedDeltaRms = _deltaRms(smoothedXs);
      final reductionRatio = (rawDeltaRms - smoothedDeltaRms) / rawDeltaRms;

      expect(
        reductionRatio,
        greaterThanOrEqualTo(0.60),
        reason:
            'fretting filter must reduce high-frequency noise by '
            '≥ 60%; measured reduction was '
            '${(reductionRatio * 100).toStringAsFixed(1)}% '
            '(raw ΔRMS=$rawDeltaRms, smoothed ΔRMS=$smoothedDeltaRms)',
      );
    });
  });

  group('LandmarkSmoothingFilter — jump-rejection matrix', () {
    test('fast strum passes the velocity check (no rejection)', () {
      final filter = LandmarkSmoothingFilter(profile: SmoothingProfile.picking);
      final trajectory = fastStrumTrack(
        frames: 30,
        amplitude: 0.10,
        cyclesAcross: 2.5,
        seed: 13,
      );

      var rejectedCount = 0;
      HandLandmarkPoint? previous;
      for (var i = 0; i < trajectory.length; i++) {
        final raw = trajectory[i].hands.single.byId(HandLandmarkId.wrist)!;
        final wasRejected = filter.shouldReject(
          raw: raw,
          previous: previous,
          frameIndex: i,
        );
        if (wasRejected) rejectedCount++;
        final smoothed = filter.filter(
          raw: trajectory[i].hands.single.byId(HandLandmarkId.wrist),
          previous: previous,
          frameIndex: i,
        );
        previous = smoothed;
      }

      // A real fast strum has per-frame delta ~ 0.08, well below the
      // 0.3 jump threshold; the filter MUST NOT reject any of its frames.
      expect(
        rejectedCount,
        0,
        reason:
            'the fast-strum fixture must pass the velocity gate; '
            'if frames are rejected, the threshold is too low — '
            'adjust the threshold or the fixture, never the assert',
      );
    });

    test('single-frame teleport IS rejected, then the next frame recovers', () {
      final filter = LandmarkSmoothingFilter(profile: SmoothingProfile.picking);
      final trajectory = teleportingTrack(
        frames: 10,
        teleportAt: 5,
        startX: 0.30,
        teleportX: 0.85,
      );

      HandLandmarkPoint? previous;
      var teleportFrameRejected = false;
      HandLandmarkPoint? postTeleportSmoothed;
      for (var i = 0; i < trajectory.length; i++) {
        final raw = trajectory[i].hands.single.byId(HandLandmarkId.wrist)!;
        if (filter.shouldReject(raw: raw, previous: previous, frameIndex: i)) {
          if (i == 5) teleportFrameRejected = true;
          // Drop the raw — keep the previous smoothed.
          continue;
        }
        final smoothed = filter.filter(
          raw: raw,
          previous: previous,
          frameIndex: i,
        );
        if (i == 6) postTeleportSmoothed = smoothed;
        previous = smoothed;
      }

      expect(
        teleportFrameRejected,
        isTrue,
        reason: 'a per-frame jump of ~0.55 must trigger the velocity gate',
      );
      expect(
        previous!.x,
        lessThan(0.50),
        reason:
            'after the rejection the previous smoothed value must '
            'still equal the pre-teleport trajectory (start=0.30, '
            'teleport=0.85)',
      );
      expect(
        postTeleportSmoothed!.x,
        lessThan(0.50),
        reason:
            'the frame immediately after the teleport must also stay '
            'near the pre-teleport trajectory — no jump echo',
      );
    });
  });
}

double _range(List<double> xs) {
  var lo = double.infinity;
  var hi = double.negativeInfinity;
  for (final v in xs) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  return hi - lo;
}

double _deltaRms(List<double> xs) {
  if (xs.length < 2) return 0;
  var sum = 0.0;
  for (var i = 1; i < xs.length; i++) {
    final d = xs[i] - xs[i - 1];
    sum += d * d;
  }
  return math.sqrt(sum / (xs.length - 1));
}
