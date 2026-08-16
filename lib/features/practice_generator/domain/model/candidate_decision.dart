/// Immutable, explainable outcome of one candidate-selection step
/// (SDD Ch8 Kör 13, ADR 0297).
///
/// The decision is the single source of truth for "what was chosen, why, and
/// what was rejected" — it never re-derives text or explanations after the
/// fact. Every list inside is sorted by a stable key so the same inputs always
/// produce the same decision bytes (A4/A8).
library;

import 'exercise_candidate.dart';

/// The stable, machine-readable reason a candidate was rejected during the
/// hard-filter step (ADR 0297 §2). The codes are persisted for diagnostic
/// reporting and never carry free-text learner data.
enum CandidateRejectReason {
  hardAvoid('candidate.reject.hardAvoid'),
  offlineUnconfirmed('candidate.reject.offlineUnconfirmed'),
  assetUnconfirmed('candidate.reject.assetUnconfirmed'),
  deviceCapabilityUnconfirmed('candidate.reject.deviceCapabilityUnconfirmed'),
  tuningUnconfirmed('candidate.reject.tuningUnconfirmed');

  const CandidateRejectReason(this.code);

  final String code;

  static CandidateRejectReason fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'CandidateRejectReason',
  );

  @override
  String toString() => code;
}

/// Independent contributors to a [SelectedCandidate.compositeScore].
///
/// The score is the explainable output of the selector; diversity and
/// exploration are tie-breaks, never score modifiers (ADR 0297 §3).
enum CandidateFactorKind {
  relevance('candidate.factor.relevance'),
  difficulty('candidate.factor.difficulty'),
  preference('candidate.factor.preference'),
  measurability('candidate.factor.measurability'),
  recentOveruse('candidate.factor.recentOveruse');

  const CandidateFactorKind(this.code);

  final String code;

  static CandidateFactorKind fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'CandidateFactorKind',
  );

  @override
  String toString() => code;
}

/// Typed, caller-supplied, normalized affinities for one candidate that the
/// selector combines with the corresponding [CandidatePolicy] weights to
/// produce a candidate-specific composite score (ADR 0297 §3).
///
/// The default [_neutral] profile has every affinity at zero so it never
/// contributes unless the caller populates a non-default profile AND the
/// policy enables the matching weight.
final class CandidateRankingProfile {
  CandidateRankingProfile._({
    required this.difficultyAffinity,
    required this.preferenceAffinity,
    required this.measurabilityScore,
  });

  factory CandidateRankingProfile({
    required double difficultyAffinity,
    required double preferenceAffinity,
    required double measurabilityScore,
  }) => CandidateRankingProfile._(
    difficultyAffinity: _requireUnitInterval(
      difficultyAffinity,
      'difficultyAffinity',
    ),
    preferenceAffinity: _requireUnitInterval(
      preferenceAffinity,
      'preferenceAffinity',
    ),
    measurabilityScore: _requireUnitInterval(
      measurabilityScore,
      'measurabilityScore',
    ),
  );

  /// How well the candidate's authored difficulty aligns with the learner's
  /// current skill level — `0` = far off, `1` = on level (brief §3).
  final double difficultyAffinity;

  /// The learner's affinity for this candidate — `0` = avoided, `1` =
  /// preferred (brief §3).
  final double preferenceAffinity;

  /// How measurable the candidate's outcome is — `0` = opaque, `1` =
  /// fully scored across direction, chord, and pitch channels (brief §3).
  final double measurabilityScore;

  /// The neutral, zero-contribution profile used when the caller has no
  /// per-candidate signal to provide.
  static final CandidateRankingProfile neutral = CandidateRankingProfile(
    difficultyAffinity: 0,
    preferenceAffinity: 0,
    measurabilityScore: 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CandidateRankingProfile &&
          other.difficultyAffinity == difficultyAffinity &&
          other.preferenceAffinity == preferenceAffinity &&
          other.measurabilityScore == measurabilityScore;

  @override
  int get hashCode =>
      Object.hash(difficultyAffinity, preferenceAffinity, measurabilityScore);
}

/// A single signed contribution to a [SelectedCandidate.compositeScore].
final class CandidateFactor {
  CandidateFactor({
    required this.kind,
    required double normalizedValue,
    required double contribution,
  }) : normalizedValue = _requireUnitInterval(
         normalizedValue,
         'normalizedValue',
       ),
       contribution = _requireFinite(contribution, 'contribution');

  final CandidateFactorKind kind;
  final double normalizedValue;
  final double contribution;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CandidateFactor &&
          other.kind == kind &&
          other.normalizedValue == normalizedValue &&
          other.contribution == contribution;

  @override
  int get hashCode => Object.hash(kind, normalizedValue, contribution);
}

/// A candidate the selector actually emitted as `selected` or `fallback`.
final class SelectedCandidate {
  SelectedCandidate({
    required String identity,
    required this.candidate,
    required this.skillId,
    required this.relevanceScore,
    required this.compositeScore,
    required Iterable<CandidateFactor> factors,
  }) : identity = _requireText(identity, 'identity'),
       factors = List<CandidateFactor>.unmodifiable(factors) {
    if (factors.isEmpty) {
      throw ArgumentError.value(
        factors,
        'factors',
        'must include at least the relevance factor',
      );
    }
    final explainedScore = factors.fold<double>(
      0,
      (total, factor) => total + factor.contribution,
    );
    if ((explainedScore - compositeScore).abs() > 0.0000001) {
      throw ArgumentError.value(
        factors,
        'factors',
        'contributions must add up to compositeScore',
      );
    }
  }

  /// Stable `'source:exerciseId'` reference (ADR 0262 identity contract).
  final String identity;

  final ExerciseCandidate candidate;

  /// The skill the selector targeted for this slot (always equal to the
  /// input [SkillPriority.skillId] — A6).
  final String skillId;

  /// The unmodified relevance score inherited from the [SkillPriority].
  final double relevanceScore;

  /// The score after policy factors (recent-overuse penalty), used to pick
  /// the winner before diversity/exploration tie-break.
  final double compositeScore;

  final List<CandidateFactor> factors;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectedCandidate &&
          other.identity == identity &&
          other.candidate == candidate &&
          other.skillId == skillId &&
          other.relevanceScore == relevanceScore &&
          other.compositeScore == compositeScore &&
          _sameList(other.factors, factors);

  @override
  int get hashCode => Object.hash(
    identity,
    candidate,
    skillId,
    relevanceScore,
    compositeScore,
    Object.hashAll(factors),
  );
}

/// A candidate the selector hard-excluded before ranking (ADR 0297 §2).
///
/// `wouldBeScore` carries the score the candidate would have received if the
/// hard filter had not removed it — useful for diagnostics ("the best
/// candidate was hard-avoided"). It is `null` only when the selector could
/// not produce a score (e.g. identity missing from the catalog).
final class RejectedCandidate {
  RejectedCandidate({
    required String identity,
    required this.candidate,
    required this.reason,
    required String detail,
    this.wouldBeScore,
  }) : identity = _requireText(identity, 'identity'),
       detail = _requireText(detail, 'detail') {
    final score = wouldBeScore;
    if (score != null && !score.isFinite) {
      throw ArgumentError.value(
        score,
        'wouldBeScore',
        'must be finite when present',
      );
    }
  }

  final String identity;
  final ExerciseCandidate candidate;
  final CandidateRejectReason reason;
  final String detail;
  final double? wouldBeScore;

  /// Stable sort key: reason first (so all hard-avoid rejections group), then
  /// identity (lexical).
  String get sortKey => '${reason.code}:$identity';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RejectedCandidate &&
          other.identity == identity &&
          other.candidate == candidate &&
          other.reason == reason &&
          other.detail == detail &&
          other.wouldBeScore == wouldBeScore;

  @override
  int get hashCode =>
      Object.hash(identity, candidate, reason, detail, wouldBeScore);
}

/// The full immutable outcome of one `CandidateSelector.select` call.
///
/// `selected` and `fallback` are both `null` only when no candidate targeting
/// the requested skill passed the hard filter — that is a structurally valid
/// outcome the caller must surface, not a runtime error. `rejected` lists
/// every candidate the selector considered and excluded by reason
/// (ADR 0297 §5; brief A5). The decision is sorted, versioned, and carries
/// the seed provenance so two callers replaying the same input observe the
/// same decision bytes.
final class CandidateDecision {
  CandidateDecision({
    SelectedCandidate? initialSelected,
    SelectedCandidate? initialFallback,
    Iterable<RejectedCandidate> rejected = const <RejectedCandidate>[],
    required String policyVersion,
    required String seedProvenance,
    required String skillId,
  }) : selected = initialSelected,
       fallback = initialFallback,
       rejected = List<RejectedCandidate>.unmodifiable(_sortRejected(rejected)),
       policyVersion = _requireText(policyVersion, 'policyVersion'),
       seedProvenance = _requireText(seedProvenance, 'seedProvenance'),
       skillId = _requireText(skillId, 'skillId') {
    // Flow analysis does not promote nullable `final` fields that override
    // ==/hashCode; capture the parameter values in locals so the validation
    // below sees them as non-nullable once the null check has passed.
    final resolvedSelected = initialSelected;
    final resolvedFallback = initialFallback;
    if (resolvedSelected != null && resolvedFallback != null) {
      if (resolvedSelected.identity == resolvedFallback.identity) {
        throw ArgumentError.value(
          resolvedFallback.identity,
          'fallback.identity',
          'must differ from selected.identity',
        );
      }
    }
    if (resolvedSelected != null && resolvedSelected.skillId != skillId) {
      throw ArgumentError.value(
        resolvedSelected.skillId,
        'selected.skillId',
        'must equal decision.skillId',
      );
    }
    if (resolvedFallback != null && resolvedFallback.skillId != skillId) {
      throw ArgumentError.value(
        resolvedFallback.skillId,
        'fallback.skillId',
        'must equal decision.skillId',
      );
    }
  }

  final SelectedCandidate? selected;
  final SelectedCandidate? fallback;
  final List<RejectedCandidate> rejected;
  final String policyVersion;
  final String seedProvenance;
  final String skillId;

  /// True when no candidate targeting the requested skill passed the hard
  /// filter (both [selected] and [fallback] are `null`). The caller must
  /// surface this — the selector never invents a candidate (ADR 0297 §1).
  bool get hasNoEligible => selected == null && fallback == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CandidateDecision &&
          other.selected == selected &&
          other.fallback == fallback &&
          _sameList(other.rejected, rejected) &&
          other.policyVersion == policyVersion &&
          other.seedProvenance == seedProvenance &&
          other.skillId == skillId;

  @override
  int get hashCode => Object.hash(
    selected,
    fallback,
    Object.hashAll(rejected),
    policyVersion,
    seedProvenance,
    skillId,
  );
}

List<RejectedCandidate> _sortRejected(Iterable<RejectedCandidate> input) {
  final sorted = input.toList()
    ..sort((left, right) => left.sortKey.compareTo(right.sortKey));
  return sorted;
}

bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}

double _requireUnitInterval(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, name, 'must be finite and within [0, 1]');
  }
  return value;
}

double _requireFinite(double value, String name) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, name, 'must be finite');
  }
  return value;
}

T _decodeEnumCode<T extends Enum>({
  required String? code,
  required List<T> values,
  required String Function(T value) codeOf,
  required String typeName,
}) {
  if (code == null || code.trim().isEmpty) {
    throw ArgumentError.value(code, 'code', '$typeName code must not be empty');
  }
  for (final value in values) {
    if (codeOf(value) == code) return value;
  }
  throw ArgumentError.value(code, 'code', 'Unknown $typeName code: $code');
}
