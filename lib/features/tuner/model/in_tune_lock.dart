/// The "string locked in" detector (round 85, GuitarTuna-class feel): one
/// in-tune reading is noise; HOLDING it is the achievement. Pure and
/// count-based (no clock) so it is deterministic in tests regardless of the
/// tuner's frame rate.
class InTuneLock {
  /// Consecutive in-tune readings of the same note required to lock.
  static const int holdReadings = 6;

  int _held = 0;
  String _note = '';
  bool _locked = false;

  bool get isLocked => _locked;

  /// Feed one tuner reading. Returns true exactly ONCE, on the reading that
  /// engages the lock — the caller fires the celebration (haptic/pulse) then.
  /// Out-of-tune readings or a different note re-arm the detector.
  bool feed({required bool inTune, required String note}) {
    if (!inTune || note != _note) {
      _note = note;
      _held = inTune ? 1 : 0;
      _locked = false;
      return false;
    }
    _held++;
    if (!_locked && _held >= holdReadings) {
      _locked = true;
      return true;
    }
    return false;
  }
}
