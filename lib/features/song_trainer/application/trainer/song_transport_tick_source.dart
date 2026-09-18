/// Periodic "the playhead moved" signal for [SongTransport] (E16-R01/A4).
///
/// MEASURED gap this closes: the transport computed `activePosition` from its
/// stopwatch correctly, but only ever PUBLISHED a new state when the backing
/// audio player emitted a `BackingPositionEvent`. A song with no backing
/// track — which is every song the importer and the editor can produce, since
/// neither attaches audio — therefore produced exactly zero state updates
/// while "playing", so the Stage's lanes and highway stood still at 0:00.
///
/// The contract is deliberately identical to the Practice engine's
/// `PracticeTickSource` (ADR 0077 §6): the source is NOT auto-started, the
/// owner decides when to start and stop it, and production uses a 16 ms
/// (≈60 Hz) period while tests inject a deterministic driver. It is a
/// separate type rather than a cross-feature import so the Song Trainer keeps
/// its own dependency surface.
library;

import 'dart:async';

/// A controllable source of periodic playhead ticks.
abstract interface class SongTransportTickSource {
  /// Whether the source is currently producing ticks.
  bool get isRunning;

  /// Begin emitting ticks to [onTick]. Idempotent — repeated calls while
  /// already running are no-ops.
  void start(void Function() onTick);

  /// Stop emitting ticks. Idempotent — safe before [start] or after a prior
  /// [stop]. Ticks already in flight are not invoked.
  void stop();
}

/// Production [SongTransportTickSource] backed by a [Timer.periodic].
final class TimerSongTransportTickSource implements SongTransportTickSource {
  /// Constructs a source with the given [period] (default ≈60 Hz).
  TimerSongTransportTickSource({
    this.period = const Duration(milliseconds: 16),
  });

  /// Tick interval.
  final Duration period;

  Timer? _timer;
  void Function()? _onTick;

  @override
  bool get isRunning => _timer != null;

  @override
  void start(void Function() onTick) {
    if (_timer != null) return;
    _onTick = onTick;
    _timer = Timer.periodic(period, (_) => _onTick?.call());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
    _onTick = null;
  }
}

/// Test double whose ticks are driven by hand.
final class ManualSongTransportTickSource implements SongTransportTickSource {
  void Function()? _onTick;

  /// Number of [start] calls the owner has made.
  int startedCount = 0;

  /// Number of [stop] calls the owner has made.
  int stoppedCount = 0;

  @override
  bool get isRunning => _onTick != null;

  @override
  void start(void Function() onTick) {
    if (_onTick != null) return;
    _onTick = onTick;
    startedCount++;
  }

  @override
  void stop() {
    if (_onTick == null) return;
    _onTick = null;
    stoppedCount++;
  }

  /// Fires one tick when the source is running.
  void tick() => _onTick?.call();
}
