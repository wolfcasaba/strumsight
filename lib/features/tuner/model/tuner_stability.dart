/// Derives the "unstable" tuner state that has no field on the estimator's
/// own output (brief §0.0/R5.1 — the estimator's `TunerReading` carries only
/// note/cents/frequency, never a stability flag). A reading that jumps far
/// from the previous one for the SAME note reads as a transient (a fresh
/// pluck, a finger squeak, a bend settling) rather than a pitch worth
/// reacting to yet. Pure and count-free (like [InTuneLock]) so it is
/// deterministic in tests regardless of the tuner's frame rate.
class TunerStability {
  /// A same-note cents jump beyond this is "unstable", not just noisy.
  static const double jumpThreshold = 12;

  String? _note;
  double? _cents;

  /// Feed one (possibly silent) reading. Returns true when this reading
  /// jumped too far from the immediately preceding reading of the SAME note.
  /// A note change or silence resets the tracker (no stale comparison across
  /// notes) and never itself counts as unstable.
  bool feed({
    required bool hasSignal,
    required String note,
    required double cents,
  }) {
    if (!hasSignal) {
      _note = null;
      _cents = null;
      return false;
    }
    final prevNote = _note;
    final prevCents = _cents;
    final unstable =
        prevNote == note &&
        prevCents != null &&
        (cents - prevCents).abs() > jumpThreshold;
    _note = note;
    _cents = cents;
    return unstable;
  }
}
