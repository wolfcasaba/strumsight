// E05-R19 — StrokeWindow tests (brief §6 acceptance cells).
//
// The window contract (brief §5/3):
//
//   - pre-onset and post-onset windows are SEPARATE constants,
//   - the window MUST NOT extend into the next onset's pre-window —
//     when two onsets are too close, the previous window is TRUNCATED
//     at the next onset's timestamp and the truncation is SIGNALLED.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/domain/metrics/stroke_window.dart';

void main() {
  // A minimal PickingFrameLike implementation for the window tests —
  // the window logic only reads `timestamp`.
  final windowImpl = const StrokeWindow();

  PickingFrameLike at(int ms) => _TestFrame(Duration(milliseconds: ms));

  group('non-overlapping onsets', () {
    test('each onset yields a window of pre+post length, no truncation', () {
      final frames = <PickingFrameLike>[
        at(0),
        at(50),
        at(150),
        at(300),
        at(400),
        at(550),
        at(600),
        at(750),
        at(900),
      ];
      final cuts = windowImpl.cut(
        frames: frames,
        onsets: const [
          PickingOnsetEvent(timestamp: Duration(milliseconds: 200)),
          PickingOnsetEvent(timestamp: Duration(milliseconds: 700)),
        ],
      );
      expect(cuts.length, 2);
      expect(cuts[0].window.truncated, isFalse);
      expect(cuts[0].window.start, const Duration(milliseconds: 100));
      expect(cuts[0].window.end, const Duration(milliseconds: 350));
      expect(
        cuts[0].samples.map((s) => s.timestamp.inMilliseconds).toList(),
        <int>[150, 300],
      );

      expect(cuts[1].window.truncated, isFalse);
      expect(cuts[1].window.start, const Duration(milliseconds: 600));
      expect(cuts[1].window.end, const Duration(milliseconds: 850));
      expect(
        cuts[1].samples.map((s) => s.timestamp.inMilliseconds).toList(),
        <int>[600, 750],
      );
    });

    test('windows are sorted by onset even if onsets arrive unsorted', () {
      final cuts = windowImpl.cut(
        frames: const <PickingFrameLike>[],
        onsets: const [
          PickingOnsetEvent(timestamp: Duration(milliseconds: 700)),
          PickingOnsetEvent(timestamp: Duration(milliseconds: 200)),
        ],
      );
      expect(cuts.length, 2);
      expect(cuts[0].window.onset, const Duration(milliseconds: 200));
      expect(cuts[1].window.onset, const Duration(milliseconds: 700));
    });
  });

  group('overlapping onsets — truncation (brief §6)', () {
    test('post window of first onset is cut at the next onset pre-window '
        'start', () {
      // Two onsets 130 ms apart, pre=100, post=150. The first window's
      // requested end is onset_0 + 150 = 150 ms. The next onset's REQUESTED
      // start is onset_1 - pre = 130 - 100 = 30 ms, which is BEFORE the
      // current window's requested end. The window is therefore truncated
      // to 30 ms (NOT 130 ms — truncating at the next onset's raw
      // timestamp would leak the `[30, 130)` band into BOTH adjacent
      // windows, which is the F1 BLOCKER fixed by this round).
      // `duration = end - start = 30 - (-100) = 130 ms` — strictly less
      // than the un-truncated 250 ms the same window would have produced
      // if the next onset were further away (the §6 falsification
      // contract).
      final cuts = windowImpl.cut(
        frames: const <PickingFrameLike>[],
        onsets: const [
          PickingOnsetEvent(timestamp: Duration(milliseconds: 0)),
          PickingOnsetEvent(timestamp: Duration(milliseconds: 130)),
        ],
      );
      expect(cuts[0].window.truncated, isTrue);
      expect(
        cuts[0].window.end,
        const Duration(milliseconds: 30),
        reason: 'cut at the next onset\'s pre-window start',
      );
      expect(
        cuts[0].window.duration,
        const Duration(milliseconds: 130),
        reason: 'cut window is shorter than the full 250 ms pre+post',
      );
      expect(cuts[1].window.truncated, isFalse);
      expect(cuts[1].window.duration, const Duration(milliseconds: 250));
    });

    test('samples after the cut boundary are NOT included in window N', () {
      // Two onsets 300 ms apart — no truncation (window 1 ends at 250,
      // window 2 starts at 200, the gap is fine). Tests that the
      // half-open `[start, end)` interval drops the sample at 251 even
      // though it falls inside window 2's start..post range.
      final cuts = windowImpl.cut(
        frames: <PickingFrameLike>[
          at(50),
          at(249), // last frame inside window 1 [0, 250)
          at(251), // first frame OUTSIDE window 1
          at(300),
          at(399),
        ],
        onsets: const [
          PickingOnsetEvent(timestamp: Duration(milliseconds: 100)),
          PickingOnsetEvent(timestamp: Duration(milliseconds: 400)),
        ],
      );
      expect(cuts[0].window.truncated, isFalse);
      expect(
        cuts[0].samples.map((s) => s.timestamp.inMilliseconds).toList(),
        <int>[50, 249],
      );
      expect(cuts[1].window.truncated, isFalse);
      expect(
        cuts[1].samples.map((s) => s.timestamp.inMilliseconds).toList(),
        <int>[300, 399],
      );
    });

    test('six-on-130ms toggle truncates all but the last window', () {
      // Each onset 130 ms apart — the next onset's pre-window start
      // (`nextOnset - 100`) always falls inside the current window
      // (post=150, pre=100, full window=250). Truncation therefore fires
      // for windows 0..4. Only the last window survives intact. The
      // fast-toggle threshold is determined by the gap to the next
      // onset's pre-window start vs. the post window (150 ms); any
      // rhythm below (post + pre) ≈ 250 ms triggers truncation, this
      // fixture pins that contract.
      //
      // The cut point is the NEXT window's REQUESTED start
      // (`nextOnset - pre`), NOT the next onset's raw timestamp — so
      // adjacent windows are guaranteed to share no samples (F1 fix).
      final cuts = windowImpl.cut(
        frames: const <PickingFrameLike>[],
        onsets: const [
          PickingOnsetEvent(timestamp: Duration(milliseconds: 0)),
          PickingOnsetEvent(timestamp: Duration(milliseconds: 130)),
          PickingOnsetEvent(timestamp: Duration(milliseconds: 260)),
          PickingOnsetEvent(timestamp: Duration(milliseconds: 390)),
          PickingOnsetEvent(timestamp: Duration(milliseconds: 520)),
          PickingOnsetEvent(timestamp: Duration(milliseconds: 650)),
        ],
      );
      expect(cuts.length, 6);
      for (var i = 0; i < 5; i++) {
        expect(
          cuts[i].window.truncated,
          isTrue,
          reason: 'window $i should be truncated',
        );
        expect(
          cuts[i].window.end,
          cuts[i + 1].window.start,
          reason: 'window $i cut at next window pre-start (no overlap)',
        );
      }
      expect(cuts[5].window.truncated, isFalse);
      expect(cuts[5].window.duration, const Duration(milliseconds: 250));
    });

    test('two simultaneous onsets: first window is empty, second is empty '
        'after truncation', () {
      final cuts = windowImpl.cut(
        frames: const <PickingFrameLike>[],
        onsets: const [
          PickingOnsetEvent(timestamp: Duration(milliseconds: 100)),
          PickingOnsetEvent(timestamp: Duration(milliseconds: 100)),
        ],
      );
      expect(cuts[0].window.truncated, isTrue);
      expect(cuts[0].samples, isEmpty);
      expect(cuts[1].samples, isEmpty);
    });

    test('fast-toggle fixture: adjacent windows share NO sample timestamps '
        '(F1 BLOCKER regression guard)', () {
      // The review F1 BLOCKER proved that the previous cut (at the
      // next onset's RAW timestamp) let the `[nextOnset - pre, nextOnset)`
      // band appear in BOTH adjacent windows' samples lists. The fix
      // truncates at the next window's REQUESTED start, so the boundary
      // is a real partition. This test pins that contract with REAL
      // samples (not empty `frames: []`) and asserts the actual sample
      // SETS are disjoint for every adjacent pair — the brief §6
      // "a mintaszám assertálva" requirement.
      //
      // The fixture mirrors `FastToggleStrokes.sixAt130ms()`: 6 onsets
      // 130 ms apart, frames every 33 ms from -100 to 791 (= 27 frames).
      // Window 0 cover [−100, 30), window 1 [30, 160), …, window 5
      // [550, 800). Adjacent windows share no timestamp.
      final frames = [for (var t = -100; t <= 791; t += 33) at(t)];
      final cuts = windowImpl.cut(
        frames: frames,
        onsets: const [
          PickingOnsetEvent(timestamp: Duration(milliseconds: 0)),
          PickingOnsetEvent(timestamp: Duration(milliseconds: 130)),
          PickingOnsetEvent(timestamp: Duration(milliseconds: 260)),
          PickingOnsetEvent(timestamp: Duration(milliseconds: 390)),
          PickingOnsetEvent(timestamp: Duration(milliseconds: 520)),
          PickingOnsetEvent(timestamp: Duration(milliseconds: 650)),
        ],
      );
      expect(cuts.length, 6);
      // Sanity: adjacent windows have at least one sample each (else
      // the test would be vacuously true).
      for (var i = 0; i < cuts.length; i++) {
        expect(
          cuts[i].samples,
          isNotEmpty,
          reason:
              'window $i must have at least one sample for the '
              'overlap check to be meaningful',
        );
      }
      // The actual F1 regression guard: every adjacent pair has
      // EMPTY intersection of timestamp SETS.
      for (var i = 0; i < cuts.length - 1; i++) {
        final left = cuts[i].samples
            .map((s) => s.timestamp.inMicroseconds)
            .toSet();
        final right = cuts[i + 1].samples
            .map((s) => s.timestamp.inMicroseconds)
            .toSet();
        final overlap = left.intersection(right);
        expect(
          overlap,
          isEmpty,
          reason:
              'windows $i and ${i + 1} MUST share no sample timestamps '
              '(F1 BLOCKER); actually shared: $overlap',
        );
      }
    });

    test(
      'every sample is included in EXACTLY one window (global partition)',
      () {
        // Stronger F1 invariant: across the whole `FastToggleStrokes`
        // timeline, every frame belongs to exactly one window — no frame
        // is dropped AND no frame is duplicated.
        final frames = [for (var t = -100; t <= 791; t += 33) at(t)];
        final cuts = windowImpl.cut(
          frames: frames,
          onsets: const [
            PickingOnsetEvent(timestamp: Duration(milliseconds: 0)),
            PickingOnsetEvent(timestamp: Duration(milliseconds: 130)),
            PickingOnsetEvent(timestamp: Duration(milliseconds: 260)),
            PickingOnsetEvent(timestamp: Duration(milliseconds: 390)),
            PickingOnsetEvent(timestamp: Duration(milliseconds: 520)),
            PickingOnsetEvent(timestamp: Duration(milliseconds: 650)),
          ],
        );
        final allReturned = [
          for (final cut in cuts) ...cut.samples,
        ].map((s) => s.timestamp.inMicroseconds).toList();
        expect(
          allReturned.length,
          frames.length,
          reason:
              'every frame must appear in exactly one window — '
              'no drops, no duplicates',
        );
        final returnedSet = allReturned.toSet();
        expect(
          returnedSet.length,
          frames.length,
          reason: 'no frame may appear in two windows (F1 BLOCKER)',
        );
      },
    );
  });

  group('default vs overridden window size', () {
    test('overriding post shrinks the window and may avoid truncation', () {
      // Same 130-ms-apart onsets as above, but with post=20 so window 0
      // ends at 20, which is BEFORE the next onset's pre-window start
      // (130 - pre = 130 - 100 = 30). No truncation — the small `post`
      // keeps the window above the partition boundary. With the
      // default post=150 the window would extend to 150 and the cut
      // would land at 30 (the F1 fix boundary).
      final overrides = const StrokeWindow(
        defaultPre: Duration(milliseconds: 100),
        defaultPost: Duration(milliseconds: 20),
      );
      final cuts = overrides.cut(
        frames: const <PickingFrameLike>[],
        onsets: const [
          PickingOnsetEvent(timestamp: Duration(milliseconds: 0)),
          PickingOnsetEvent(timestamp: Duration(milliseconds: 130)),
        ],
      );
      expect(cuts[0].window.truncated, isFalse);
      expect(cuts[0].window.duration, const Duration(milliseconds: 120));
    });

    test('overriding pre widens the window without violating the post cap', () {
      final overrides = const StrokeWindow(
        defaultPre: Duration(milliseconds: 200),
        defaultPost: Duration(milliseconds: 150),
      );
      final cuts = overrides.cut(
        frames: const <PickingFrameLike>[],
        onsets: const [
          PickingOnsetEvent(timestamp: Duration(milliseconds: 500)),
        ],
      );
      expect(cuts[0].window.start, const Duration(milliseconds: 300));
      expect(cuts[0].window.end, const Duration(milliseconds: 650));
      expect(cuts[0].window.duration, const Duration(milliseconds: 350));
    });
  });

  group('empty / degenerate inputs', () {
    test('no onsets → empty result', () {
      final cuts = windowImpl.cut(
        frames: [at(0), at(100)],
        onsets: const <PickingOnsetEvent>[],
      );
      expect(cuts, isEmpty);
    });

    test('no frames, single onset → empty samples', () {
      final cuts = windowImpl.cut(
        frames: const <PickingFrameLike>[],
        onsets: const [
          PickingOnsetEvent(timestamp: Duration(milliseconds: 200)),
        ],
      );
      expect(cuts.length, 1);
      expect(cuts[0].samples, isEmpty);
      expect(cuts[0].window.truncated, isFalse);
      expect(cuts[0].window.duration, const Duration(milliseconds: 250));
    });

    test(
      'onset with no nearby frames → empty samples, window still defined',
      () {
        final cuts = windowImpl.cut(
          frames: [at(0), at(1000)],
          onsets: const [
            PickingOnsetEvent(timestamp: Duration(milliseconds: 500)),
          ],
        );
        expect(cuts.length, 1);
        expect(cuts[0].samples, isEmpty);
        expect(cuts[0].window.duration, const Duration(milliseconds: 250));
      },
    );
  });
}

class _TestFrame implements PickingFrameLike {
  const _TestFrame(this.timestamp);
  @override
  final Duration timestamp;
}
