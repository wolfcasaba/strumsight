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
/// stayed uncertain (ADR 0505 D3) — never the raw exception text. The six
/// `signal*` members mirror the six non-`good` `SignalQualityState`s
/// one-to-one (ADR 0535 D1): a merged "signal quality" bucket carried a
/// single piece of advice that was wrong for half the states it covered, so
/// a collector/"other" tag is forbidden here.
enum RecognitionRejectReason {
  lowConfidence,

  /// Chord-level instability: the recognized chord keeps changing. NOT a
  /// signal-level problem — see [signalUnstable] for a swinging input level.
  unstable,

  /// Mirrors `SignalQualityState.tooQuiet` (ADR 0535 D1): the input level is
  /// under the quiet threshold.
  signalTooQuiet,

  /// Mirrors `SignalQualityState.tooLoud` (ADR 0535 D1): the input peak is
  /// over the loud threshold (clipping already excluded).
  signalTooLoud,

  /// Mirrors `SignalQualityState.clipping` (ADR 0535 D1): too many samples
  /// are pinned at full scale.
  signalClipping,

  /// Mirrors `SignalQualityState.tooNoisy` (ADR 0535 D1): tonalness is under
  /// the noisy ceiling — mostly noise, not a chord.
  signalTooNoisy,

  /// Mirrors `SignalQualityState.speechLike` (ADR 0535 D1): tonalness sits in
  /// the speech-like band, never a speaker/source classification.
  signalSpeechLike,

  /// Mirrors `SignalQualityState.unstable` (ADR 0535 D1): the input LEVEL is
  /// swinging. Deliberately distinct from [unstable], which is about the
  /// chord verdict — the two mean different things and must not be merged.
  signalUnstable,

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
