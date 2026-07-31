import 'package:strumsight/features/practice/application/practice_tick_source.dart';

/// Deterministic [PracticeTickSource] for tests — no [Timer], no ambient
/// time. The caller drives the tick stream with [emitTick].
///
/// [start]/[stop] mirror the production contract: idempotent, counted.
final class FakePracticeTickSource implements PracticeTickSource {
  void Function()? _onTick;

  @override
  int startedCount = 0;

  @override
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

  /// Fires one tick to the currently registered listener. No-op when the
  /// source is stopped.
  void emitTick() {
    _onTick?.call();
  }
}
