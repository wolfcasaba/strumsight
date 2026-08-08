// E05-R19 — Stroke window (SDD §20.1).
//
// The window is the time interval around an audio-onset event from which the
// picking metric engine extracts a stroke trajectory. The contract is
// EXPLICIT (brief §5/3):
//
//   - pre-window and post-window are SEPARATE constants,
//   - the window MUST NOT extend into the next onset's pre-window — when
//     two onsets are too close, the previous window is TRUNCATED at the
//     next onset's pre-window start (i.e. `nextOnset - pre`) and the
//     truncation is SIGNALLED so the downstream code can decide whether
//     to use the truncated window (most cases) or discard it (rare
//     alignment work).
//
// The truncation point is the NEXT onset's REQUESTED start, NOT its raw
// timestamp — without that, a sample in the `[nextOnset - pre, nextOnset)`
// band would appear in BOTH adjacent windows' `samples` lists, and a
// downstream `_pathSegments` over the duplicated sample would inflate the
// path length for two windows simultaneously, distorting amplitude / speed /
// linearity (the E05-R19 review F1 BLOCKER). Truncating at the next pre-
// window start guarantees the partition is a true partition: for any
// timestamp `t`, `t` appears in at most one `PickingStrokeCut.samples` list.
//
// The constants are public and override-able per-call so the §6 fast-toggle
// fixture can shrink `post` without losing the §5 contract. The truncation
// rule is the same regardless of the constants — a stricter window just
// makes truncation more likely.

library;

/// A single audio-onset event fed into the picking metric engine.
///
/// The audio path produces this list (R21 wires the real source); in this
/// round the engine accepts the list INJECTED, so tests and future callers
/// can build it directly.
final class PickingOnsetEvent {
  const PickingOnsetEvent({required this.timestamp});

  final Duration timestamp;
}

/// The cut of all frames belonging to a single onset's stroke window.
///
/// `start` / `end` are the actual window bounds — they may differ from the
// requested `pre` / `post` constants if the next onset caused a truncation.
/// `truncated` is `true` iff the window was cut short by the next onset.
final class PickingStrokeWindow {
  const PickingStrokeWindow({
    required this.onset,
    required this.start,
    required this.end,
    required this.truncated,
  });

  final Duration onset;
  final Duration start;
  final Duration end;
  final bool truncated;

  Duration get duration => end - start;
}

/// Cuts a sequence of frames into one window per onset, applying the
/// brief §5/3 truncation rule.
///
/// `defaultPre` and `defaultPost` define the window size; a per-onset
/// override is exposed via [windowFor] for tests that want to drive the
/// engine from the fixtures.
final class StrokeWindow {
  const StrokeWindow({
    this.defaultPre = const Duration(milliseconds: 100),
    this.defaultPost = const Duration(milliseconds: 150),
  });

  /// The default pre-onset window length. The 100 ms constant is short
  /// enough that picking pre-motion dominates the signal but long enough
  /// to capture the pre-velocity peak in a typical strum.
  final Duration defaultPre;

  /// The default post-onset window length. The 150 ms constant is short
  /// enough that the typical fast-toggle (≈ 167 ms period) does NOT
  /// overlap the next onset's pre-window — but borderline cases do
  /// trigger truncation, which is exactly what the brief §6 acceptance
  /// cell asserts.
  final Duration defaultPost;

  /// Cut frames into one window per onset.
  ///
  /// Frames are sorted by timestamp (insertion order is preserved — the
  /// caller is expected to feed a monotonic series as the engine does for
  /// every other SDD §20 metric). Each onset's window is the half-open
  /// interval `[onset - pre, onset + post)` intersected with the
  /// half-open interval `[onset - pre, nextOnset - pre)` so the next
  /// onset's pre-window CANNOT leak into the current window. The cut
  /// point is therefore the next onset's REQUESTED start, not its raw
  /// timestamp — without that, samples in `[nextOnset - pre, nextOnset)`
  /// would belong to both windows.
  ///
  /// Returns one [PickingStrokeWindow] per onset in input order, each
  /// paired with the frames that fell inside the cut interval. An onset
  /// whose window contains zero frames is still returned (with empty
  /// `frames`) so the caller can iterate 1-to-1 with the onsets list.
  List<PickingStrokeCut> cut({
    required List<PickingFrameLike> frames,
    required List<PickingOnsetEvent> onsets,
    Duration? preOverride,
    Duration? postOverride,
  }) {
    final pre = preOverride ?? defaultPre;
    final post = postOverride ?? defaultPost;
    final sortedOnsets = [...onsets]
      ..sort(
        (a, b) =>
            a.timestamp.inMicroseconds.compareTo(b.timestamp.inMicroseconds),
      );
    final result = <PickingStrokeCut>[];
    for (var i = 0; i < sortedOnsets.length; i++) {
      final onset = sortedOnsets[i];
      final requestedStart = onset.timestamp - pre;
      final requestedEnd = onset.timestamp + post;
      // The next window's REQUESTED start (not its raw timestamp) is the
      // truncation boundary. This guarantees no sample is shared between
      // two adjacent windows (E05-R19 F1 BLOCKER).
      final nextRequestStart = i + 1 < sortedOnsets.length
          ? sortedOnsets[i + 1].timestamp - pre
          : null;
      Duration actualEnd;
      bool truncated;
      if (nextRequestStart != null &&
          nextRequestStart.inMicroseconds < requestedEnd.inMicroseconds) {
        actualEnd = nextRequestStart;
        truncated = true;
      } else {
        actualEnd = requestedEnd;
        truncated = false;
      }
      final samples = <PickingFrameLike>[];
      for (final frame in frames) {
        final ts = frame.timestamp;
        if (ts.inMicroseconds >= requestedStart.inMicroseconds &&
            ts.inMicroseconds < actualEnd.inMicroseconds) {
          samples.add(frame);
        }
      }
      result.add(
        PickingStrokeCut(
          window: PickingStrokeWindow(
            onset: onset.timestamp,
            start: requestedStart,
            end: actualEnd,
            truncated: truncated,
          ),
          samples: samples,
        ),
      );
    }
    return result;
  }
}

/// One onset's cut: the [PickingStrokeWindow] metadata plus the
/// `PickingFrameLike` samples that fell inside.
final class PickingStrokeCut {
  const PickingStrokeCut({required this.window, required this.samples});

  final PickingStrokeWindow window;
  final List<PickingFrameLike> samples;
}

/// Minimal interface the [StrokeWindow] needs from a frame — only the
/// timestamp. The full `PickingFrame` (defined in `picking_metric_engine.dart`)
/// satisfies this implicitly because it exposes a `timestamp` field; the
/// structural type is fine for the window logic, which never inspects
/// landmarks.
abstract interface class PickingFrameLike {
  Duration get timestamp;
}
