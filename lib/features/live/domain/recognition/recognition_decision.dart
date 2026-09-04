/// Closed set of states a recognizer's verdict can be in for one signal
/// (strum direction this round; chord in a later round) — SDD Ch14 Kör 4,
/// ADR 0505 D3. The domain computes this from its own inputs; the UI only
/// displays it (ADR 0271 §1: `UNKNOWN > CONFIDENTLY WRONG`).
enum RecognitionDecision {
  /// A verdict is forming but hasn't cleared any threshold yet.
  candidate,

  /// Leaning toward a verdict, not yet stable enough to confirm.
  provisional,

  /// Cleared every threshold — the UI may show it.
  confirmed,

  /// Below the confirmation threshold — the UI must show "unsure", never a
  /// guess dressed up as a verdict.
  uncertain,

  /// Actively rejected; see the paired [RecognitionRejectReason].
  rejected,

  /// Was confirmed, then aged out.
  expired;

  /// The wire form used by every contract file's `toJson`.
  String toJson() => name;

  /// Decodes a persisted decision without guessing a safe fallback — an
  /// unrecognised name is a typed error, never a silent `null` (ADR 0505 D6).
  static RecognitionDecision fromJson(Object? value) {
    if (value is! String) {
      throw ArgumentError.value(value, 'decision', 'must be a string');
    }
    for (final decision in RecognitionDecision.values) {
      if (decision.name == value) return decision;
    }
    throw ArgumentError.value(value, 'decision', 'is not a supported value');
  }
}

/// Closed, machine-checkable reasons a [RecognitionDecision] rejected or
/// stayed uncertain (ADR 0505 D3) — never the raw exception text.
enum RecognitionRejectReason {
  lowConfidence,
  unstable,
  signalQuality,
  noChord,
  modelUnavailable,
  timeout;

  /// The wire form used by every contract file's `toJson`.
  String toJson() => name;

  /// Decodes a persisted reject reason without guessing a safe fallback — an
  /// unrecognised name is a typed error, never a silent `null` (ADR 0505 D6).
  static RecognitionRejectReason fromJson(Object? value) {
    if (value is! String) {
      throw ArgumentError.value(value, 'rejectReason', 'must be a string');
    }
    for (final reason in RecognitionRejectReason.values) {
      if (reason.name == value) return reason;
    }
    throw ArgumentError.value(
      value,
      'rejectReason',
      'is not a supported value',
    );
  }
}
