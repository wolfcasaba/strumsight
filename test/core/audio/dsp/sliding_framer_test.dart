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
}
