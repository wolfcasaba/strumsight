// The course spine and its well-formedness rules.
//
// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md`
// §1 (the spine) and §5 (what the tests must pin). A mission is deliberately
// NOT a hand-written exercise: it is a goal + a definition of done + an unlock
// rule, and the existing adaptive generator produces the actual exercise.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/curriculum/public.dart';
import 'package:strumsight/features/practice_generator/public.dart';

SuccessCriteria _accuracy({double minimum = 0.7}) => SuccessCriteria(
  kind: SuccessCriterionKind.accuracyThreshold,
  description: 'land the strokes on the grid',
  requiredCapabilities: const [
    ExerciseCapability.requiresMicrophone,
    ExerciseCapability.supportsDirectionScoring,
  ],
  minimumAccuracy: minimum,
);

SuccessCriteria _completion() => SuccessCriteria(
  kind: SuccessCriterionKind.completion,
  description: 'tune the guitar',
  requiredCapabilities: const [ExerciseCapability.supportsOffline],
);

CurriculumMission _measuredMission({
  String missionId = 'm.rhythm.downQuarters',
  Set<String> trains = const {'rhythm.downQuarters'},
  Set<String> requires = const {},
}) => CurriculumMission(
  missionId: missionId,
  goalType: PracticeGoalType.rhythm,
  trainedSkillIds: trains,
  unlock: requires.isEmpty
      ? UnlockRule.always
      : UnlockRule.skillConfidence(
          prerequisiteSkillIds: requires,
          minimumState: SkillEstimateState.emerging,
          minimumLevel: 0.6,
        ),
  successCriteria: _accuracy(),
  isOutcomeMeasured: true,
);

void main() {
  group('mission invariants', () {
    test('a mission cannot be gated on the very skill it teaches', () {
      // The self-lock hazard: such a rung could never open, because the only
      // way to earn the evidence is to pass the rung that needs it.
      expect(
        () => _measuredMission(
          trains: const {'rhythm.downQuarters'},
          requires: const {'rhythm.downQuarters'},
        ),
        throwsArgumentError,
      );
    });

    test('a measured mission must train at least one skill', () {
      // Otherwise it claims to measure progress without saying progress in
      // WHAT, and nothing downstream could credit it.
      expect(
        () => CurriculumMission(
          missionId: 'm.empty',
          goalType: PracticeGoalType.rhythm,
          trainedSkillIds: const {},
          unlock: UnlockRule.always,
          successCriteria: _accuracy(),
          isOutcomeMeasured: true,
        ),
        throwsArgumentError,
      );
    });

    test('an accuracy threshold must be declared measured, and carry one', () {
      // A threshold on accuracy IS a performance claim, so it cannot present
      // itself as unmeasured...
      expect(
        () => CurriculumMission(
          missionId: 'm.x',
          goalType: PracticeGoalType.rhythm,
          trainedSkillIds: const {'a'},
          unlock: UnlockRule.always,
          successCriteria: _accuracy(),
          isOutcomeMeasured: false,
        ),
        throwsArgumentError,
      );
      // ...and it cannot be a threshold with no threshold in it.
      expect(
        () => CurriculumMission(
          missionId: 'm.y',
          goalType: PracticeGoalType.rhythm,
          trainedSkillIds: const {'a'},
          unlock: UnlockRule.always,
          successCriteria: SuccessCriteria(
            kind: SuccessCriterionKind.accuracyThreshold,
            description: 'no number',
            requiredCapabilities: const [ExerciseCapability.requiresMicrophone],
          ),
          isOutcomeMeasured: true,
        ),
        throwsArgumentError,
      );
    });

    test('a completion rung must NOT claim to be measured', () {
      // Design §2 rule 7. "You did it" is not "you did it well", and an
      // unmeasured rung must never masquerade as earned skill.
      expect(
        () => CurriculumMission(
          missionId: 'm.tune',
          goalType: PracticeGoalType.technique,
          trainedSkillIds: const {},
          unlock: UnlockRule.always,
          successCriteria: _completion(),
          isOutcomeMeasured: true,
        ),
        throwsArgumentError,
      );
      // The honest form is accepted, and trains no skill.
      final tuning = CurriculumMission(
        missionId: 'm.tune',
        goalType: PracticeGoalType.technique,
        trainedSkillIds: const {},
        unlock: UnlockRule.always,
        successCriteria: _completion(),
        isOutcomeMeasured: false,
      );
      expect(tuning.isOutcomeMeasured, isFalse);
    });
  });

  group('course well-formedness', () {
    Course courseOf(List<CurriculumMission> missions) => Course(
      courseId: 'beginner',
      version: 1,
      stages: [
        CurriculumStage(
          stageId: 's1',
          levels: [
            for (final (i, m) in missions.indexed)
              CurriculumLevel(
                levelId: 'l${i + 1}',
                goalType: m.goalType,
                missions: [m],
              ),
          ],
        ),
      ],
    );

    test('a well-formed ladder validates with no issues', () {
      final course = courseOf([
        _measuredMission(missionId: 'm1', trains: const {'s.a'}),
        _measuredMission(
          missionId: 'm2',
          trains: const {'s.b'},
          requires: const {'s.a'},
        ),
      ]);
      expect(course.validate(), isEmpty);
    });

    test('a prerequisite no mission ever teaches is an issue', () {
      // Otherwise the rung is unreachable: nothing in the course can produce
      // the evidence its gate demands.
      final course = courseOf([
        _measuredMission(
          missionId: 'm1',
          trains: const {'s.a'},
          requires: const {'s.nobody.teaches.this'},
        ),
      ]);
      expect(course.validate(), contains(CourseIssue.unreachablePrerequisite));
    });

    test('a prerequisite taught only LATER is an issue', () {
      // Forward references make a ladder that cannot be climbed in order, even
      // though every skill is taught somewhere.
      final course = courseOf([
        _measuredMission(
          missionId: 'm1',
          trains: const {'s.a'},
          requires: const {'s.b'},
        ),
        _measuredMission(missionId: 'm2', trains: const {'s.b'}),
      ]);
      expect(course.validate(), contains(CourseIssue.forwardPrerequisite));
    });

    test('duplicate mission or level ids are an issue', () {
      final course = courseOf([
        _measuredMission(missionId: 'dup', trains: const {'s.a'}),
        _measuredMission(missionId: 'dup', trains: const {'s.b'}),
      ]);
      expect(course.validate(), contains(CourseIssue.duplicateId));
    });

    test('an empty course, stage or level is an issue', () {
      expect(
        Course(courseId: 'c', version: 1, stages: const []).validate(),
        contains(CourseIssue.empty),
      );
      expect(
        Course(
          courseId: 'c',
          version: 1,
          stages: [CurriculumStage(stageId: 's', levels: const [])],
        ).validate(),
        contains(CourseIssue.empty),
      );
      expect(
        Course(
          courseId: 'c',
          version: 1,
          stages: [
            CurriculumStage(
              stageId: 's',
              levels: [
                CurriculumLevel(
                  levelId: 'l',
                  goalType: PracticeGoalType.rhythm,
                  missions: const [],
                ),
              ],
            ),
          ],
        ).validate(),
        contains(CourseIssue.empty),
      );
    });

    test('the version is part of the course identity', () {
      // Design §1: the version exists so a later re-ordering cannot silently
      // invalidate progress already earned, which means it has to be visible.
      final one = courseOf([
        _measuredMission(trains: const {'s.a'}),
      ]);
      expect(one.version, 1);
      expect(
        () => Course(courseId: 'c', version: 0, stages: one.stages),
        throwsArgumentError,
      );
    });
  });

  group('ordered traversal', () {
    test('missions come back in ladder order, flattened', () {
      final course = Course(
        courseId: 'beginner',
        version: 1,
        stages: [
          CurriculumStage(
            stageId: 's1',
            levels: [
              CurriculumLevel(
                levelId: 'l1',
                goalType: PracticeGoalType.rhythm,
                missions: [
                  _measuredMission(missionId: 'a', trains: const {'s.a'}),
                  _measuredMission(missionId: 'b', trains: const {'s.b'}),
                ],
              ),
            ],
          ),
          CurriculumStage(
            stageId: 's2',
            levels: [
              CurriculumLevel(
                levelId: 'l2',
                goalType: PracticeGoalType.chordChanges,
                missions: [
                  _measuredMission(missionId: 'c', trains: const {'s.c'}),
                ],
              ),
            ],
          ),
        ],
      );
      expect(course.missionsInOrder.map((m) => m.missionId), ['a', 'b', 'c']);
    });
  });
}
