import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen awake during a playing session, behind an interface so
/// screens never call the plugin directly (SDD Ch2 §5.1/10) and a test can
/// assert that the wakelock was actually RELEASED (Kör 9 §9.4).
abstract interface class ScreenWakelock {
  Future<void> enable();

  Future<void> disable();
}

/// The real one. Plugin errors are swallowed on purpose: a device without the
/// wakelock channel (host tests, desktop) must not break a practice session —
/// the wakelock is a comfort feature, never a correctness one.
final class WakelockPlusScreenWakelock implements ScreenWakelock {
  const WakelockPlusScreenWakelock();

  @override
  Future<void> enable() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // Best effort — see the class doc.
    }
  }

  @override
  Future<void> disable() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {
      // Best effort — see the class doc.
    }
  }
}
