// E05-R13 — Hand track assigner (SDD §15.3, §15.4, Kör 13 §Feladatok).
//
// The assigner is the stateful core of hand tracking: per frame, it
//   - matches the provider's `HandObservation`s to the previously known
//     tracks (position + previous-state basis — there is no per-hand
//     handedness-confidence field, §0.0 R1);
//   - assigns NEW track IDs to hands that have never been seen;
//   - holds the SAME track ID through a short occlusion (≤
//     [shortGapFrames]) and emits the track as `recovering`;
//   - after a long gap, emits a final `lost` snapshot for the previous
//     track and mints a NEW track ID when the hand reappears;
//   - derives the guitar role per hand from handedness + the player's
//     `leftHanded` setting using the §0.0 R8 formula (guitar geometry is
//     out of scope — R15);
//   - runs every tracked landmark through a `LandmarkSmoothingFilter` so
//     downstream consumers see the same smoothed coordinates regardless
//     of who reads them.
//
// Pure Dart, framework-free, deterministic — the only "clock" is the
// injected `frameIndex`. The constructor is intentionally narrow: NO
// camera-facing parameter (R07 invariance, §0.0 R2).
//
// The assigner works with a small, fixed subset of landmark IDs (the
// wrist and a few finger tips — `trackedLandmarkIds` below). The full
// 21-point topology is preserved by `HandObservation`; the assigner only
// smooths the IDs downstream consumers actually rely on. Picking a
// subset is intentional: it keeps the matching key cheap (just the wrist
// position) and avoids iterating over landmarks the assigner has no use
// for.

library;

import 'dart:math' as math;

import 'hand_landmarks.dart'
    show
        HandLandmarkId,
        HandObservation,
        HandLandmarkResult,
        Handedness,
        HandLandmarkPoint;
import 'hand_track.dart'
    show HandRole, HandTrack, HandTrackFrameState, TrackStatus;
import 'landmark_smoothing.dart' show LandmarkSmoothingFilter, SmoothingProfile;

/// The landmark IDs the assigner smooths and tracks across frames.
///
/// Wrist anchors the position-based matching; the finger tips carry the
/// visible motion downstream consumers actually read. New IDs land here
/// when a future round extends the visible set (R14 pose, R17 metrics).
const List<HandLandmarkId> trackedLandmarkIds = <HandLandmarkId>[
  HandLandmarkId.wrist,
  HandLandmarkId.indexTip,
  HandLandmarkId.middleTip,
  HandLandmarkId.ringTip,
  HandLandmarkId.pinkyTip,
];

/// Stateful hand tracker. One instance per session.
final class HandTrackAssigner {
  HandTrackAssigner({
    required this.leftHanded,
    this.shortGapFrames = 3,
    SmoothingProfile? pickingProfile,
    SmoothingProfile? frettingProfile,
    this.jumpVelocityThreshold = 0.30,
  }) : _pickingProfile = pickingProfile ?? SmoothingProfile.picking,
       _frettingProfile = frettingProfile ?? SmoothingProfile.fretting;

  /// The player's handedness setting. Drives the role derivation
  /// (R8). NOT the camera-side handedness — see §0.0 R2.
  final bool leftHanded;

  /// Maximum frames of missing observation before a track is declared
  /// `lost` and a new ID is minted on reappearance.
  final int shortGapFrames;

  /// Per-frame distance (normalized space) that triggers the jump-
  /// rejection gate inside the smoother.
  final double jumpVelocityThreshold;

  final SmoothingProfile _pickingProfile;
  final SmoothingProfile _frettingProfile;

  int _nextId = 1;
  final List<_InternalTrack> _internal = <_InternalTrack>[];

  LandmarkSmoothingFilter _filterFor(HandRole role) => LandmarkSmoothingFilter(
    profile: role == HandRole.picking ? _pickingProfile : _frettingProfile,
    jumpVelocityThreshold: jumpVelocityThreshold,
  );

  /// Process one frame. Returns the new `HandTrackFrameState`.
  HandTrackFrameState process(
    HandLandmarkResult result, {
    required int frameIndex,
  }) {
    final observations = result.hands;
    final now = frameIndex;

    // 1. Assign each observation to an existing track OR a new track.
    final matched = <_InternalTrack>[];
    final unmatched = <HandObservation>[...observations];

    // 1a. Greedy nearest-neighbour matching on the wrist position,
    //     restricted to the same physical handedness. The provider's
    //     handedness label is the only identity we get from the model.
    for (final obs in List<HandObservation>.from(unmatched)) {
      _InternalTrack? best;
      double bestDist = double.infinity;
      for (final candidate in _internal) {
        if (matched.contains(candidate)) continue;
        // Hard constraint: handedness must match. The model's handedness
        // label is what we use here; crossing hands swap positions but
        // keep their physical handedness, which is exactly what keeps
        // the role stable.
        if (candidate.handedness != obs.handedness) continue;
        final lastPoint = candidate.lastObservation?.byId(HandLandmarkId.wrist);
        final obsPoint = obs.byId(HandLandmarkId.wrist);
        if (lastPoint == null || obsPoint == null) continue;
        final dx = lastPoint.x - obsPoint.x;
        final dy = lastPoint.y - obsPoint.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < bestDist) {
          bestDist = dist;
          best = candidate;
        }
      }
      if (best != null) {
        matched.add(best);
        best.observe(obs, now);
        unmatched.remove(obs);
      }
    }

    // 1b. Anything still unmatched becomes a new track.
    for (final obs in unmatched) {
      final role = _roleFor(obs.handedness);
      final filter = _filterFor(role);
      final newTrack = _InternalTrack(
        id: _nextId++,
        handedness: obs.handedness,
        role: role,
        filter: filter,
        firstFrameIndex: now,
        lastSeenFrameIndex: now,
        lastObservation: obs,
        previousSmoothed: _extractLandmarks(obs, filter, now, previous: null),
        jumpVelocityThreshold: jumpVelocityThreshold,
      );
      _internal.add(newTrack);
      matched.add(newTrack);
    }

    // 2. Any internal track NOT matched this frame is either recovering
    //    (gap ≤ shortGapFrames) or lost (gap > shortGapFrames).
    final lost = <_InternalTrack>[];
    for (final track in _internal) {
      if (matched.contains(track)) continue;
      final gap = now - track.lastSeenFrameIndex;
      if (gap > shortGapFrames) {
        lost.add(track);
      }
    }
    // Drop lost tracks from the active list — they get one final `lost`
    // snapshot emitted below.
    _internal.removeWhere(lost.contains);

    // 3. Build the snapshot.
    final emitted = <HandTrack>[];
    for (final track in _internal) {
      final isMatched = matched.contains(track);
      final gap = now - track.lastSeenFrameIndex;
      final status = isMatched
          ? TrackStatus.active
          : (gap <= shortGapFrames ? TrackStatus.recovering : TrackStatus.lost);
      if (status == TrackStatus.lost) {
        continue; // shouldn't reach here post-filter
      }
      emitted.add(track.toHandTrack(status: status));
    }
    // Emit the lost tracks' final `lost` snapshot exactly once, then drop.
    for (final track in lost) {
      emitted.add(track.toHandTrack(status: TrackStatus.lost));
    }

    emitted.sort((a, b) => a.id.compareTo(b.id));
    return HandTrackFrameState(frameIndex: now, tracks: emitted);
  }

  /// The guitar role derived from the physical handedness and the player's
  /// `leftHanded` setting. R8 formula — guitar geometry is R15.
  HandRole _roleFor(Handedness physical) {
    if (leftHanded) {
      // Left-handed player: fretting is the RIGHT physical hand.
      return physical == Handedness.right
          ? HandRole.fretting
          : HandRole.picking;
    }
    // Right-handed player: fretting is the LEFT physical hand.
    return physical == Handedness.left ? HandRole.fretting : HandRole.picking;
  }
}

/// Extract the tracked IDs from an observation into a per-ID map.
Map<HandLandmarkId, HandLandmarkPoint> _extractLandmarks(
  HandObservation obs,
  LandmarkSmoothingFilter filter,
  int frameIndex, {
  required Map<HandLandmarkId, HandLandmarkPoint>? previous,
}) {
  final raw = <HandLandmarkId, HandLandmarkPoint>{};
  for (final id in trackedLandmarkIds) {
    final p = obs.byId(id);
    if (p != null) raw[id] = p;
  }
  return filter.filterMap(raw: raw, previous: previous, frameIndex: frameIndex);
}

/// Mutable internal representation of a track across frames.
class _InternalTrack {
  _InternalTrack({
    required this.id,
    required this.handedness,
    required this.role,
    required this.filter,
    required this.firstFrameIndex,
    required this.lastSeenFrameIndex,
    required this.lastObservation,
    required this.previousSmoothed,
    required this.jumpVelocityThreshold,
  });

  final int id;
  Handedness handedness;
  HandRole role;
  final LandmarkSmoothingFilter filter;
  final int firstFrameIndex;
  int lastSeenFrameIndex;
  HandObservation? lastObservation;
  Map<HandLandmarkId, HandLandmarkPoint> previousSmoothed;
  final double jumpVelocityThreshold;
  TrackStatus status = TrackStatus.active;

  void observe(HandObservation obs, int frameIndex) {
    lastSeenFrameIndex = frameIndex;
    lastObservation = obs;
    // The physical handedness follows the model label; the role stays
    // bound to the FIRST observation so crossing hands don't swap roles.
    handedness = obs.handedness;

    // Jump-rejection: if any landmark in the observation moves too far
    // from the previous smoothed, reject the whole observation and keep
    // the previous smoothed state.
    final raw = <HandLandmarkId, HandLandmarkPoint>{};
    for (final id in trackedLandmarkIds) {
      final p = obs.byId(id);
      if (p != null) raw[id] = p;
    }
    if (!_isRejected(raw, previousSmoothed)) {
      previousSmoothed = filter.filterMap(
        raw: raw,
        previous: previousSmoothed,
        frameIndex: frameIndex,
      );
    }
    status = TrackStatus.active;
  }

  bool _isRejected(
    Map<HandLandmarkId, HandLandmarkPoint> raw,
    Map<HandLandmarkId, HandLandmarkPoint> previous,
  ) {
    for (final entry in raw.entries) {
      final prev = previous[entry.key];
      if (prev == null) continue;
      final dx = entry.value.x - prev.x;
      final dy = entry.value.y - prev.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist > jumpVelocityThreshold) return true;
    }
    return false;
  }

  HandTrack toHandTrack({required TrackStatus status}) {
    return HandTrack(
      id: id,
      handedness: handedness,
      role: role,
      status: status,
      smoothedLandmarks: previousSmoothed,
      firstFrameIndex: firstFrameIndex,
      lastSeenFrameIndex: lastSeenFrameIndex,
    );
  }
}
