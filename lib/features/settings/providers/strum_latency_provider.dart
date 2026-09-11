import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/persisted_preference.dart';
import '../../../core/storage/storage_keys.dart';

/// Calibrated **pendulum↔strum** offset in MILLISECONDS, for the rhythm
/// exercise's timing score. Persisted; local-only (a property of THIS device's
/// display and audio path). `null`-equivalent 0 means uncalibrated, and an
/// uncalibrated device gets **no timing score at all** rather than a guessed one.
///
/// ## Why a third latency preference and not one of the existing two
///
/// [inputLatencyProvider] and [visualLatencyProvider] are both TAP-based: the
/// learner taps the screen against a click, or against a flash. Each therefore
/// carries the device's TOUCH latency, which is why the Learn highway uses only
/// their DIFFERENCE — touch cancels there, leaving the audio↔display skew.
///
/// The rhythm exercise's pair is different in both channels: its reference is
/// the PENDULUM (display out) and its response is a STRUM heard by the
/// MICROPHONE (audio in). Touch latency is not in it at all, audio-out is not in
/// it at all, and the quantity cannot be derived from the other two — so reusing
/// either would mean applying a systematically wrong offset to a score, which is
/// worse than applying none.
///
/// ## What this number actually contains, stated plainly
///
/// It is NOT "device latency". It is the offset between **what this learner
/// feels as together** and **what the engine reports**, and it deliberately
/// includes their own anticipation.
///
/// Humans do not synchronise by reacting; they predict, and tap 20-100 ms BEFORE
/// the pacing signal — negative mean asynchrony, one of the most robust findings
/// in the sensorimotor synchronisation literature. That anticipation is present
/// in the calibration strums AND in the exercise strums, by the same person, so
/// subtracting the calibration removes it from the score. That is the desired
/// behaviour: calibrating out only hardware latency would leave every learner on
/// earth reading as 20-100 ms early, and the app would be calling normal human
/// timing a fault.
///
/// The cost of that choice, said out loud: the timing score then measures
/// steadiness relative to the learner's own sense of "together", NOT absolute
/// alignment to the grid. For a beginner that is the right target. It also means
/// the calibration is personal, not transferable — and since anticipation grows
/// with slower tempi, a calibration taken at one tempo is only approximate at
/// another. That tempo dependence is **not measured** here.
class StrumLatencyNotifier extends Notifier<int> with PersistedPreference<int> {
  static const defaultValue = 0;

  /// Wider than the tap-based keys' ±300 ms is not needed, and a narrower band
  /// is safer: an offset this large would mean the measurement, not the device.
  static const minMs = -300;
  static const maxMs = 300;

  @override
  int build() {
    final v = preferences.readInt(StorageKeys.strumLatencyMs);
    return v == null ? defaultValue : v.clamp(minMs, maxMs);
  }

  Future<void> set(int ms) async {
    state = ms.clamp(minMs, maxMs);
    await persist(
      StorageKeys.strumLatencyMs,
      (store) => store.writeInt(StorageKeys.strumLatencyMs, state),
    );
  }
}

final strumLatencyProvider = NotifierProvider<StrumLatencyNotifier, int>(
  StrumLatencyNotifier.new,
);
