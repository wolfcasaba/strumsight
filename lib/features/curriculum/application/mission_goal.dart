/// Turning a curriculum mission into the planner's own goal type.
///
/// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §4.
/// The curriculum never builds exercise content. It hands the existing
/// `practice_generator` a goal; that engine reads the catalogue, aggregates the
/// learner's evidence, applies its progression rules and chooses the actual
/// exercise. This file is the whole seam between the two.
///
/// Pure Dart: no Flutter, no Riverpod, and no clock of its own — the caller
/// passes `createdAt` (AGENTS.md §6/§10).
library;

import '../../practice_generator/public.dart'
    show GoalId, GoalPriority, PracticeGoal, PracticeGoalStatus;
import '../domain/course.dart';

/// The planner goal for [mission].
///
/// Two details here protect the generator's reproducibility guarantee
/// (ADR 0259): a `PracticeGenerationRequest` derives its `seed` and
/// `contentHash` from a canonical snapshot that INCLUDES each goal's id and its
/// `skillIds` LIST, while deliberately excluding every timestamp.
///
///   - **The id is DERIVED from the mission id**, never generated. A fresh
///     random id would change the seed on every attempt, so the same rung would
///     plan differently each time it was opened — quietly destroying the
///     guarantee that identical content plans identically.
///   - **The skill ids are SORTED.** They arrive as a `Set`, whose iteration
///     order follows insertion, and the snapshot hashes them as a list. Without
///     sorting, two spellings of the same mission would hash differently.
///
/// No `MetricTarget` is attached, on purpose. The threshold already lives in the
/// mission's `SuccessCriteria`, which the generator validates and which travels
/// with the mission; copying it into the goal as well would give "how good is
/// good enough" two homes that can drift apart.
PracticeGoal missionGoal(
  CurriculumMission mission, {
  required DateTime createdAt,
}) => PracticeGoal(
  id: GoalId('goal.${mission.missionId}'),
  type: mission.goalType,
  // The rung the learner is on is what they are working on now.
  priority: GoalPriority.primary,
  status: PracticeGoalStatus.active,
  createdAt: createdAt,
  skillIds: mission.trainedSkillIds.toList()..sort(),
  // Provenance: an outcome must be traceable back to the rung that asked for it.
  normalizedTargetId: mission.missionId,
);
