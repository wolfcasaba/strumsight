// E05-R13 §6 — Property test: ID stability on noisy continuous trajectories.
//
// Across N trials with `PROPERTY_SEED` (default 42) randomized noise
// amplitude and drift, every trial's continuous trajectory must produce
// EXACTLY ONE active track on every frame, and the ID must be stable
// across the full trajectory. A trial is "unstable" when a single track
// gains a second ID over its lifetime; the acceptance threshold is 100%
// trials stable (no trial may mint an extra ID).

library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_landmarks.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_track.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_track_assigner.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final random = math.Random(seed);
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  const trials = 80;
  const framesPerTrial = 60;
  var stableTrials = 0;

  test('property: noisy continuous trajectory keeps ONE stable track ID', () {
    for (var trial = 0; trial < trials; trial++) {
      final noiseAmplitude = 0.005 + random.nextDouble() * 0.04;
      final stepPerFrame = -0.01 + random.nextDouble() * 0.02;
      final startX = 0.10 + random.nextDouble() * 0.60;
      final startY = 0.10 + random.nextDouble() * 0.60;
      final handedness = random.nextBool() ? Handedness.left : Handedness.right;
      final leftHanded = random.nextBool();

      final assigner = HandTrackAssigner(
        leftHanded: leftHanded,
        shortGapFrames: 3,
      );

      var firstActiveId = -1;
      var trialStable = true;
      for (var i = 0; i < framesPerTrial; i++) {
        final x =
            startX +
            stepPerFrame * i +
            (random.nextDouble() - 0.5) * noiseAmplitude;
        final y = startY + (random.nextDouble() - 0.5) * noiseAmplitude;
        final result = HandLandmarkResult(
          timestampUs: i * 33_333,
          observability: HandLandmarkObservability.one,
          hands: <HandObservation>[
            HandObservation(
              handedness: handedness,
              landmarks: <HandLandmarkId, HandLandmarkPoint>{
                HandLandmarkId.wrist: HandLandmarkPoint(
                  x: x,
                  y: y,
                  z: 0,
                  visibility: 0.95,
                ),
              },
              confidence: 0.9,
            ),
          ],
        );

        final state = assigner.process(result, frameIndex: i);
        final active = state.tracks
            .where((t) => t.status == TrackStatus.active)
            .toList();
        if (active.length != 1) {
          trialStable = false;
          break;
        }
        final id = active.single.id;
        if (firstActiveId == -1) {
          firstActiveId = id;
        } else if (id != firstActiveId) {
          trialStable = false;
          break;
        }
      }

      if (trialStable) stableTrials++;
    }

    // 100% stability required — any failing trial is a real regression.
    // %-based threshold documented in the brief §6 acceptance matrix.
    final stableRatio = stableTrials / trials;
    expect(
      stableRatio,
      equals(1.0),
      reason:
          'all $trials trials must keep a stable track ID; '
          'unstable: ${trials - stableTrials}',
    );
  });
}
