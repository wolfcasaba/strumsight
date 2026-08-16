/// Versioned, deterministic configuration for candidate selection
/// (ADR 0297, SDD Ch8 Kör 13).
///
/// The policy never reads a clock and never generates randomness. Every
/// weight is validated at construction and surfaced as an immutable field
/// so a generated plan can retain the exact selection provenance after the
/// values are tuned. The exploration seed is **not** part of the policy —
/// it is a per-call input supplied by the caller (ADR 0259 §1, brief §5.3).
library;

/// Controls the normalized weights applied during candidate ranking, plus the
/// relevance window that lets the deterministic diversity/exploration tie
/// break kick in.
final class CandidatePolicy {
  CandidatePolicy({
    String version = 'candidate-policy-v1',
    this.recentOverusePenalty = 0.2,
    this.diversityWindow = 0.05,
    this.explorationWeight = 0.0,
    this.difficultyWeight = 0.0,
    this.preferenceWeight = 0.0,
    this.measurabilityWeight = 0.0,
  }) : version = _requireText(version, 'version') {
    _requireUnitInterval(recentOverusePenalty, 'recentOverusePenalty');
    _requireNonNegativeFinite(diversityWindow, 'diversityWindow');
    _requireUnitInterval(explorationWeight, 'explorationWeight');
    _requireUnitInterval(difficultyWeight, 'difficultyWeight');
    _requireUnitInterval(preferenceWeight, 'preferenceWeight');
    _requireUnitInterval(measurabilityWeight, 'measurabilityWeight');
    if (diversityWindow > 1) {
      throw ArgumentError.value(
        diversityWindow,
        'diversityWindow',
        'must be within [0, 1]',
      );
    }
  }

  const CandidatePolicy._default()
    : version = 'candidate-policy-v1',
      recentOverusePenalty = 0.2,
      diversityWindow = 0.05,
      explorationWeight = 0,
      difficultyWeight = 0,
      preferenceWeight = 0,
      measurabilityWeight = 0;

  /// Default policy for this initial selection contract. All candidate-level
  /// soft-factor weights and `explorationWeight` are `0` so the default
  /// contract reproduces the prior lexical behavior with no soft-factor
  /// noise. Activate soft factors explicitly via a custom policy.
  static const CandidatePolicy defaultPolicy = CandidatePolicy._default();

  /// Stable identifier retained by [CandidateDecision] as selection
  /// provenance (ADR 0297 §5).
  final String version;

  /// Signed penalty subtracted from `relevanceScore` when the candidate's
  /// identity is in the caller's `recentlyUsedIdentities` set (brief A7).
  final double recentOverusePenalty;

  /// Inclusive maximum `compositeScore` drop, relative to the top candidate,
  /// within which the diversity/exploration tie break may rearrange the
  /// order (ADR 0297 §3). A value of `0` collapses the tie-break window to
  /// strict equality; `1` permits any candidate targeting the skill.
  final double diversityWindow;

  /// Toggles the deterministic seed-based permutation inside the
  /// [diversityWindow] bucket. `0` → strict lexical order, the seed never
  /// affects the winner. Positive values → the seed drives a deterministic
  /// permutation of the bucket with a lexical tie-break, still bounded by
  /// the [diversityWindow] so the chosen candidate can never outscore the
  /// canonical top of the bucket (ADR 0297 §3).
  final double explorationWeight;

  /// Weight applied to [CandidateRankingProfile.difficultyAffinity] when
  /// computing the candidate-specific composite score (brief §3, A3).
  final double difficultyWeight;

  /// Weight applied to [CandidateRankingProfile.preferenceAffinity] when
  /// computing the candidate-specific composite score (brief §3, A3).
  final double preferenceWeight;

  /// Weight applied to [CandidateRankingProfile.measurabilityScore] when
  /// computing the candidate-specific composite score (brief §3, A3).
  final double measurabilityWeight;
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}

void _requireUnitInterval(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, name, 'must be finite and within [0, 1]');
  }
}

void _requireNonNegativeFinite(double value, String name) {
  if (!value.isFinite || value < 0) {
    throw ArgumentError.value(value, name, 'must be finite and non-negative');
  }
}
