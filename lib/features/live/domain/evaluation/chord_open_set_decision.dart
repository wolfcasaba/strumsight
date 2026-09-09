/// Open-set chord decision: "no chord", "a chord I do not support", or a
/// supported class (E14-R32, ADR 0540).
///
/// The shipped chord vocabulary is CLOSED — 24 maj/min classes plus N.C.
/// (`assets/ml/model_manifest.json`, `output_classes`). A sus4, add9 or 7th
/// chord is therefore not merely mis-scored: it has no correct answer at
/// all, and today the decoder must name the nearest maj/min anyway. That is
/// the "confidently wrong" class (ADR 0271 §1), and this file is the
/// mechanism that lets the pipeline say `unknown` instead.
///
/// Three honesty properties are structural here:
///
/// 1. **`noChord` and `unknown` are different answers.** `noChord` means
///    nothing is sounding; `unknown` means something IS sounding and the
///    model has no class for it. They never collapse into one state, and
///    `recognition_metrics.dart` already scores them with two different
///    metrics (`chordNoChordF1` vs `chordUnknownFalseAccept`).
/// 2. **No threshold is invented here.** Every floor is an explicit input.
///    The shipped default is [ChordOpenSetPolicy.disabled], which is the
///    IDENTITY on today's behaviour — it can return neither `noChord` nor
///    `unknown`, so wiring this function in changes nothing until a MEASURED
///    policy is supplied (ADR 0540 D4).
/// 3. **The decision is a pure function of the evidence it names**
///    (`winSim`, `margin`, and the N.C. floor), so it is fully testable
///    without audio and cannot silently depend on engine state.
library;

/// The three answers of the open-set decision.
enum ChordOpenSetOutcome {
  /// Nothing is sounding — the `N.C.` state.
  noChord,

  /// Something is sounding, but the winning class is not trustworthy enough
  /// to name: either the evidence is weak, or two classes are too close.
  unknownChord,

  /// The winning class may be named.
  supportedChord,
}

/// The evidence the decision reads.
///
/// [winSim] and [margin] are the SAME quantities the DSP chord matcher
/// already computes (`chord_matcher.dart`: `winSim` = the winning template's
/// similarity, `margin` = `(best − second) / best`); the ML path supplies
/// the analogous posterior maximum and its normalised gap. Both are
/// expected in `0..1`; values outside that range are an
/// [ArgumentError], never clamped silently.
final class ChordOpenSetEvidence {
  ChordOpenSetEvidence({required this.winSim, required this.margin}) {
    _requireUnitInterval(winSim, 'winSim');
    _requireUnitInterval(margin, 'margin');
  }

  /// Similarity/posterior of the winning chord class.
  final double winSim;

  /// Relative gap between the winning and the runner-up class.
  final double margin;

  static void _requireUnitInterval(double value, String name) {
    if (value.isNaN || value < 0 || value > 1) {
      throw ArgumentError.value(value, name, 'must be a number inside 0..1');
    }
  }
}

/// The floors the decision compares the evidence against.
///
/// Every field is a REQUIRED input with no default: a threshold that nobody
/// measured must not be able to hide inside this type.
final class ChordOpenSetPolicy {
  const ChordOpenSetPolicy({
    required this.noChordSimilarityFloor,
    required this.unknownSimilarityFloor,
    required this.unknownMarginFloor,
  });

  /// The shipped default: no floor at all, so the decision is always
  /// [ChordOpenSetOutcome.supportedChord] — byte-for-byte today's
  /// behaviour (see the library doc, property 2).
  const ChordOpenSetPolicy.disabled()
    : noChordSimilarityFloor = 0,
      unknownSimilarityFloor = 0,
      unknownMarginFloor = 0;

  /// N.C. only: keeps the caller's existing no-chord floor and never emits
  /// [ChordOpenSetOutcome.unknownChord]. Use while the unknown floors are
  /// still NEEDS-MEASUREMENT.
  const ChordOpenSetPolicy.noChordOnly({required double similarityFloor})
    : noChordSimilarityFloor = similarityFloor,
      unknownSimilarityFloor = 0,
      unknownMarginFloor = 0;

  /// Below this winning similarity, nothing is sounding (`N.C.`).
  final double noChordSimilarityFloor;

  /// At or above [noChordSimilarityFloor] but below this, something is
  /// sounding that the model cannot name.
  final double unknownSimilarityFloor;

  /// Even a strong winner is `unknown` when the runner-up is this close.
  final double unknownMarginFloor;

  /// `false` when the policy can never produce
  /// [ChordOpenSetOutcome.unknownChord] — the state this round ships in.
  bool get emitsUnknown => unknownSimilarityFloor > 0 || unknownMarginFloor > 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'noChordSimilarityFloor': noChordSimilarityFloor,
    'unknownSimilarityFloor': unknownSimilarityFloor,
    'unknownMarginFloor': unknownMarginFloor,
  };
}

/// Decides between `noChord`, `unknown` and a supported class.
///
/// Evaluation order — first match wins, and the order is part of the
/// contract:
///
/// 1. `winSim < noChordSimilarityFloor` → [ChordOpenSetOutcome.noChord];
/// 2. `winSim < unknownSimilarityFloor` → [ChordOpenSetOutcome.unknownChord];
/// 3. `margin < unknownMarginFloor` → [ChordOpenSetOutcome.unknownChord];
/// 4. otherwise → [ChordOpenSetOutcome.supportedChord].
///
/// Both comparisons are strict, so a value exactly ON a floor belongs to the
/// more informative side — the same "boundary belongs to the accepting side"
/// convention the release gate uses (ADR 0511 D3).
ChordOpenSetOutcome decideChordOpenSet({
  required ChordOpenSetEvidence evidence,
  required ChordOpenSetPolicy policy,
}) {
  if (evidence.winSim < policy.noChordSimilarityFloor) {
    return ChordOpenSetOutcome.noChord;
  }
  if (evidence.winSim < policy.unknownSimilarityFloor) {
    return ChordOpenSetOutcome.unknownChord;
  }
  if (evidence.margin < policy.unknownMarginFloor) {
    return ChordOpenSetOutcome.unknownChord;
  }
  return ChordOpenSetOutcome.supportedChord;
}
