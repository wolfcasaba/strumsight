// E05-R13 — Hand track fixture generator.
//
// Deterministic generators used by the hand-track assigner and smoothing unit
// tests and by the ID-stability property test. All generators are pure
// functions on plain Dart primitives, so the same seed produces the same
// sequence on every run (PROPERTY_SEED-aware).
//
// The fixtures are deliberately constructed to exercise the four behaviours
// the §6 acceptance matrix pins:
//
//   1. continuousNoisyTrack        — track stays alive on a noisy but
//                                    continuous trajectory;
//   2. occludedTrack(under/at/over) — three cells around shortGapFrames;
//   3. crossingHandsTrack          — two hands swap x positions across the
//                                    frame boundary;
//   4. fastStrumTrack              — high-amplitude sinusoidal motion that
//                                    must NOT be eaten by the picking filter.
//
// Every generator returns a `List<HandLandmarkResult>` so a caller can drive
// the assigner by feeding the list one element per frame. The frames are
// numbered by their list index — the assigner treats the index as its
// injected clock, so there is no DateTime / Stopwatch anywhere.

library;

import 'dart:math' as math;

import 'package:strumsight/features/vision/domain/landmarks/hand_landmarks.dart';

/// The minimum set of landmark IDs every fixture populates.
///
/// Keeping the topology constant across fixtures keeps the smoothed-vs-raw
/// comparisons comparable: every fixture's "wrist" carries the same physical
/// meaning, so the per-frame velocity calculations stay consistent.
const List<HandLandmarkId> _trackedIds = <HandLandmarkId>[
  HandLandmarkId.wrist,
  HandLandmarkId.indexTip,
  HandLandmarkId.middleTip,
];

HandObservation _hand({
  required Handedness handedness,
  required double x,
  required double y,
  double visibility = 0.95,
  double confidence = 0.92,
}) {
  final points = <HandLandmarkId, HandLandmarkPoint>{
    for (final id in _trackedIds)
      id: HandLandmarkPoint(x: x, y: y, z: 0, visibility: visibility),
  };
  return HandObservation(
    handedness: handedness,
    landmarks: points,
    confidence: confidence,
  );
}

HandLandmarkResult _result({
  required int timestampUs,
  required List<HandObservation> hands,
}) {
  final observability = hands.isEmpty
      ? HandLandmarkObservability.notObservable
      : (hands.length == 1
            ? HandLandmarkObservability.one
            : HandLandmarkObservability.two);
  return HandLandmarkResult(
    timestampUs: timestampUs,
    observability: observability,
    hands: hands,
  );
}

/// Build a noisy but continuous single-hand trajectory.
///
/// `startX`/`startY` set the anchor; the trajectory drifts by `stepPerFrame`
/// per frame on the x axis, with `noiseAmplitude` of deterministic noise
/// applied to both axes (a fixed-step pseudo-random — not Math.random — so
/// the same call produces the same sequence).
List<HandLandmarkResult> continuousNoisyTrack({
  Handedness handedness = Handedness.right,
  int frames = 60,
  double startX = 0.30,
  double startY = 0.50,
  double stepPerFrame = 0.005,
  double noiseAmplitude = 0.015,
  int seed = 42,
}) {
  final random = math.Random(seed);
  final out = <HandLandmarkResult>[];
  for (var i = 0; i < frames; i++) {
    final x =
        startX +
        stepPerFrame * i +
        (random.nextDouble() - 0.5) * noiseAmplitude;
    final y = startY + (random.nextDouble() - 0.5) * noiseAmplitude;
    out.add(
      _result(
        timestampUs: i * 33_333,
        hands: <HandObservation>[_hand(handedness: handedness, x: x, y: y)],
      ),
    );
  }
  return out;
}

/// Build a trajectory with a single occlusion of `gapLength` frames starting
/// at `gapAt`. The hand returns to (near) its pre-gap trajectory after the
/// gap. Frames inside the gap carry `notObservable`.
List<HandLandmarkResult> occludedTrack({
  Handedness handedness = Handedness.right,
  int frames = 30,
  int gapAt = 10,
  int gapLength = 4,
  double startX = 0.30,
  double startY = 0.50,
  double stepPerFrame = 0.005,
  double noiseAmplitude = 0.005,
  int seed = 7,
}) {
  final random = math.Random(seed);
  final out = <HandLandmarkResult>[];
  for (var i = 0; i < frames; i++) {
    final isOccluded = i >= gapAt && i < gapAt + gapLength;
    if (isOccluded) {
      out.add(
        _result(timestampUs: i * 33_333, hands: const <HandObservation>[]),
      );
      continue;
    }
    final x =
        startX +
        stepPerFrame * i +
        (random.nextDouble() - 0.5) * noiseAmplitude;
    final y = startY + (random.nextDouble() - 0.5) * noiseAmplitude;
    out.add(
      _result(
        timestampUs: i * 33_333,
        hands: <HandObservation>[_hand(handedness: handedness, x: x, y: y)],
      ),
    );
  }
  return out;
}

/// Build a trajectory where two hands (left + right) cross each other's x
/// position around `crossAt`. The crossing is what stresses track-by-position
/// association: a naive nearest-centroid assigner would swap the IDs.
List<HandLandmarkResult> crossingHandsTrack({
  int frames = 30,
  int crossAt = 15,
  double leftStartX = 0.30,
  double rightStartX = 0.70,
  double yLeft = 0.40,
  double yRight = 0.55,
  int seed = 11,
}) {
  final random = math.Random(seed);
  final out = <HandLandmarkResult>[];
  for (var i = 0; i < frames; i++) {
    // Linear swap between frame 0 and crossAt*2: pre-cross → crossing → post-cross.
    final t = (i / crossAt).clamp(0.0, 2.0);
    final crossWeight = t <= 1.0 ? t : 2.0 - t;
    final leftX =
        leftStartX +
        (rightStartX - leftStartX) * crossWeight +
        (random.nextDouble() - 0.5) * 0.005;
    final rightX =
        rightStartX +
        (leftStartX - rightStartX) * crossWeight +
        (random.nextDouble() - 0.5) * 0.005;
    out.add(
      _result(
        timestampUs: i * 33_333,
        hands: <HandObservation>[
          _hand(handedness: Handedness.left, x: leftX, y: yLeft),
          _hand(handedness: Handedness.right, x: rightX, y: yRight),
        ],
      ),
    );
  }
  return out;
}

/// Build a high-amplitude sinusoidal trajectory that models a real fast
/// strum. The picking filter must preserve its amplitude; the jump-
/// rejection threshold must NOT fire on the per-frame delta here.
List<HandLandmarkResult> fastStrumTrack({
  Handedness handedness = Handedness.right,
  int frames = 30,
  double centerX = 0.50,
  double centerY = 0.50,
  double amplitude = 0.10,
  double cyclesAcross = 2.5,
  int seed = 13,
}) {
  final random = math.Random(seed);
  final out = <HandLandmarkResult>[];
  final omega = (2.0 * math.pi * cyclesAcross) / frames;
  for (var i = 0; i < frames; i++) {
    final x = centerX + amplitude * math.sin(omega * i);
    final y =
        centerY +
        amplitude * 0.1 * math.sin(omega * i) +
        (random.nextDouble() - 0.5) * 0.001;
    out.add(
      _result(
        timestampUs: i * 33_333,
        hands: <HandObservation>[_hand(handedness: handedness, x: x, y: y)],
      ),
    );
  }
  return out;
}

/// Build a single-frame teleport (the rejection target): the hand jumps from
/// its expected position to a distant one in a single frame, then returns.
List<HandLandmarkResult> teleportingTrack({
  Handedness handedness = Handedness.right,
  int frames = 10,
  int teleportAt = 5,
  double startX = 0.30,
  double startY = 0.50,
  double teleportX = 0.85,
  double teleportY = 0.20,
}) {
  final out = <HandLandmarkResult>[];
  for (var i = 0; i < frames; i++) {
    final isTeleport = i == teleportAt;
    final x = isTeleport ? teleportX : startX;
    final y = isTeleport ? teleportY : startY;
    out.add(
      _result(
        timestampUs: i * 33_333,
        hands: <HandObservation>[_hand(handedness: handedness, x: x, y: y)],
      ),
    );
  }
  return out;
}

/// Build a trajectory that holds near `preX` for [settle] frames and then
/// STAYS at a new, distant `postX` from frame [relocateAt] onwards. Models
/// a real, sustained relocation (no teleport blip, no occlusion). The
/// smoother must eventually catch up to the new position; the F1 BLOCKER
/// is the pre-fix behaviour of freezing on the old anchor.
List<HandLandmarkResult> persistentRelocationTrack({
  Handedness handedness = Handedness.right,
  int frames = 40,
  int settle = 10,
  int relocateAt = 10,
  double preX = 0.30,
  double preY = 0.50,
  double postX = 0.70,
  double postY = 0.50,
  double noiseAmplitude = 0.001,
  int seed = 17,
}) {
  assert(relocateAt >= settle, 'relocate must come after the settle window');
  final random = math.Random(seed);
  HandLandmarkResult build(int i) {
    final x = i < relocateAt ? preX : postX;
    final y = i < relocateAt ? preY : postY;
    final jitter = (random.nextDouble() - 0.5) * noiseAmplitude;
    return _result(
      timestampUs: i * 33_333,
      hands: <HandObservation>[
        _hand(handedness: handedness, x: x + jitter, y: y + jitter),
      ],
    );
  }

  return <HandLandmarkResult>[for (var i = 0; i < frames; i++) build(i)];
}

/// Same relocation pattern but the hand briefly disappears (short occlusion)
/// before reappearing at the new spot. `gapAt` is the first occluded frame
/// and `gapLength` frames are notObservable after it. The relocated hand
/// must be tracked as the SAME track ID (short gap rule) and the smoother
/// must catch up to the new position.
List<HandLandmarkResult> relocationAfterOcclusionTrack({
  Handedness handedness = Handedness.right,
  int frames = 40,
  int settle = 8,
  int gapAt = 8,
  int gapLength = 3,
  double preX = 0.30,
  double postX = 0.70,
  double preY = 0.50,
  double postY = 0.50,
  int seed = 21,
}) {
  assert(gapAt >= settle, 'gap must come after the settle window');
  final random = math.Random(seed);
  final out = <HandLandmarkResult>[];
  for (var i = 0; i < frames; i++) {
    final inGap = i >= gapAt && i < gapAt + gapLength;
    if (inGap) {
      out.add(
        _result(timestampUs: i * 33_333, hands: const <HandObservation>[]),
      );
      continue;
    }
    final x = i < gapAt ? preX : postX;
    final y = i < gapAt ? preY : postY;
    final jitter = (random.nextDouble() - 0.5) * 0.001;
    out.add(
      _result(
        timestampUs: i * 33_333,
        hands: <HandObservation>[
          _hand(handedness: handedness, x: x + jitter, y: y + jitter),
        ],
      ),
    );
  }
  return out;
}

/// Build a trajectory whose visibility starts high and then drops to a
/// sustained low value. Used to prove the smoothed visibility follows
/// the raw (not the historical max).
List<HandLandmarkResult> lowVisibilityTrack({
  Handedness handedness = Handedness.right,
  int frames = 30,
  double x = 0.30,
  double y = 0.50,
  double highVisibility = 0.95,
  double lowVisibility = 0.10,
  int dropAt = 5,
}) {
  final out = <HandLandmarkResult>[];
  for (var i = 0; i < frames; i++) {
    final v = i < dropAt ? highVisibility : lowVisibility;
    final points = <HandLandmarkId, HandLandmarkPoint>{
      for (final id in _trackedIds)
        id: HandLandmarkPoint(x: x, y: y, z: 0, visibility: v),
    };
    out.add(
      HandLandmarkResult(
        timestampUs: i * 33_333,
        observability: HandLandmarkObservability.one,
        hands: <HandObservation>[
          HandObservation(
            handedness: handedness,
            landmarks: points,
            confidence: v,
          ),
        ],
      ),
    );
  }
  return out;
}
