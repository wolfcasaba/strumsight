// Whether a mission can be offered, and if not, WHY.
//
// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md`
// §2 (the honesty rules) and §4 ("a mission whose required capability is
// unsupported must be surfaced as unavailable, never silently substituted").
//
// The priority between the two reasons is the point of this file. When the
// device cannot measure the mission AND the learner has not earned the
// prerequisite, the answer must name the CAPABILITY, not the learner — the same
// ordering `LivePipeline.debugDeriveChordDecision` already uses, where a signal
// problem outranks `noChord`/`lowConfidence` so a bad microphone is never
// blamed on the player's fingers.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/curriculum/public.dart';
import 'package:strumsight/features/practice_generator/public.dart';

ExerciseCapabilities _supporting(Set<ExerciseCapability> supported) => {
  for (final capability in ExerciseCapability.values)
    capability: supported.contains(capability)
        ? CapabilitySupport.supported
        : CapabilitySupport.unsupported,
};

const _needed = <ExerciseCapability>{
  ExerciseCapability.requiresMicrophone,
  ExerciseCapability.supportsDirectionScoring,
};

SkillEstimate _strong(String skillId) => SkillEstimate(
  skillId: skillId,
  level: 0.9,
  uncertainty: 0.1,
  state: SkillEstimateState.strong,
  trend: SkillTrend.improving,
  trendDelta: 0.1,
  lastObservedAt: DateTime.utc(2026, 9, 11),
  evidenceIds: const ['e1'],
  evidenceSummary: const EvidenceSummary(
    validPerformanceCount: 6,
    stalePerformanceCount: 0,
    discomfortOnlyCount: 0,
  ),
);

CurriculumMission _mission({Set<String> requires = const {}}) =>
    CurriculumMission(
      missionId: 'm.rhythm.downUpEighths',
      goalType: PracticeGoalType.rhythm,
      trainedSkillIds: const {'rhythm.downUpEighths'},
      unlock: requires.isEmpty
          ? UnlockRule.always
          : UnlockRule.skillConfidence(
              prerequisiteSkillIds: requires,
              minimumState: SkillEstimateState.emerging,
              minimumLevel: 0.6,
            ),
      successCriteria: SuccessCriteria(
        kind: SuccessCriterionKind.accuracyThreshold,
        description: 'land the strokes on the grid',
        requiredCapabilities: _needed,
        minimumAccuracy: 0.7,
      ),
      isOutcomeMeasured: true,
    );

/// A tuning rung: open to everyone, measured by nothing.
CurriculumMission _unmeasured() => CurriculumMission(
  missionId: 'm.tune',
  goalType: PracticeGoalType.technique,
  trainedSkillIds: const {},
  unlock: UnlockRule.always,
  successCriteria: SuccessCriteria(
    kind: SuccessCriterionKind.completion,
    description: 'tune the guitar',
    requiredCapabilities: const [ExerciseCapability.supportsOffline],
  ),
  isOutcomeMeasured: false,
);

void main() {
  test('an open, supported mission is available', () {
    expect(
      missionAvailability(
        _mission(),
        estimates: const {},
        deviceCapabilities: _supporting(_needed),
      ),
      MissionAvailability.available,
    );
  });

  test('a gated mission with no evidence is locked, not unavailable', () {
    // "Locked" is a statement about the ladder, not about the device, and it is
    // not a failure — design §2 rule 6: a mission cannot fail, only be not yet
    // reached.
    expect(
      missionAvailability(
        _mission(requires: const {'rhythm.downQuarters'}),
        estimates: const {},
        deviceCapabilities: _supporting(_needed),
      ),
      MissionAvailability.lockedPendingSkill,
    );
  });

  test('evidence opens the gate', () {
    expect(
      missionAvailability(
        _mission(requires: const {'rhythm.downQuarters'}),
        estimates: {'rhythm.downQuarters': _strong('rhythm.downQuarters')},
        deviceCapabilities: _supporting(_needed),
      ),
      MissionAvailability.available,
    );
  });

  test('a missing capability makes it unavailable, never substituted', () {
    expect(
      missionAvailability(
        _mission(),
        deviceCapabilities: _supporting(const {
          ExerciseCapability.requiresMicrophone,
        }),
        estimates: const {},
      ),
      MissionAvailability.unavailableCapability,
      reason: 'direction scoring is unsupported here',
    );
  });

  test('an unsupported capability OUTRANKS a missing prerequisite', () {
    // Both wrong at once: the answer must name the capability. Reporting
    // "locked" would tell the learner to go practise something that this device
    // cannot measure either — an answer that is true but useless, and it reads
    // as the learner's shortfall when it is the device's.
    expect(
      missionAvailability(
        _mission(requires: const {'rhythm.downQuarters'}),
        estimates: const {},
        deviceCapabilities: _supporting(const {}),
      ),
      MissionAvailability.unavailableCapability,
    );
  });

  test('an unmeasured rung is available without any evidence', () {
    // Design §2 rule 7: tuning and posture are open, and the availability
    // answer says nothing about skill because there is none to claim.
    expect(
      missionAvailability(
        _unmeasured(),
        estimates: const {},
        deviceCapabilities: _supporting(const {
          ExerciseCapability.supportsOffline,
        }),
      ),
      MissionAvailability.available,
    );
  });

  test('even an unmeasured rung needs its own capability', () {
    // It is offline-only, so an environment that cannot do offline cannot offer
    // it — honesty cuts both ways.
    expect(
      missionAvailability(
        _unmeasured(),
        estimates: const {},
        deviceCapabilities: _supporting(const {}),
      ),
      MissionAvailability.unavailableCapability,
    );
  });

  test('degraded evidence locks rather than opens', () {
    // The stale/conflicted guarantee again, through the availability seam this
    // time: a surface asking "can I offer this?" must get the same answer the
    // gate gives.
    for (final state in const [
      SkillEstimateState.stale,
      SkillEstimateState.conflicted,
    ]) {
      final degraded = SkillEstimate(
        skillId: 'rhythm.downQuarters',
        level: 1,
        uncertainty: 0.1,
        state: state,
        trend: SkillTrend.flat,
        trendDelta: 0,
        lastObservedAt: DateTime.utc(2026, 9, 11),
        evidenceIds: const ['e1'],
        evidenceSummary: const EvidenceSummary(
          validPerformanceCount: 0,
          stalePerformanceCount: 9,
          discomfortOnlyCount: 0,
        ),
      );
      expect(
        missionAvailability(
          _mission(requires: const {'rhythm.downQuarters'}),
          estimates: {'rhythm.downQuarters': degraded},
          deviceCapabilities: _supporting(_needed),
        ),
        MissionAvailability.lockedPendingSkill,
        reason: '$state must not open a rung',
      );
    }
  });

  test('availability values round-trip through stable codes', () {
    for (final value in MissionAvailability.values) {
      expect(MissionAvailability.fromCode(value.code), value);
    }
    expect(() => MissionAvailability.fromCode('nope'), throwsArgumentError);
  });
}
