import 'dart:async';

/// A controllable source of periodic "clock tick" signals for the practice
/// session controller (ADR 0077 §6).
///
/// Each tick fires [PracticeTickSource.onTick] exactly once. The controller
/// converts that into a [ClockAdvanced] signal — never directly into a
/// scoring pass (SDD §24.1).
///
/// The source is **not** auto-started; the controller decides when to
/// start and stop it. Production uses a 16 ms period; tests inject a
/// deterministic driver.
abstract interface class PracticeTickSource {
  /// Number of [start] calls the controller has made on this source.
  int get startedCount;

  /// Number of [stop] calls the controller has made on this source.
  int get stoppedCount;

  /// Whether the source is currently producing ticks.
  bool get isRunning;

  /// Begin emitting ticks to [onTick]. Idempotent — repeated calls while
  /// already running are no-ops.
  void start(void Function() onTick);

  /// Stop emitting ticks. Idempotent — safe to call before [start] or
  /// after a prior [stop]. Ticks that are already in-flight at the moment
  /// of [stop] are not invoked.
  void stop();
}

/// Production [PracticeTickSource] backed by a [Timer.periodic].
///
/// Uses a 16 ms period (≈60 Hz) — the same cadence the legacy
/// `learn_screen.dart` ticker drives. The timer is held on the controller
/// (in production the controller is owned by a Riverpod provider, so the
/// timer lives for the lifetime of the provider scope).
final class TimerPracticeTickSource implements PracticeTickSource {
  TimerPracticeTickSource({this.period = const Duration(milliseconds: 16)});

  final Duration period;
  Timer? _timer;
  void Function()? _onTick;

  @override
  int startedCount = 0;

  @override
  int stoppedCount = 0;

  @override
  bool get isRunning => _timer != null;

  @override
  void start(void Function() onTick) {
    if (_timer != null) return;
    _onTick = onTick;
    _timer = Timer.periodic(period, (_) {
      _onTick?.call();
    });
    startedCount++;
  }

  @override
  void stop() {
    final timer = _timer;
    if (timer == null) return;
    timer.cancel();
    _timer = null;
    _onTick = null;
    stoppedCount++;
  }
}
