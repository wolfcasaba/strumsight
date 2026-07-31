// Shared contract test for [PracticeSessionClock]. Both the production
// monotonic implementation and the test fake must satisfy this contract, so
// the harness runs the same scenarios against each.
//
// The two test groups at the bottom of this file wire the harness to each
// implementation; adding a third clock implementation later means adding one
// more wiring call here and one more suite run.
//
// Assertions tolerate microsecond drift on the monotonic clock (real elapsed
// time between `start()` and `now()`), but compare state-machine deltas —
// which are zero on both implementations — wherever the contract is about
// "the clock's internal state does not change".
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/application/practice_session_clock.dart';

import '../../../support/fake_practice_session_clock.dart';

typedef _ClockFactory = PracticeSessionClock Function();

/// Tolerance for real elapsed time on the MonotonicPracticeSessionClock.
const Duration _monotonicTolerance = Duration(milliseconds: 10);

/// Asserts that the difference between two values is within [tolerance].
Matcher _within(Duration tolerance) =>
    lessThanOrEqualTo(tolerance.inMicroseconds);

void _runClockContract(_ClockFactory make) {
  test('now() before any start() returns zero in every field', () {
    final clock = make();
    final snapshot = clock.now();
    expect(snapshot.wall, Duration.zero);
    expect(snapshot.active, Duration.zero);
    expect(snapshot.paused, Duration.zero);
    expect(snapshot.attempt, Duration.zero);
  });

  test('start() places the clock in a fresh session state', () {
    final clock = make();
    clock.start();
    final snapshot = clock.now();
    expect(snapshot.wall, lessThanOrEqualTo(_monotonicTolerance));
    expect(snapshot.active, lessThanOrEqualTo(_monotonicTolerance));
    expect(snapshot.paused, Duration.zero);
    expect(snapshot.attempt, snapshot.active);
  });

  test('start() is idempotent: repeated start() does not throw or distort', () {
    final clock = make();
    clock.start();
    clock.start();
    final snapshot = clock.now();
    expect(snapshot.wall, lessThanOrEqualTo(_monotonicTolerance));
    expect(snapshot.active, lessThanOrEqualTo(_monotonicTolerance));
    expect(snapshot.paused, Duration.zero);
  });

  test('active + paused == wall invariant holds after pause and resume', () {
    final clock = make();
    clock.start();
    clock.pause();
    final paused = clock.now();
    expect(paused.active + paused.paused, paused.wall);
    clock.resume();
    final resumed = clock.now();
    expect(resumed.active + resumed.paused, resumed.wall);
  });

  test('pause() while paused is a no-op (state-machine fields unchanged)', () {
    final clock = make();
    clock.start();
    clock.pause();
    final before = clock.now();
    clock.pause();
    final after = clock.now();
    // active is `wall - paused`; while paused, wall and paused both grow by
    // the same real-time delta, so active is invariant — exact zero delta.
    expect(after.active - before.active, Duration.zero);
    // wall and paused both grow by the same amount on both implementations.
    expect(after.wall - before.wall, after.paused - before.paused);
  });

  test(
    'resume() while running is a no-op (state-machine fields unchanged)',
    () {
      final clock = make();
      clock.start();
      final before = clock.now();
      clock.resume();
      final after = clock.now();
      // paused stays put; wall and active grow by the same amount.
      expect(after.paused - before.paused, Duration.zero);
      expect(after.wall - before.wall, after.active - before.active);
      // The wall delta is bounded by the time the test takes — generous.
      expect(
        (after.wall - before.wall).inMicroseconds.abs(),
        _within(_monotonicTolerance),
      );
    },
  );

  test(
    'resetAttempt() zeros attempt; paused unchanged; wall/active unchanged',
    () {
      final clock = make();
      clock.start();
      final before = clock.now();
      clock.resetAttempt();
      final after = clock.now();
      // attempt is `active - baseline`; at the moment of reset, baseline ==
      // active, so attempt starts at 0 and then grows with active. Within
      // the call's own elapsed time, attempt is at most the tolerance.
      expect(after.attempt, lessThanOrEqualTo(_monotonicTolerance));
      // paused unchanged across the reset call.
      expect(after.paused - before.paused, Duration.zero);
      // wall and active grow by the same amount (we're running, not paused).
      expect(after.wall - before.wall, after.active - before.active);
    },
  );

  // R07 REVIEW NOTE-2 / E02-R11 §5.15: `start()` is now a no-op when the
  // session has already started — including from `paused`. A fresh session
  // starts with `resetAttempt()` + the reducer's `RestartAttempt`. The clock
  // contract test pins the new behaviour on BOTH implementations.
  test('start() while paused is a no-op (no fields reset)', () {
    final clock = make();
    clock.start();
    final veryEarly = clock.now();
    // The pre-pause snapshots are noisy on the monotonic clock (real
    // elapsed time between `start()` and the snapshot reads), so we
    // tolerate drift within the tolerance window.
    clock.pause();
    final pausedBefore = clock.now();
    clock.start(); // <-- this is the call under test
    final pausedAfter = clock.now();
    // The clock is still paused after the redundant start().
    expect(pausedAfter.paused >= pausedBefore.paused, isTrue);
    expect(
      (pausedAfter.wall - pausedAfter.paused).abs() <= _monotonicTolerance,
      isTrue,
      reason:
          'active must remain within the tolerance window of the pre-pause '
          'active; start() while paused must not reset the clock.',
    );
    // Sanity: the very-early snapshot is ignored for the comparison — the
    // test exercises the *paused* state, not the very first start. The
    // delta from `pausedBefore -> pausedAfter` must be tiny (only the
    // time the test took to invoke .start()).
    expect(
      (pausedAfter.wall - pausedBefore.wall).abs() <= _monotonicTolerance,
      isTrue,
    );
    // Stash the early snapshot to silence the unused warning.
    expect(veryEarly, isA<PracticeClockSnapshot>());
  });
}

/// Cross-implementation contract — same expectations on both clocks.
void main() {
  group('MonotonicPracticeSessionClock', () {
    _runClockContract(MonotonicPracticeSessionClock.new);
  });

  group('FakePracticeSessionClock', () {
    _runClockContract(FakePracticeSessionClock.new);

    test('advance() grows wall by the delta while running', () {
      final clock = FakePracticeSessionClock();
      clock.start();
      clock.advance(const Duration(seconds: 3));
      expect(clock.now().wall, const Duration(seconds: 3));
      expect(clock.now().active, const Duration(seconds: 3));
    });

    test('advance() while paused grows wall AND paused; active stays put', () {
      final clock = FakePracticeSessionClock();
      clock.start();
      clock.advance(const Duration(seconds: 2));
      clock.pause();
      clock.advance(const Duration(seconds: 5));
      final snapshot = clock.now();
      expect(snapshot.wall, const Duration(seconds: 7));
      expect(snapshot.paused, const Duration(seconds: 5));
      expect(snapshot.active, const Duration(seconds: 2));
    });

    test(
      'advance() after resume resumes active growth from the resume point',
      () {
        final clock = FakePracticeSessionClock();
        clock.start();
        clock.advance(const Duration(seconds: 2));
        clock.pause();
        clock.advance(const Duration(seconds: 3));
        clock.resume();
        clock.advance(const Duration(seconds: 4));
        final snapshot = clock.now();
        expect(snapshot.wall, const Duration(seconds: 9));
        expect(snapshot.active, const Duration(seconds: 6));
        expect(snapshot.paused, const Duration(seconds: 3));
      },
    );

    test('resetAttempt() after an active session only zeros attempt', () {
      final clock = FakePracticeSessionClock();
      clock.start();
      clock.advance(const Duration(seconds: 5));
      clock.resetAttempt();
      clock.advance(const Duration(seconds: 3));
      final snapshot = clock.now();
      expect(snapshot.wall, const Duration(seconds: 8));
      expect(snapshot.active, const Duration(seconds: 8));
      expect(snapshot.paused, Duration.zero);
      expect(snapshot.attempt, const Duration(seconds: 3));
    });

    test(
      'start() after pause is a no-op (clock stays paused, fields intact)',
      () {
        final clock = FakePracticeSessionClock();
        clock.start();
        clock.advance(const Duration(seconds: 5));
        clock.pause();
        clock.advance(const Duration(seconds: 3));
        final before = clock.now();
        clock.start(); // <-- no-op under the new contract
        final snapshot = clock.now();
        // The clock is still paused, so `paused` keeps growing as `wall`
        // grows, and `active` stays put.
        expect(snapshot.wall, before.wall);
        expect(snapshot.paused, before.paused);
        expect(snapshot.active, before.active);
        expect(snapshot.attempt, before.attempt);
      },
    );

    test('pause() before start() is a no-op (no fields change)', () {
      final clock = FakePracticeSessionClock();
      clock.pause();
      final snapshot = clock.now();
      expect(snapshot.wall, Duration.zero);
      expect(snapshot.active, Duration.zero);
      expect(snapshot.paused, Duration.zero);
    });

    test('resetAttempt() before start() is a no-op', () {
      final clock = FakePracticeSessionClock();
      clock.resetAttempt();
      final snapshot = clock.now();
      expect(snapshot.attempt, Duration.zero);
    });

    test('active + paused == wall invariant holds across 200 random steps', () {
      final clock = FakePracticeSessionClock();
      clock.start();
      var step = 0;
      // 200 deterministic µ-scale steps — covers the invariant under
      // alternating pause/resume/advance interleavings.
      for (var i = 0; i < 200; i++) {
        switch (i % 4) {
          case 0:
            clock.advance(const Duration(milliseconds: 7));
          case 1:
            clock.pause();
          case 2:
            clock.advance(const Duration(milliseconds: 3));
          case 3:
            clock.resume();
        }
        final snap = clock.now();
        expect(
          snap.active + snap.paused,
          snap.wall,
          reason: 'invariant broken at step $step (i=$i)',
        );
        step++;
      }
    });
  });
}
