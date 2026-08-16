/// Deterministic, domain-pure selection of one exercise candidate per
/// requested skill (ADR 0297, SDD Ch8 Kör 13).
///
/// The selector is the boundary that turns one [SkillPriority] into an
/// executable [SelectedCandidate] plus a same-skill fallback, while keeping
/// the hard filter uncrossable:
///
///  1. Candidates are filtered to those targeting the requested skill.
///  2. The hard filter removes everything that is hard-avoided, has no
///     caller-confirmed offline availability, asset, device capability, or
///     tuning/prerequisite confirmation — those candidates never reach
///     ranking (ADR 0297 §2; brief A1/A2).
///  3. Surviving candidates are scored by `SkillPriority.score` minus the
///     recent-overuse penalty, then sorted by `(compositeScore desc,
///     identity asc)`. Diversity and exploration act strictly as a
///     deterministic tie-break inside the configured
///     [CandidatePolicy.diversityWindow] (ADR 0297 §3; brief A3/A4/A8).
///  4. The selection and the fallback share the same skill target and
///     always survive the hard filter (brief A6).
///
/// The selector never reads a clock, never consults `Random`, and never
/// interprets a [LearnerConstraint] `value` field (ADR 0297 §1).
library;

import '../model/candidate_decision.dart';
import '../model/exercise_candidate.dart';
import '../model/practice_catalog_snapshot.dart';
import '../model/skill_priority.dart';
import '../policy/candidate_policy.dart';

/// The typed, identity-based execution truth a caller supplies for one
/// selection step.
///
/// Every identity is `source.code:exerciseId` and is matched against the
/// snapshot's `ExerciseCandidate` references. A value not present in its
/// set is treated as unconfirmed — there is no optimistic fallback
/// (ADR 0297 §1; brief A2).
final class CandidateRuntimeContext {
  CandidateRuntimeContext({
    Iterable<String> hardAvoidIdentities = const <String>[],
    Iterable<String> confirmedAssetIdentities = const <String>[],
    Iterable<String> confirmedDeviceCapabilityIdentities = const <String>[],
    Iterable<String> confirmedOfflineIdentities = const <String>[],
    Iterable<String> confirmedTuningIdentities = const <String>[],
    Iterable<String> recentlyUsedIdentities = const <String>[],
    Map<String, CandidateRankingProfile> rankingProfiles =
        const <String, CandidateRankingProfile>{},
  }) : hardAvoidIdentities = Set<String>.unmodifiable(hardAvoidIdentities),
       confirmedAssetIdentities = Set<String>.unmodifiable(
         confirmedAssetIdentities,
       ),
       confirmedDeviceCapabilityIdentities = Set<String>.unmodifiable(
         confirmedDeviceCapabilityIdentities,
       ),
       confirmedOfflineIdentities = Set<String>.unmodifiable(
         confirmedOfflineIdentities,
       ),
       confirmedTuningIdentities = Set<String>.unmodifiable(
         confirmedTuningIdentities,
       ),
       recentlyUsedIdentities = Set<String>.unmodifiable(
         recentlyUsedIdentities,
       ),
       _rankingProfiles = Map<String, CandidateRankingProfile>.unmodifiable(
         rankingProfiles,
       );

  /// Identities the caller has determined are hard-avoided for this learner
  /// (ADR 0258 hard constraint truth, resolved outside this boundary).
  final Set<String> hardAvoidIdentities;

  final Set<String> confirmedAssetIdentities;
  final Set<String> confirmedDeviceCapabilityIdentities;
  final Set<String> confirmedOfflineIdentities;
  final Set<String> confirmedTuningIdentities;

  /// Identities used in the most recent generation(s). Candidates whose
  /// identity is in this set receive the configured
  /// [CandidatePolicy.recentOverusePenalty] (brief A7). The selector never
  /// reads a clock — recency windows belong to the caller.
  final Set<String> recentlyUsedIdentities;

  final Map<String, CandidateRankingProfile> _rankingProfiles;

  /// Caller-supplied per-candidate ranking profile for one identity.
  /// Returns [CandidateRankingProfile.neutral] when the caller did not
  /// populate one (brief §3).
  CandidateRankingProfile rankingProfileFor(String identity) =>
      _rankingProfiles[identity] ?? CandidateRankingProfile.neutral;

  static String identityOf(ExerciseCandidate candidate) =>
      '${candidate.source.code}:${candidate.exerciseId}';
}

/// Produces a single [CandidateDecision] per requested [SkillPriority].
///
/// The selector is pure, deterministic, and reads no global state: the
/// snapshot, the runtime context, the policy, and the seed are all inputs.
final class CandidateSelector {
  const CandidateSelector({this.policy = CandidatePolicy.defaultPolicy});

  final CandidatePolicy policy;

  CandidateDecision select({
    required SkillPriority priority,
    required PracticeCatalogSnapshot catalog,
    required CandidateRuntimeContext context,
    required int seed,
  }) {
    final skillId = priority.skillId;
    final skillTargets = catalog.candidates
        .where((candidate) => candidate.skillTargets.contains(skillId))
        .toList(growable: false);

    final ranked = <_ScoredCandidate>[];
    final rejected = <RejectedCandidate>[];

    for (final candidate in skillTargets) {
      final identity = CandidateRuntimeContext.identityOf(candidate);
      final hardReason = _hardExcludeReason(
        identity: identity,
        candidate: candidate,
        context: context,
      );
      if (hardReason != null) {
        rejected.add(
          RejectedCandidate(
            identity: identity,
            candidate: candidate,
            reason: hardReason.reason,
            detail: hardReason.detail,
            wouldBeScore: priority.score,
          ),
        );
        continue;
      }
      final profile = context.rankingProfileFor(identity);
      final composite = _compositeScore(
        priority: priority,
        identity: identity,
        context: context,
        profile: profile,
      );
      ranked.add(_ScoredCandidate(candidate, identity, composite, profile));
    }

    ranked.sort(_compareScored);

    final topBucket = _topBucket(ranked);
    final selectedScored = _pickFromBucket(topBucket, seed);
    // Fallback comes from the canonical lexical-ranked list (not the
    // permuted diversity bucket), so the fallback identity is independent
    // of the seed (brief A8). The fallback always targets the same skill
    // (brief A6) because every candidate here passed the skill-target
    // filter.
    final fallbackScored = _pickFallback(ranked, selectedScored?.identity);

    SelectedCandidate? selected;
    if (selectedScored != null) {
      selected = _toSelected(
        scored: selectedScored,
        skillId: skillId,
        relevanceScore: priority.score,
        context: context,
      );
    }
    SelectedCandidate? fallback;
    if (fallbackScored != null) {
      fallback = _toSelected(
        scored: fallbackScored,
        skillId: skillId,
        relevanceScore: priority.score,
        context: context,
      );
    }

    return CandidateDecision(
      initialSelected: selected,
      initialFallback: fallback,
      rejected: rejected,
      policyVersion: policy.version,
      seedProvenance: seed.toString(),
      skillId: skillId,
    );
  }

  double _compositeScore({
    required SkillPriority priority,
    required String identity,
    required CandidateRuntimeContext context,
    required CandidateRankingProfile profile,
  }) {
    final overuse = context.recentlyUsedIdentities.contains(identity)
        ? policy.recentOverusePenalty
        : 0.0;
    return priority.score +
        policy.difficultyWeight * profile.difficultyAffinity +
        policy.preferenceWeight * profile.preferenceAffinity +
        policy.measurabilityWeight * profile.measurabilityScore -
        overuse;
  }

  List<_ScoredCandidate> _topBucket(List<_ScoredCandidate> ranked) {
    if (ranked.isEmpty) return const <_ScoredCandidate>[];
    final top = ranked.first.compositeScore;
    final window = policy.diversityWindow;
    final bucket = <_ScoredCandidate>[];
    for (final scored in ranked) {
      if ((top - scored.compositeScore).abs() <= window) {
        bucket.add(scored);
      } else {
        break;
      }
    }
    return bucket;
  }

  _ScoredCandidate? _pickFromBucket(List<_ScoredCandidate> bucket, int seed) {
    if (bucket.isEmpty) return null;
    if (bucket.length == 1) return bucket.single;
    // explorationWeight == 0 collapses to strict lexical order — the seed
    // never affects the winner. Positive values enable the deterministic
    // seed-based permutation, still bounded by the lexical tie-break and
    // the diversityWindow that defined this bucket (ADR 0297 §3).
    if (policy.explorationWeight == 0) return bucket.first;
    final indexed = List<_ScoredCandidate>.of(bucket);
    indexed.sort((left, right) {
      final leftKey = _seedKey(seed, left.identity);
      final rightKey = _seedKey(seed, right.identity);
      final keyCompare = leftKey.compareTo(rightKey);
      if (keyCompare != 0) return keyCompare;
      return left.identity.compareTo(right.identity);
    });
    return indexed.first;
  }

  _ScoredCandidate? _pickFallback(
    List<_ScoredCandidate> ranked,
    String? selectedIdentity,
  ) {
    for (final scored in ranked) {
      if (scored.identity == selectedIdentity) continue;
      return scored;
    }
    return null;
  }

  SelectedCandidate _toSelected({
    required _ScoredCandidate scored,
    required String skillId,
    required double relevanceScore,
    required CandidateRuntimeContext context,
  }) {
    final factors = <CandidateFactor>[
      CandidateFactor(
        kind: CandidateFactorKind.relevance,
        normalizedValue: 1,
        contribution: relevanceScore,
      ),
    ];
    if (policy.difficultyWeight > 0 && scored.profile.difficultyAffinity != 0) {
      final contribution =
          policy.difficultyWeight * scored.profile.difficultyAffinity;
      if (contribution != 0) {
        factors.add(
          CandidateFactor(
            kind: CandidateFactorKind.difficulty,
            normalizedValue: scored.profile.difficultyAffinity,
            contribution: contribution,
          ),
        );
      }
    }
    if (policy.preferenceWeight > 0 && scored.profile.preferenceAffinity != 0) {
      final contribution =
          policy.preferenceWeight * scored.profile.preferenceAffinity;
      if (contribution != 0) {
        factors.add(
          CandidateFactor(
            kind: CandidateFactorKind.preference,
            normalizedValue: scored.profile.preferenceAffinity,
            contribution: contribution,
          ),
        );
      }
    }
    if (policy.measurabilityWeight > 0 &&
        scored.profile.measurabilityScore != 0) {
      final contribution =
          policy.measurabilityWeight * scored.profile.measurabilityScore;
      if (contribution != 0) {
        factors.add(
          CandidateFactor(
            kind: CandidateFactorKind.measurability,
            normalizedValue: scored.profile.measurabilityScore,
            contribution: contribution,
          ),
        );
      }
    }
    if (context.recentlyUsedIdentities.contains(scored.identity)) {
      factors.add(
        CandidateFactor(
          kind: CandidateFactorKind.recentOveruse,
          normalizedValue: 1,
          contribution: -policy.recentOverusePenalty,
        ),
      );
    }
    return SelectedCandidate(
      identity: scored.identity,
      candidate: scored.candidate,
      skillId: skillId,
      relevanceScore: relevanceScore,
      compositeScore: scored.compositeScore,
      factors: factors,
    );
  }

  _HardReason? _hardExcludeReason({
    required String identity,
    required ExerciseCandidate candidate,
    required CandidateRuntimeContext context,
  }) {
    if (context.hardAvoidIdentities.contains(identity)) {
      return const _HardReason(
        CandidateRejectReason.hardAvoid,
        'identity is in hardAvoidIdentities',
      );
    }
    final needsAsset =
        candidate.capabilities[ExerciseCapability.requiresSongAsset] ==
            CapabilitySupport.supported ||
        candidate.capabilities[ExerciseCapability.requiresBackingTrack] ==
            CapabilitySupport.supported;
    if (needsAsset && !context.confirmedAssetIdentities.contains(identity)) {
      return const _HardReason(
        CandidateRejectReason.assetUnconfirmed,
        'candidate requires an asset the caller has not confirmed',
      );
    }
    final needsDeviceCapability =
        candidate.capabilities[ExerciseCapability.requiresMicrophone] ==
            CapabilitySupport.supported ||
        candidate.capabilities[ExerciseCapability.requiresCamera] ==
            CapabilitySupport.supported;
    if (needsDeviceCapability &&
        !context.confirmedDeviceCapabilityIdentities.contains(identity)) {
      return const _HardReason(
        CandidateRejectReason.deviceCapabilityUnconfirmed,
        'candidate requires a device capability the caller has not confirmed',
      );
    }
    if (!candidate.offlineAvailable &&
        !context.confirmedOfflineIdentities.contains(identity)) {
      return const _HardReason(
        CandidateRejectReason.offlineUnconfirmed,
        'candidate has no offline availability and the caller has not confirmed one',
      );
    }
    if (candidate.prerequisites.contains(_tuningPrerequisiteCode) &&
        !context.confirmedTuningIdentities.contains(identity)) {
      return const _HardReason(
        CandidateRejectReason.tuningUnconfirmed,
        'candidate requires the tuning prerequisite the caller has not confirmed',
      );
    }
    return null;
  }
}

/// Stable, catalog-declared prerequisite code that signals a candidate needs
/// the learner's instrument tuning confirmed. Mirrors the constant in
/// `plan_validator.dart` — the boundary is intentionally duplicated so each
/// service owns its own coupling.
const String _tuningPrerequisiteCode = 'guitar.tuned';

int _seedKey(int seed, String identity) {
  var hash = seed ^ 0x9E3779B9;
  for (final code in identity.codeUnits) {
    hash = (hash ^ (code & 0xFFFFFFFF)) * 16777619;
    hash &= 0xFFFFFFFF;
  }
  hash = (hash ^ (hash >> 13)) * 0x5BD1E995;
  hash &= 0xFFFFFFFF;
  hash ^= hash >> 15;
  return hash & 0xFFFFFFFF;
}

int _compareScored(_ScoredCandidate left, _ScoredCandidate right) {
  final score = right.compositeScore.compareTo(left.compositeScore);
  if (score != 0) return score;
  return left.identity.compareTo(right.identity);
}

class _ScoredCandidate {
  _ScoredCandidate(
    this.candidate,
    this.identity,
    this.compositeScore,
    this.profile,
  );

  final ExerciseCandidate candidate;
  final String identity;
  final double compositeScore;
  final CandidateRankingProfile profile;
}

class _HardReason {
  const _HardReason(this.reason, this.detail);

  final CandidateRejectReason reason;
  final String detail;
}
