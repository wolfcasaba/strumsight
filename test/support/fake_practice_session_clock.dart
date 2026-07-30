import 'package:strumsight/features/practice/application/practice_session_clock.dart';

/// Deterministic [PracticeSessionClock] for tests — no [Stopwatch], no
/// ambient time. The caller drives the clock with [advance].
///
/// Honours the same contract as [MonotonicPracticeSessionClock]:
/// `active + paused == wall` at every snapshot; [start] / [pause] / [resume]
/// are idempotent.
final class FakePracticeSessionClock implements PracticeSessionClock {
  Duration _wall = Duration.zero;
  Duration _pausedTotal = Duration.zero;
  Duration _lastTransitionWall = Duration.zero;
  Duration _attemptBaseline = Duration.zero;
  bool _isPaused = false;
  bool _hasStarted = false;

  /// Whether the clock is currently in a running (non-paused) state.
  bool get isRunning => _hasStarted && !_isPaused;

  /// Advances the wall clock by [delta]. Safe to call in any state — a
  /// paused clock advances both `wall` and the in-progress `paused`
  /// interval.
  void advance(Duration delta) {
    if (delta <= Duration.zero) return;
    _wall += delta;
  }

  @override
  PracticeClockSnapshot now() {
    final paused = pausedAt(
      _wall,
      _pausedTotal,
      _isPaused,
      _lastTransitionWall,
    );
    final active = _wall - paused;
    return PracticeClockSnapshot(
      wall: _wall,
      active: active,
      paused: paused,
      attempt: active - _attemptBaseline,
    );
  }

  @override
  void start() {
    if (_hasStarted && !_isPaused) return;
    _wall = Duration.zero;
    _pausedTotal = Duration.zero;
    _lastTransitionWall = Duration.zero;
    _attemptBaseline = Duration.zero;
    _isPaused = false;
    _hasStarted = true;
  }

  @override
  void pause() {
    if (!_hasStarted || _isPaused) return;
    _lastTransitionWall = _wall;
    _isPaused = true;
  }

  @override
  void resume() {
    if (!_hasStarted || !_isPaused) return;
    _pausedTotal += _wall - _lastTransitionWall;
    _lastTransitionWall = _wall;
    _isPaused = false;
  }

  @override
  void resetAttempt() {
    if (!_hasStarted) return;
    _attemptBaseline = now().active;
  }
}
