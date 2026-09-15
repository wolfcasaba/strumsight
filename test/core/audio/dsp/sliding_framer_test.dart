import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/dsp/sliding_framer.dart';

/// E01-R10 §10.3 — [SlidingFramer] is the first DSP file to cross into the
/// shared audio boundary (the Live pipeline and the Tuner engine both re-frame
/// mic chunks with it). It had no direct test, only pipeline-level coverage,
/// so the move comes with one: framing is where an off-by-one silently shifts
/// every downstream analysis window.
void main() {
  List<double> ramp(int n, {int from = 0}) =>
      List<double>.generate(n, (i) => (from + i).toDouble());

  test('a short chunk yields nothing and is buffered', () {
    final framer = SlidingFramer(window: 4, hop: 2);
    expect(framer.add(ramp(3)).toList(), isEmpty);
    // The 4th sample completes the first frame from the buffered remainder.
    final frames = framer.add(ramp(1, from: 3)).toList();
    expect(frames, hasLength(1));
    expect(frames.single, [0, 1, 2, 3]);
  });

  test('frames advance by hop, not by window', () {
    final framer = SlidingFramer(window: 4, hop: 2);
    final frames = framer.add(ramp(8)).toList();
    expect(frames.map((f) => f.toList()), [
      [0, 1, 2, 3],
      [2, 3, 4, 5],
      [4, 5, 6, 7],
    ]);
  });

  test('hop == window gives non-overlapping frames', () {
    final framer = SlidingFramer(window: 3, hop: 3);
    expect(framer.add(ramp(6)).map((f) => f.toList()), [
      [0, 1, 2],
      [3, 4, 5],
    ]);
  });

  test('framing is continuous across chunk boundaries', () {
    // The mic delivers arbitrary chunk sizes; the frame grid must not restart.
    final framer = SlidingFramer(window: 4, hop: 2);
    final all = <List<double>>[
      ...framer.add(ramp(5)).map((f) => f.toList()),
      ...framer.add(ramp(5, from: 5)).map((f) => f.toList()),
    ];
    expect(all, [
      [0, 1, 2, 3],
      [2, 3, 4, 5],
      [4, 5, 6, 7],
      [6, 7, 8, 9],
    ]);
  });

  test('the tail shorter than one hop is retained, not dropped', () {
    final framer = SlidingFramer(window: 4, hop: 4);
    expect(framer.add(ramp(6)).map((f) => f.toList()), [
      [0, 1, 2, 3],
    ]);
    // Samples 4,5 stayed buffered: feeding two more completes the next frame.
    expect(framer.add(ramp(2, from: 6)).map((f) => f.toList()), [
      [4, 5, 6, 7],
    ]);
  });

  test('reset drops the buffered remainder', () {
    final framer = SlidingFramer(window: 4, hop: 2);
    expect(framer.add(ramp(3)).toList(), isEmpty);
    framer.reset();
    expect(framer.add(ramp(3, from: 100)).toList(), isEmpty);
    final frames = framer.add(ramp(1, from: 103)).map((f) => f.toList());
    expect(frames, [
      [100, 101, 102, 103],
    ]);
  });

  test('an empty chunk is a no-op', () {
    final framer = SlidingFramer(window: 2, hop: 1);
    expect(framer.add(const []).toList(), isEmpty);
  });

  test('hop larger than the window is rejected', () {
    expect(
      () => SlidingFramer(window: 2, hop: 3),
      throwsA(isA<AssertionError>()),
    );
  });

  // D4: the framer's pending store grows by doubling, so a mic chunk many
  // times the window (audio_streamer delivers 6400 samples against a 1024
  // onset window) must be framed in one call without losing or reordering a
  // sample — and the capacity it grew to must still be reusable afterwards.
  test('a chunk far larger than the window frames in one call', () {
    final framer = SlidingFramer(window: 4, hop: 2);
    final frames = framer.add(ramp(20)).map((f) => f.toList()).toList();
    expect(frames, hasLength(9));
    expect(frames.first, [0, 1, 2, 3]);
    expect(frames.last, [16, 17, 18, 19]);
    // The tail (sample 18,19 — one hop short of a frame) survives into the
    // next, much smaller chunk, on the same grid.
    expect(framer.add(ramp(2, from: 20)).map((f) => f.toList()), [
      [18, 19, 20, 21],
    ]);
  });

  test('a typed chunk frames identically to a plain list', () {
    final typed = SlidingFramer(window: 4, hop: 2);
    final plain = SlidingFramer(window: 4, hop: 2);
    expect(
      typed.add(Float64List.fromList(ramp(8))).map((f) => f.toList()),
      plain.add(ramp(8)).map((f) => f.toList()),
    );
  });

  test('each emitted frame is a fresh buffer, never a recycled one', () {
    // Downstream consumers retain frames (the strum classifier keeps a
    // post-onset evidence ring), so recycling one output buffer would rewrite
    // their history — the frames must stay independent objects.
    final framer = SlidingFramer(window: 4, hop: 2);
    final frames = framer.add(ramp(8)).toList();
    expect(identical(frames[0], frames[1]), isFalse);
    framer.add(ramp(8, from: 8)).toList();
    expect(frames[0], [0, 1, 2, 3]);
    expect(frames[1], [2, 3, 4, 5]);
  });
}
