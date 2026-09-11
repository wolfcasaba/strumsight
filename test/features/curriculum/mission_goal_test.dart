// Turning a mission into the planner's own goal type.
//
// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §4.
// The curriculum never builds exercise content; it hands the existing generator
// a goal and lets it choose the exercise from the learner's evidence.
//
// The reproducibility cells are the point of this file. A
// `PracticeGenerationRequest` derives its `seed` and `contentHash` from a
// canonical snapshot that INCLUDES each goal's id and its skillIds LIST (ADR
// 0259), while deliberately excluding every timestamp. So a randomly generated
// goal id, or an unsorted skill set, would make the same mission produce a
// different seed on every attempt — quietly destroying the guarantee that the
// same content always plans the same way.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/curriculum/public.dart';
import 'package:strumsight/features/practice_generator/public.dart';

CurriculumMission _mission({
  String id = 'mission.emToAm',
  Set<String> trains = const {'chord.emToAm', 'chord.aMinor'},
}) => CurriculumMission(
  missionId: id,
  goalType: PracticeGoalType.chordChanges,
  trainedSkillIds: trains,
  unlock: UnlockRule.always,
  successCriteria: SuccessCriteria(
    kind: SuccessCriterionKind.accuracyThreshold,
    description: 'change without stopping the strum',
    requiredCapabilities: const [
      ExerciseCapability.requiresMicrophone,
      ExerciseCapability.supportsChordScoring,
    ],
    minimumAccuracy: 0.7,
  ),
  isOutcomeMeasured: true,
);

final _now = DateTime.utc(2026, 9, 11, 10);

void main() {
  test('the goal carries the mission through, in the planner\'s own types', () {
    final goal = missionGoal(_mission(), createdAt: _now);
    expect(goal.type, PracticeGoalType.chordChanges);
    expect(goal.priority, GoalPriority.primary);
    expect(goal.status, PracticeGoalStatus.active);
    expect(goal.skillIds, containsAll(['chord.aMinor', 'chord.emToAm']));
    expect(
      goal.normalizedTargetId,
      'mission.emToAm',
      reason: 'an outcome must be traceable back to the rung that asked for it',
    );
  });

  test('the goal id is DERIVED from the mission, never generated', () {
    // Two independent calls must produce the same id, or the request seed moves
    // under the planner's feet.
    final a = missionGoal(_mission(), createdAt: _now);
    final b = missionGoal(_mission(), createdAt: DateTime.utc(2027, 1, 1));
    expect(a.id, b.id);
    expect(a.id.value, contains('mission.emToAm'));
  });

  test('skill ids come out SORTED, so the content hash is stable', () {
    // A Set's iteration order follows insertion, and the snapshot hashes the
    // list. Two spellings of the same mission must not hash differently.
    final one = missionGoal(
      _mission(trains: const {'chord.emToAm', 'chord.aMinor'}),
      createdAt: _now,
    );
    final other = missionGoal(
      _mission(trains: const {'chord.aMinor', 'chord.emToAm'}),
      createdAt: _now,
    );
    expect(one.skillIds, other.skillIds);
    expect(one.skillIds, ['chord.aMinor', 'chord.emToAm']);
  });

  test('the same mission yields the same request seed and hash', () {
    // The property all of the above exists to protect, asserted end to end.
    PracticeGenerationRequest build(DateTime when) => PracticeGenerationRequest(
      id: GenerationRequestId('req.1'),
      createdAt: when,
      locale: 'en',
      generationMode: GenerationMode.starter,
      planHorizonDays: 7,
      availability: WeeklyAvailability(const []),
      constraints: LearnerConstraints(const []),
      goals: [missionGoal(_mission(), createdAt: when)],
    );
    final first = build(_now);
    final later = build(DateTime.utc(2027, 3, 4));
    expect(first.seed, later.seed);
    expect(first.contentHash, later.contentHash);
  });

  test('different missions do NOT collide', () {
    final a = missionGoal(_mission(id: 'mission.dMajor'), createdAt: _now);
    final b = missionGoal(_mission(id: 'mission.gMajor'), createdAt: _now);
    expect(a.id, isNot(b.id));
  });

  test('the goal carries no threshold of its own', () {
    // The threshold lives in the mission's `SuccessCriteria`, which the
    // generator already validates. Copying it into a `MetricTarget` as well
    // would give "how good is good enough" two homes that can drift apart.
    expect(missionGoal(_mission(), createdAt: _now).metricTarget, isNull);
  });

  test('an unmeasured rung still produces a usable goal', () {
    final tuning = CurriculumMission(
      missionId: 'mission.tuneAndSit',
      goalType: PracticeGoalType.technique,
      trainedSkillIds: const {},
      unlock: UnlockRule.always,
      successCriteria: SuccessCriteria(
        kind: SuccessCriterionKind.completion,
        description: 'tune up',
        requiredCapabilities: const [ExerciseCapability.supportsOffline],
      ),
      isOutcomeMeasured: false,
    );
    final goal = missionGoal(tuning, createdAt: _now);
    expect(goal.skillIds, isEmpty);
    expect(goal.type, PracticeGoalType.technique);
  });

  test('every mission in the shipped course produces a valid goal', () {
    // The ids in the course must satisfy the planner's id pattern — a dot is
    // allowed, a space or a slash is not — so this catches a malformed mission
    // id at the point the course is written rather than at runtime.
    final ids = <GoalId>{};
    for (final mission in beginnerCourse().missionsInOrder) {
      final goal = missionGoal(mission, createdAt: _now);
      expect(goal.skillIds.toSet().length, goal.skillIds.length);
      expect(
        ids.add(goal.id),
        isTrue,
        reason:
            'duplicate goal id for '
            '${mission.missionId}',
      );
    }
  });
}
