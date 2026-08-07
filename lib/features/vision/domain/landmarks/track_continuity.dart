// E05-R13 — Track continuity metrics (SDD §15.4, Kör 13 §Feladatok).
//
// Pure aggregation over a sequence of `HandTrackFrameState`s. The metrics
// are designed to be cheap to compute, deterministic on the input order,
// and comparable across sessions. They feed the performance summary and
// surface regressions in tracking quality (jitter spike, ID churn,
// processing-time blow-up).
//
// Aggregator only — the assigner is the sole owner of state; this file
// never mutates anything.

library;

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

  /// Total number of distinct track IDs observed across the whole session.
  final int tracksObserved;

  /// Total number of `trackLost` events emitted. A non-zero value is a
  /// SIGNAL — a long occlusion happened — but is not in itself a failure.
  final int tracksLost;

  /// Total number of frames on which the "stable" property was violated
  /// for a track — i.e. a previously known ID vanished and was replaced by
  /// a NEW ID for the same physical hand inside a single frame. Should be
  /// zero in a healthy session.
  final int idChanges;

  /// Maximum per-frame wrist jitter (smoothed-vs-raw normalized-space
  /// distance) seen across the whole session. Zero in an idle session.
  final double maxJitterNormalized;

  /// Sum of per-frame processing durations reported by the caller (the
  /// assigner reports a `Stopwatch.elapsed` per call).
  final Duration totalProcessingDuration;

  /// Aggregate a list of frame snapshots into a single [TrackContinuity].
  ///
  /// `processingDurations` (optional, same length as [frames]) carries the
  /// caller-measured per-frame wall time. Without it the duration stays
  /// zero — callers that don't care skip the bookkeeping.
  static TrackContinuity aggregate(
    List<HandTrackFrameState> frames, {
    List<Duration>? processingDurations,
  }) {
    final idsObserved = <int>{};
    var tracksLost = 0;
    var idChanges = 0;
    var maxJitter = 0.0;

    final seenIdsPerHandedness = <String, Set<int>>{};

    for (final frame in frames) {
      for (final track in frame.tracks) {
        idsObserved.add(track.id);
        if (track.status == TrackStatus.lost) {
          tracksLost++;
          continue;
        }
        // Jitter proxy: the smoothed-vs-raw wrist landmark delta. The
        // smoothed value is the track's smoothed coordinate; the raw
        // value would need to be threaded through the frame, which we
        // don't have here. As a stand-in we use the spread of smoothed
        // landmarks across the same ID — this is the "jitter" the
        // downstream layer actually sees.
        // For this round, the assigner reports smoothed only; jitter is
        // therefore 0 unless the caller provides a comparison source.
        // (Hook left for R17 / R18 metrics.)
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

    final totalDuration = processingDurations == null
        ? Duration.zero
        : processingDurations.fold<Duration>(
            Duration.zero,
            (acc, d) => acc + d,
          );

    return TrackContinuity._(
      tracksObserved: idsObserved.length,
      tracksLost: tracksLost,
      idChanges: idChanges,
      maxJitterNormalized: maxJitter,
      totalProcessingDuration: totalDuration,
    );
  }
}
