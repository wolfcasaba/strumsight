// E05-R13 — Track continuity metrics (SDD §15.4, Kör 13 §Feladatok).
//
// Pure aggregation over a sequence of `HandTrackFrameState`s. The metrics
// are designed to be cheap to compute, deterministic on the input order,
// and comparable across sessions. They feed the performance summary and
// surface regressions in tracking quality (jitter spike, ID churn,
// processing-time blow-up).
//
// The assigner reports two things per frame:
//   - a `processingDuration` on the `HandTrackFrameState` (Stopwatch.elapsed);
//   - a `rawSmoothedDeltaNormalized` on each `HandTrack` (wrist delta).
// `TrackContinuity.aggregate` sums them so consumers can read the
// summary without having to walk every snapshot themselves.
//
// Aggregator only — the assigner is the sole owner of state; this file
// never mutates anything.

library;

import 'dart:math' as math;

import 'hand_track.dart' show HandTrackFrameState, TrackStatus;

/// Aggregated continuity metrics over a multi-frame tracking session.
final class TrackContinuity {
  TrackContinuity._({
    required this.tracksObserved,
    required this.tracksLost,
    required this.idChanges,
    required this.maxJitterNormalized,
    required this.totalProcessingDuration,
  });

  final int tracksObserved;
  final int tracksLost;
  final int idChanges;
  final double maxJitterNormalized;
  final Duration totalProcessingDuration;

  /// Aggregate a list of frame snapshots into a single [TrackContinuity].
  ///
  /// The processing wall-clock is sourced from each frame's
  /// `processingDuration` (the assigner wraps a `Stopwatch` around its
  /// `process` body). An optional `processingDurations` override is
  /// kept for callers that want to measure elsewhere (tests, custom
  /// transports); when supplied it replaces the per-frame values.
  static TrackContinuity aggregate(
    List<HandTrackFrameState> frames, {
    List<Duration>? processingDurations,
  }) {
    final idsObserved = <int>{};
    var tracksLost = 0;
    var idChanges = 0;
    var maxJitter = 0.0;
    var totalDuration = Duration.zero;

    final seenIdsPerHandedness = <String, Set<int>>{};

    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i];
      final override =
          processingDurations != null && i < processingDurations.length
          ? processingDurations[i]
          : null;
      totalDuration += override ?? frame.processingDuration;
      for (final track in frame.tracks) {
        idsObserved.add(track.id);
        if (track.status == TrackStatus.lost) {
          tracksLost++;
          continue;
        }
        maxJitter = math.max(maxJitter, track.rawSmoothedDeltaNormalized);
        final key = track.handedness.name;
        seenIdsPerHandedness.putIfAbsent(key, () => <int>{}).add(track.id);
      }
    }

    for (final entry in seenIdsPerHandedness.values) {
      // If more than one ID ever coexisted under the same handedness
      // key, count the extra IDs as churn — the brief's "should never
      // happen" target is 0.
      if (entry.length > 1) idChanges += entry.length - 1;
    }

    return TrackContinuity._(
      tracksObserved: idsObserved.length,
      tracksLost: tracksLost,
      idChanges: idChanges,
      maxJitterNormalized: maxJitter,
      totalProcessingDuration: totalDuration,
    );
  }
}
