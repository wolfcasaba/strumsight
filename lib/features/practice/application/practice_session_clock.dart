import 'package:meta/meta.dart';

/// Monotonic snapshot of the practice session clock at one instant.
///
/// Invariant — measured by `practice_session_clock_test.dart`:
/// `active + paused == wall` at every snapshot.
///
/// `attempt` is the `active` time accumulated since the last
/// [PracticeSessionClock.resetAttempt] call.
@immutable
final class PracticeClockSnapshot {
  const PracticeClockSnapshot({
    required this.wall,
    required this.active,
    required this.paused,
    required this.attempt,
  });

  const PracticeClockSnapshot.zero()
    : wall = Duration.zero,
      active = Duration.zero,
      paused = Duration.zero,
      attempt = Duration.zero;

  /// Total time elapsed since [PracticeSessionClock.start], **including** time
  /// spent paused. Driven by a monotonic [Stopwatch] in production.
  final Duration wall;

  /// `wall - paused` — the time the session was actually advancing.
  final Duration active;

  /// Accumulated time spent paused since the last [start] call.
  final Duration paused;

  /// `active` accumulated since the most recent [resetAttempt] call.
  final Duration attempt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeClockSnapshot &&
          other.wall == wall &&
          other.active == active &&
          other.paused == paused &&
          other.attempt == attempt;

  @override
  int get hashCode => Object.hash(wall, active, paused, attempt);

  @override
  String toString() =>
      'PracticeClockSnapshot(wall: $wall, active: $active, '
      'paused: $paused, attempt: $attempt)';
}

/// A monotonic clock driving the practice session state machine.
///
/// Lives under `application/` (not `domain/`) because it depends on the
/// ambient [Stopwatch]; the domain-purity test forbids `Stopwatch` from
/// `domain/` and this clock is intentionally impure (it reads time).
///
/// The clock is idempotent: repeated [start] / [pause] / [resume] calls in
/// already-active / already-paused / already-running states do not throw and
/// do not distort the snapshot fields.
abstract interface class PracticeSessionClock {
  /// Returns a fresh monotonic snapshot.
  PracticeClockSnapshot now();

  /// Begins a new session, zeroing every accumulator. A no-op when already
  /// running (idempotent). If invoked while paused, restarts the session
  /// fresh.
  void start();

  /// Pauses the running session; idempotent when already paused (or before
  /// the first [start]).
  void pause();

  /// Resumes a paused session; idempotent when already running (or before
  /// the first [start]).
  void resume();

  /// Zeros only the [PracticeClockSnapshot.attempt] accumulator; leaves
  /// `wall`/`active`/`paused` untouched.
  void resetAttempt();
}

/// Production [PracticeSessionClock] driven by a single monotonic
/// [Stopwatch]. `DateTime.now()` is intentionally avoided.
///
/// The internal [Stopwatch] runs continuously between [start] calls so that
/// `wall` keeps growing even while the session is paused. The `paused`
/// accumulator is recomputed on every snapshot from the running totals
/// `_pausedTotal` (sum of *completed* pause durations) plus the in-progress
/// pause interval — see [pausedAt] for the pure formula.
final class MonotonicPracticeSessionClock implements PracticeSessionClock {
  final Stopwatch _stopwatch = Stopwatch();
  Duration _pausedTotal = Duration.zero;
  Duration _lastTransitionWall = Duration.zero;
  Duration _attemptBaseline = Duration.zero;
  bool _isPaused = false;
  bool _hasStarted = false;

  @override
  PracticeClockSnapshot now() => _snapshot();

  @override
  void start() {
    if (_hasStarted && !_isPaused) return;
    _stopwatch
      ..reset()
      ..start();
    _pausedTotal = Duration.zero;
    _lastTransitionWall = Duration.zero;
    _attemptBaseline = Duration.zero;
    _isPaused = false;
    _hasStarted = true;
  }

  @override
  void pause() {
    if (!_hasStarted || _isPaused) return;
    // Mark the boundary — `_pausedTotal` does not grow here because the
    // just-completed active interval's duration is captured by
    // `_lastTransitionWall`. The new pause interval starts now.
    _lastTransitionWall = _stopwatch.elapsed;
    _isPaused = true;
  }

  @override
  void resume() {
    if (!_hasStarted || !_isPaused) return;
    // Close out the in-progress pause interval and add its length to the
    // accumulated total. Active intervals contribute nothing to
    // `_pausedTotal`; only their endpoints are recorded in
    // `_lastTransitionWall`.
    _pausedTotal += _stopwatch.elapsed - _lastTransitionWall;
    _lastTransitionWall = _stopwatch.elapsed;
    _isPaused = false;
  }

  @override
  void resetAttempt() {
    if (!_hasStarted) return;
    final wall = _stopwatch.elapsed;
    final paused = pausedAt(wall, _pausedTotal, _isPaused, _lastTransitionWall);
    _attemptBaseline = wall - paused;
  }

  PracticeClockSnapshot _snapshot() {
    final wall = _hasStarted ? _stopwatch.elapsed : Duration.zero;
    final paused = _hasStarted
        ? pausedAt(wall, _pausedTotal, _isPaused, _lastTransitionWall)
        : Duration.zero;
    final active = wall - paused;
    return PracticeClockSnapshot(
      wall: wall,
      active: active,
      paused: paused,
      attempt: active - _attemptBaseline,
    );
  }
}

/// Pure helper — `pausedAt` is the running total of `pausedTotal` plus the
/// in-progress pause interval (`wall − lastTransitionWall`) when the clock
/// is currently paused. Exposed at top level so tests can validate the
/// formula without instantiating the clock.
Duration pausedAt(
  Duration wall,
  Duration pausedTotal,
  bool isPaused,
  Duration lastTransitionWall,
) =>
    pausedTotal +
    (isPaused && wall > lastTransitionWall
        ? wall - lastTransitionWall
        : Duration.zero);
