/// Whether a mission can be offered, and if not, WHY.
///
/// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md`
/// §2 and §4. Two things can stop a mission being offered, and which one the
/// learner is told about matters:
///
///   - the DEVICE cannot measure it (no microphone, no direction scoring);
///   - the LADDER has not opened it yet (the prerequisite evidence is missing).
///
/// Pure Dart: no Flutter, no Riverpod, no clock (AGENTS.md §6).
library;

import '../../practice_generator/public.dart'
    show
        CapabilitySupport,
        ExerciseCapabilities,
        ExerciseCapability,
        SkillEstimate;
import 'course.dart';

/// Whether a mission can be offered right now.
enum MissionAvailability {
  /// Offer it.
  available('available'),

  /// The ladder has not opened it yet. NOT a failure — a mission cannot fail,
  /// it can only be not yet reached (design §2 rule 6).
  lockedPendingSkill('lockedPendingSkill'),

  /// This environment cannot measure what the mission is defined by, so
  /// offering it would mean either scoring nothing or scoring something else.
  /// Surfaced as unavailable, never silently substituted (design §4).
  unavailableCapability('unavailableCapability');

  const MissionAvailability(this.code);

  /// Stable persisted code. Never persist `.name`.
  final String code;

  static MissionAvailability fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'MissionAvailability',
  );

  @override
  String toString() => code;
}

/// Whether [mission] can be offered, given what this environment can measure
/// and what the learner has earned.
///
/// A missing capability OUTRANKS a missing prerequisite, deliberately. When both
/// are true, "locked" would send the learner off to practise something this
/// device cannot measure either — an answer that is technically true and
/// practically useless, and one that reads as the learner's shortfall when it is
/// the environment's. This mirrors the ordering
/// `LivePipeline.debugDeriveChordDecision` already uses, where a signal-quality
/// problem outranks `noChord` / `lowConfidence` so that a bad microphone is
/// never blamed on the player's fingers.
MissionAvailability missionAvailability(
  CurriculumMission mission, {
  required Map<String, SkillEstimate> estimates,
  required ExerciseCapabilities deviceCapabilities,
}) {
  if (!mission.successCriteria.isMeasurableFor(deviceCapabilities)) {
    return MissionAvailability.unavailableCapability;
  }
  if (!mission.unlock.isSatisfiedBy(estimates)) {
    return MissionAvailability.lockedPendingSkill;
  }
  return MissionAvailability.available;
}

/// The capabilities [mission] needs that [deviceCapabilities] does not support.
///
/// Separate from [missionAvailability] so a surface can say WHICH capability is
/// missing — "a microphone is needed for this" is actionable, "unavailable" is
/// not. Empty when nothing is missing.
Set<ExerciseCapability> missingCapabilitiesFor(
  CurriculumMission mission,
  ExerciseCapabilities deviceCapabilities,
) => {
  for (final capability in mission.successCriteria.requiredCapabilities)
    if (deviceCapabilities[capability] != CapabilitySupport.supported)
      capability,
};

/// Decodes a stable persisted enum code, refusing anything unrecognised rather
/// than defaulting. Copied per file by repo convention.
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
