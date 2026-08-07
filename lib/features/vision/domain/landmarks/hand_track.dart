// E05-R13 — Hand track model (SDD §15.4, Kör 13 §Feladatok).
//
// A `HandTrack` is the stable, frame-surviving identity of one physical hand
// across the jitter, short occlusions and crossings of a session. Three
// independent concepts live here, each documented separately because the
// brief forbids conflating them:
//
//   - physical handedness (`Handedness` from hand_landmarks.dart),
//   - guitar role (`HandRole` — fretting vs picking),
//   - lifecycle status (`TrackStatus` — active / recovering / lost).
//
// Pure Dart, framework-free, immutable. The stateful evolution (track
// birth, recovery, loss) lives in `HandTrackAssigner`, which produces
// `HandTrackFrameState` snapshots — `HandTrack` itself never mutates.

library;

import 'hand_landmarks.dart' show HandLandmarkId, HandLandmarkPoint, Handedness;

/// Which guitar role a track represents.
///
/// Roles are NOT derived from handedness alone — they require the player's
/// `leftHanded` setting (and eventually, guitar geometry in R15). The
/// `HandTrackAssigner` is the only place the derivation lives, so this
/// enum stays a pure label.
enum HandRole { fretting, picking }

/// The lifecycle state of a track on the frame it was emitted.
///
///   - [active]    — the track was matched to an observation this frame.
///   - [recovering]— the track was missing for ≤ `shortGapFrames` frames;
///                   the same track ID is preserved and the assigner is
///                   waiting for the hand to come back into view.
///   - [lost]      — the track has been missing for > `shortGapFrames`
///                   frames; the assigner emits one final `lost` snapshot
///                   and then drops it. Any hand that re-enters the frame
///                   gets a NEW track ID.
enum TrackStatus { active, recovering, lost }

/// The stable, smoothed identity of one hand over the session.
///
/// Identity (`id`) is a monotonic counter minted by `HandTrackAssigner` —
/// it has no relation to the provider's handedness label, which can flip
/// during crossings and the model must not rely on. `smoothedLandmarks`
/// carries the filtered coordinates for every landmark the assigner was
/// asked to track; absent IDs match `HandObservation`'s absent-IDs rule
/// (no zero-fill).
final class HandTrack {
  HandTrack({
    required this.id,
    required this.handedness,
    required this.role,
    required this.status,
    required this.smoothedLandmarks,
    required this.firstFrameIndex,
    required this.lastSeenFrameIndex,
    this.rawSmoothedDeltaNormalized = 0,
  });

  /// Stable, monotonic, opaque integer identity. Two frames with the same
  /// `id` mean "this is the same hand" — independent of the provider's
  /// handedness label for that frame.
  final int id;

  /// The hand's PHYSICAL handedness — the model's label, NOT a camera
  /// mirror. R07 invariance: the front-camera preview may be mirrored,
  /// but the domain value here never reflects that mirror.
  final Handedness handedness;

  /// The guitar role derived from handedness + the player's `leftHanded`
  /// setting. R8 formula is the assigner's responsibility.
  final HandRole role;

  /// Lifecycle status on the frame this snapshot was emitted.
  final TrackStatus status;

  /// The smoothed landmark coordinates for the tracked IDs. Absent IDs
  /// are absent, never zero-filled.
  final Map<HandLandmarkId, HandLandmarkPoint> smoothedLandmarks;

  /// The first frame index this track was ever observed on.
  final int firstFrameIndex;

  /// The most recent frame index where this track was matched to an
  /// observation (NOT necessarily the frame the snapshot was emitted on —
  /// a `recovering` snapshot's `lastSeenFrameIndex` is older than the
  /// current frame by at most `shortGapFrames`).
  final int lastSeenFrameIndex;

  /// Wrist distance between the latest raw observation and the previous
  /// smoothed value, in normalized coordinates.
  final double rawSmoothedDeltaNormalized;
}

/// A per-frame snapshot of every track the assigner emitted.
///
/// The snapshot is immutable; successive calls to `HandTrackAssigner.process`
/// return new snapshots. Downstream consumers (smoothed-landmark reader,
/// `TrackContinuity` aggregator) treat each snapshot as a one-way view.
final class HandTrackFrameState {
  HandTrackFrameState({
    required this.frameIndex,
    required List<HandTrack> tracks,
    this.processingDuration = Duration.zero,
  }) : _tracks = List.unmodifiable(tracks);

  /// The injected frame index this snapshot belongs to — the deterministic
  /// "clock" the assigner uses instead of `DateTime.now()`.
  final int frameIndex;

  /// Wall-clock time spent producing this frame snapshot.
  final Duration processingDuration;

  final List<HandTrack> _tracks;

  List<HandTrack> get tracks => _tracks;
}
