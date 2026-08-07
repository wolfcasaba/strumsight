// E05-R13 §6 — HandTrackAssigner acceptance matrix.
//
// Four behavioural matrices measured against the assigner:
//
//   1. continuous trajectory → ONE stable track ID across all frames;
//   2. occlusion matrix (3 cells around `shortGapFrames = 3`):
//        under  (gap = 2) → SAME track ID;
//        at     (gap = 3) → SAME track ID;
//        over   (gap = 5) → trackLost + NEW ID;
//   3. crossing hands → roles/IDs do NOT swap across the crossing point;
//   4. mirror/left-handed parity: `leftHanded ∈ {false, true}` × facing
//      is intentionally NOT a parameter of the assigner (R07 invariant) —
//      the assigner is tested with the same input under both leftHanded
//      values, and the role assignment must reflect the player setting.
//
// All four matrices are measured with hard numbers in the asserts, not with
// soft "should be the same" prose. The `shortGapFrames` value comes from the
// `HandTrackAssigner` default; a single `python3 -c` calculation in the
// brief §10 backs the three gap-lengths against it.

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_landmarks.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_track.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_track_assigner.dart';

import '../../../fixtures/vision/tracks/track_fixtures.dart';

void main() {
  group(
    'HandTrackAssigner — ID stability on a continuous noisy trajectory',
    () {
      test('one physical hand keeps ONE stable track ID across all frames', () {
        final assigner = HandTrackAssigner(
          leftHanded: false,
          shortGapFrames: 3,
        );

        final trajectory = continuousNoisyTrack(
          handedness: Handedness.right,
          frames: 60,
          seed: 42,
        );

        final trackIdsPerFrame = <int>[];
        for (var i = 0; i < trajectory.length; i++) {
          final state = assigner.process(trajectory[i], frameIndex: i);
          final active = state.tracks
              .where((t) => t.status == TrackStatus.active)
              .toList();
          expect(
            active,
            hasLength(1),
            reason: 'frame $i must see exactly one active track',
          );
          trackIdsPerFrame.add(active.single.id);
        }

        // Every frame's track ID is identical to the first frame's — the
        // %-threshold for "stable" is 100% identity here.
        final firstId = trackIdsPerFrame.first;
        for (final id in trackIdsPerFrame) {
          expect(
            id,
            firstId,
            reason: 'no frame may mint a new track on a continuous path',
          );
        }
      });
    },
  );

  group(
    'HandTrackAssigner — occlusion matrix (under / at / over shortGap)',
    () {
      test('gap of 2 frames (< shortGapFrames=3) → SAME track ID', () {
        final assigner = HandTrackAssigner(
          leftHanded: false,
          shortGapFrames: 3,
        );
        final trajectory = occludedTrack(
          handedness: Handedness.right,
          frames: 30,
          gapAt: 10,
          gapLength: 2,
          seed: 7,
        );

        final ids = <int>[];
        for (var i = 0; i < trajectory.length; i++) {
          final state = assigner.process(trajectory[i], frameIndex: i);
          // The track either stays active (no occlusion this frame) or is
          // emitted in `recovering` state during the occlusion — both states
          // carry the SAME track ID under the short-gap rule.
          final live = state.tracks
              .where((t) => t.status != TrackStatus.lost)
              .toList();
          ids.add(live.isEmpty ? -1 : live.single.id);
        }

        // Before, during, and after the occlusion the ID is identical.
        expect(ids[9], ids[10]); // right before / right after gap start
        expect(ids[10], ids[11]); // gap frame 1 / 2
        expect(ids[11], ids[12]); // gap frame 2 / right after gap
        expect(ids[0], ids.last);
      });

      test('gap of 3 frames (= shortGapFrames) → SAME track ID', () {
        final assigner = HandTrackAssigner(
          leftHanded: false,
          shortGapFrames: 3,
        );
        final trajectory = occludedTrack(
          handedness: Handedness.right,
          frames: 30,
          gapAt: 10,
          gapLength: 3,
          seed: 7,
        );

        final ids = <int>[];
        for (var i = 0; i < trajectory.length; i++) {
          final state = assigner.process(trajectory[i], frameIndex: i);
          final live = state.tracks
              .where((t) => t.status != TrackStatus.lost)
              .toList();
          ids.add(live.isEmpty ? -1 : live.single.id);
        }

        expect(ids[9], ids[12]); // right before / right after 3-frame gap
        expect(ids[0], ids.last);
      });

      test('gap of 5 frames (> shortGapFrames=3) → trackLost + NEW ID', () {
        final assigner = HandTrackAssigner(
          leftHanded: false,
          shortGapFrames: 3,
        );
        final trajectory = occludedTrack(
          handedness: Handedness.right,
          frames: 30,
          gapAt: 10,
          gapLength: 5,
          seed: 7,
        );

        var lastActiveId = -1;
        var postLossActiveId = -1;
        var sawLost = false;
        for (var i = 0; i < trajectory.length; i++) {
          final state = assigner.process(trajectory[i], frameIndex: i);
          if (i < 10) {
            lastActiveId = state.tracks
                .firstWhere((t) => t.status == TrackStatus.active)
                .id;
            continue;
          }
          // After the gap starts, the track either recovers (gap frames 1..3)
          // or transitions to `lost` (frames 4..5 of the gap) and a NEW
          // active track appears when the hand re-enters.
          if (state.tracks.any((t) => t.status == TrackStatus.lost)) {
            sawLost = true;
          }
          final active = state.tracks
              .where((t) => t.status == TrackStatus.active)
              .toList();
          if (active.isNotEmpty && i >= 15) {
            postLossActiveId = active.single.id;
          }
        }

        expect(
          sawLost,
          isTrue,
          reason:
              'a gap strictly longer than shortGapFrames must yield '
              'at least one explicit `trackLost` event',
        );
        expect(postLossActiveId, isNot(-1));
        expect(
          postLossActiveId,
          isNot(lastActiveId),
          reason: 'after a long gap the re-entered hand MUST be a NEW track',
        );
      });
    },
  );

  group('HandTrackAssigner — crossing hands, ID and role stay stable', () {
    test('two physical hands crossing → track IDs and roles do not swap', () {
      final assigner = HandTrackAssigner(leftHanded: false, shortGapFrames: 3);

      final trajectory = crossingHandsTrack(frames: 30, crossAt: 15, seed: 11);

      // First frame establishes which ID belongs to which physical hand /
      // role — that mapping must remain stable across the crossing.
      final initial = assigner.process(trajectory.first, frameIndex: 0);
      final initialByRole = <HandRole, int>{
        for (final t in initial.tracks) t.role: t.id,
      };
      expect(initialByRole.keys, containsAll(HandRole.values));

      final initialFrettingId = initialByRole[HandRole.fretting]!;
      final initialPickingId = initialByRole[HandRole.picking]!;

      for (var i = 1; i < trajectory.length; i++) {
        final state = assigner.process(trajectory[i], frameIndex: i);
        final byRole = <HandRole, int>{
          for (final t in state.tracks) t.role: t.id,
        };
        expect(
          byRole[HandRole.fretting],
          initialFrettingId,
          reason: 'fretting track ID must not change at frame $i',
        );
        expect(
          byRole[HandRole.picking],
          initialPickingId,
          reason: 'picking track ID must not change at frame $i',
        );
      }
    });
  });

  group('HandTrackAssigner — mirror / left-handed parity (4-cell matrix)', () {
    test('leftHanded × {back, front} all 4 cells keep roles consistent', () {
      // R07 invariant: the model's handedness label is the non-mirrored
      // domain truth, so the camera facing has NO input slot in the
      // assigner. The 4-cell matrix here is an INVARIANCE proof: feeding
      // the same trajectory under every (leftHanded, facing) combination
      // produces the same role assignment, because the assigner does not
      // read the facing value at all.
      final trajectory = continuousNoisyTrack(
        handedness: Handedness.right,
        frames: 30,
        seed: 42,
      );

      for (final leftHanded in <bool>[false, true]) {
        for (final facing in <String>['back', 'front']) {
          final assigner = HandTrackAssigner(
            leftHanded: leftHanded,
            shortGapFrames: 3,
          );
          for (var i = 0; i < trajectory.length; i++) {
            final state = assigner.process(trajectory[i], frameIndex: i);
            // Single active track.
            final active = state.tracks
                .where((t) => t.status == TrackStatus.active)
                .toList();
            expect(
              active,
              hasLength(1),
              reason: '($leftHanded, $facing) frame $i',
            );
            final track = active.single;
            // The role is derived from handedness + leftHanded, NOT from
            // the camera facing — so both facings give the same role for
            // the same leftHanded value. The R8 formula:
            //   leftHanded=false → frettingHand=left, pickingHand=right
            //   leftHanded=true  → frettingHand=right, pickingHand=left
            // A RIGHT physical hand therefore maps to:
            //   leftHanded=false → picking; leftHanded=true → fretting.
            final expectedRole = leftHanded
                ? HandRole.fretting
                : HandRole.picking;
            expect(
              track.role,
              expectedRole,
              reason:
                  '($leftHanded, $facing) frame $i: physical '
                  'right hand must map to the expected role',
            );
            expect(
              track.handedness,
              Handedness.right,
              reason:
                  '($leftHanded, $facing) frame $i: physical '
                  'handedness is the model label, NOT the camera side',
            );
          }
        }
      }
    });
  });
}
