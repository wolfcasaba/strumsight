/// When a curriculum rung opens.
///
/// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §2.
/// Two of that section's rules live here rather than in the UI, because a rule
/// enforced only at the edge is a rule that can be bypassed:
///
///   - **rule 5** — unlocking requires CONFIDENCE, not luck. A hit count is not
///     a gate; the gate is the learner's [SkillEstimateState]. `emerging` or
///     better opens a rung, and `stale` / `conflicted` never do, because both
///     mean "the evidence is no longer trustworthy", not "the learner is good".
///   - **rule 7** — what is not measured says so. A rung with nothing to
///     measure (tuning, posture) is honest about that via [UnlockRule.isMeasured]
///     instead of quietly presenting itself as earned skill.
///
/// Pure Dart: no Flutter, no Riverpod, no clock (AGENTS.md §6).
library;

import '../../practice_generator/public.dart'
    show SkillEstimate, SkillEstimateState;

/// The kind of condition a rung opens on.
enum UnlockGate {
  /// Always open. For rungs the app cannot measure and does not pretend to.
  always('always'),

  /// Open once every prerequisite skill has trustworthy enough evidence.
  skillConfidence('skillConfidence');

  const UnlockGate(this.code);

  /// Stable persisted code. Never persist `.name` — a rename would silently
  /// invalidate stored progress.
  final String code;

  static UnlockGate fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'UnlockGate',
  );

  @override
  String toString() => code;
}

/// How much confidence a [SkillEstimateState] actually carries.
///
/// This exists because [SkillEstimateState] is declared
/// `unknown, initial, emerging, stable, strong, stale, conflicted`, so `stale`
/// and `conflicted` sit AFTER `strong` in index order. Comparing `.index` would
/// read degraded evidence as the strongest kind there is, which is precisely the
/// false claim rule 5 forbids. The ordering is therefore explicit, and the two
/// degraded states are deliberately OUTSIDE it — they are not a low rank, they
/// are "not usable as evidence", which is a different thing.
const Map<SkillEstimateState, int> _confidenceRank = <SkillEstimateState, int>{
  SkillEstimateState.initial: 1,
  SkillEstimateState.emerging: 2,
  SkillEstimateState.stable: 3,
  SkillEstimateState.strong: 4,
};

/// One rung's unlock condition.
final class UnlockRule {
  /// A rung that is always open, for content the app does not measure.
  ///
  /// There is nothing to vary, so there is one instance: [always].
  const UnlockRule._always()
    : gate = UnlockGate.always,
      prerequisiteSkillIds = const <String>{},
      minimumState = null,
      minimumLevel = null;

  /// A rung gated on the learner's measured confidence.
  ///
  /// Throws if the gate could never mean anything: an empty prerequisite set
  /// (which would look measured while gating on nothing), a [minimumState] that
  /// carries no usable confidence, or a [minimumLevel] outside `0..1`.
  UnlockRule.skillConfidence({
    required Set<String> prerequisiteSkillIds,
    required SkillEstimateState minimumState,
    required double minimumLevel,
  }) : gate = UnlockGate.skillConfidence,
       prerequisiteSkillIds = Set<String>.unmodifiable(prerequisiteSkillIds),
       minimumState = minimumState,
       minimumLevel = minimumLevel {
    if (prerequisiteSkillIds.isEmpty) {
      throw ArgumentError.value(
        prerequisiteSkillIds,
        'prerequisiteSkillIds',
        'a confidence gate with no prerequisite would be vacuous',
      );
    }
    if (!_confidenceRank.containsKey(minimumState)) {
      throw ArgumentError.value(
        minimumState,
        'minimumState',
        'not a usable minimum: unknown, stale and conflicted carry no '
            'trustworthy confidence',
      );
    }
    if (minimumLevel < 0 || minimumLevel > 1) {
      throw ArgumentError.value(
        minimumLevel,
        'minimumLevel',
        'must be within 0..1',
      );
    }
  }

  /// The only rung condition that needs no evidence.
  static const UnlockRule always = UnlockRule._always();

  final UnlockGate gate;

  /// Skills that must be good enough; empty for [UnlockGate.always].
  final Set<String> prerequisiteSkillIds;

  /// Least confidence each prerequisite must carry; null for
  /// [UnlockGate.always].
  final SkillEstimateState? minimumState;

  /// Least skill level each prerequisite must reach, inclusive; null for
  /// [UnlockGate.always].
  final double? minimumLevel;

  /// Whether passing this rung says anything MEASURED about the learner.
  ///
  /// False for [UnlockGate.always]. Surfaces must keep the two apart so an
  /// unmeasured rung cannot be shown as earned skill (design §2 rule 7).
  bool get isMeasured => gate != UnlockGate.always;

  /// Whether [estimates] (by skill id) open this rung.
  ///
  /// A prerequisite with no entry is treated as [SkillEstimateState.unknown] —
  /// absence of evidence never satisfies a gate. An estimate with a null
  /// [SkillEstimate.level] (the `unknown` case, which carries no level so that
  /// missing evidence cannot be mistaken for low performance) likewise never
  /// satisfies one.
  bool isSatisfiedBy(Map<String, SkillEstimate> estimates) {
    if (gate == UnlockGate.always) return true;
    final requiredRank = _confidenceRank[minimumState]!;
    for (final skillId in prerequisiteSkillIds) {
      final estimate = estimates[skillId];
      if (estimate == null) return false;
      final rank = _confidenceRank[estimate.state];
      if (rank == null || rank < requiredRank) return false;
      final level = estimate.level;
      if (level == null || level < minimumLevel!) return false;
    }
    return true;
  }
}

/// Decodes a stable persisted enum code, refusing anything unrecognised rather
/// than defaulting. Copied per file by repo convention — the helper is private
/// and there is no shared utility to import (see
/// `practice_generator/domain/model/plan_enums.dart`).
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
