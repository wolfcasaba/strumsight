import 'package:meta/meta.dart';

/// Snapshot of the three numbers that drive the streak-eligibility predicate.
///
/// The values come straight from the session — never from the wall clock or
/// any frame estimate. The defaults match the SDD §20.5 contract.
@immutable
final class PracticeSessionEligibilityInput {
  const PracticeSessionEligibilityInput({
    required this.activeDuration,
    required this.resolvedRequiredTargets,
    required this.freePracticeStrums,
  });

  /// Active time accumulated during the session — `playingElapsed`.
  final Duration activeDuration;

  /// Number of required (non-optional) targets that received a resolution.
  final int resolvedRequiredTargets;

  /// Number of strum observations recorded in a Free Practice session.
  final int freePracticeStrums;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeSessionEligibilityInput &&
          other.activeDuration == activeDuration &&
          other.resolvedRequiredTargets == resolvedRequiredTargets &&
          other.freePracticeStrums == freePracticeStrums;

  @override
  int get hashCode =>
      Object.hash(activeDuration, resolvedRequiredTargets, freePracticeStrums);
}

/// Pure, deterministic streak-eligibility predicate (SDD §20.5, ADR 0082 §7).
///
/// ```text
/// eligible = activeDuration >= 20 s
///         || resolvedRequiredTargets >= 4
///         || freePracticeStrums >= 8
/// ```
///
/// All three thresholds are `>=` (inclusive). The predicate is intentionally
/// wiring-free — no provider, no consumer, no DB writes; the binding lives in
/// the streak-only round (E02-R19).
@immutable
final class PracticeSessionEligibility {
  const PracticeSessionEligibility();

  /// The threshold an active session must reach to qualify.
  static const Duration activeDurationThreshold = Duration(seconds: 20);

  /// The threshold of required-target hits that qualifies a session.
  static const int resolvedRequiredTargetsThreshold = 4;

  /// The threshold of free-practice strums that qualifies as "made progress".
  static const int freePracticeStrumsThreshold = 8;

  /// Whether the supplied snapshot qualifies.
  bool isEligible(PracticeSessionEligibilityInput input) =>
      input.activeDuration >= activeDurationThreshold ||
      input.resolvedRequiredTargets >= resolvedRequiredTargetsThreshold ||
      input.freePracticeStrums >= freePracticeStrumsThreshold;
}
