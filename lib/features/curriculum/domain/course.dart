/// The course spine: a versioned, ordered ladder of stages, levels and
/// missions.
///
/// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §1.
/// A mission is deliberately NOT a hand-written exercise. It is a goal, a
/// definition of done, and an unlock rule; the existing adaptive generator
/// produces the actual exercise from the learner's own evidence. So this file
/// is data and invariants, with no exercise content in it at all.
///
/// Pure Dart: no Flutter, no Riverpod, no clock (AGENTS.md §6).
library;

import '../../practice_generator/public.dart'
    show PracticeGoalType, SuccessCriteria, SuccessCriterionKind;
import 'unlock_rule.dart';

/// A way a course can be malformed.
enum CourseIssue {
  /// A course, stage or level with nothing in it.
  empty('empty'),

  /// Two stages, levels or missions share an id.
  duplicateId('duplicateId'),

  /// A mission's gate needs a skill no mission in the course ever trains, so
  /// the rung can never open.
  unreachablePrerequisite('unreachablePrerequisite'),

  /// A mission's gate needs a skill trained only LATER in the ladder, so the
  /// course cannot be climbed in its own order.
  forwardPrerequisite('forwardPrerequisite');

  const CourseIssue(this.code);

  final String code;

  @override
  String toString() => code;
}

/// One rung's smallest unit of work.
final class CurriculumMission {
  /// Throws when the mission could not mean what it says:
  ///
  /// - gated on a skill it trains itself (a rung that can never open, because
  ///   the only way to earn the evidence is to pass the rung that needs it);
  /// - declared measured while training no skill (progress in WHAT?);
  /// - an `accuracyThreshold` that is not declared measured, or that carries no
  ///   threshold;
  /// - a `completion` criterion declaring itself measured — "you did it" is not
  ///   "you did it well" (design §2 rule 7).
  ///
  /// [SuccessCriterionKind.assessmentOnly] and
  /// [SuccessCriterionKind.tempoSustained] are NOT constrained here. The repo
  /// establishes only that they are no exception to the measurability rule
  /// (ADR 0294 decision 2) and does not define their semantics further, so the
  /// mission declares [isOutcomeMeasured] for them rather than having a guess
  /// derived on its behalf.
  CurriculumMission({
    required String missionId,
    required this.goalType,
    required Set<String> trainedSkillIds,
    required this.unlock,
    required this.successCriteria,
    required this.isOutcomeMeasured,
  }) : missionId = _requireText(missionId, 'missionId'),
       trainedSkillIds = Set<String>.unmodifiable(trainedSkillIds) {
    final selfGated = unlock.prerequisiteSkillIds.intersection(
      this.trainedSkillIds,
    );
    if (selfGated.isNotEmpty) {
      throw ArgumentError.value(
        selfGated.toList(growable: false),
        'unlock',
        'a mission cannot be gated on a skill it trains itself',
      );
    }
    if (isOutcomeMeasured && this.trainedSkillIds.isEmpty) {
      throw ArgumentError.value(
        trainedSkillIds,
        'trainedSkillIds',
        'a measured mission must say which skill it measures progress in',
      );
    }
    switch (successCriteria.kind) {
      case SuccessCriterionKind.accuracyThreshold:
        if (!isOutcomeMeasured) {
          throw ArgumentError.value(
            isOutcomeMeasured,
            'isOutcomeMeasured',
            'an accuracy threshold is a performance claim and cannot present '
                'itself as unmeasured',
          );
        }
        if (successCriteria.minimumAccuracy == null) {
          throw ArgumentError.value(
            successCriteria,
            'successCriteria',
            'an accuracyThreshold criterion needs a minimumAccuracy',
          );
        }
      case SuccessCriterionKind.completion:
        if (isOutcomeMeasured) {
          throw ArgumentError.value(
            isOutcomeMeasured,
            'isOutcomeMeasured',
            'a completion criterion measures that it happened, not how well',
          );
        }
      case SuccessCriterionKind.assessmentOnly:
      case SuccessCriterionKind.tempoSustained:
        break;
    }
  }

  final String missionId;

  /// Which existing planner goal this mission pursues. The curriculum reuses
  /// [PracticeGoalType] rather than inventing a parallel vocabulary.
  final PracticeGoalType goalType;

  /// Skills this mission develops. Empty is legitimate for an unmeasured rung
  /// (tuning, posture) and forbidden for a measured one.
  final Set<String> trainedSkillIds;

  final UnlockRule unlock;

  final SuccessCriteria successCriteria;

  /// Whether finishing this mission says something MEASURED about the learner.
  ///
  /// Distinct from [UnlockRule.isMeasured], which is about whether OPENING the
  /// rung depends on measured evidence. A rung can be open to everyone and
  /// still be measured on the way out, and vice versa; surfaces must keep both
  /// apart from earned skill (design §2 rule 7).
  final bool isOutcomeMeasured;
}

/// One rung of the ladder.
final class CurriculumLevel {
  CurriculumLevel({
    required String levelId,
    required this.goalType,
    required List<CurriculumMission> missions,
  }) : levelId = _requireText(levelId, 'levelId'),
       missions = List<CurriculumMission>.unmodifiable(missions);

  final String levelId;
  final PracticeGoalType goalType;
  final List<CurriculumMission> missions;
}

/// A broad section of the ladder.
final class CurriculumStage {
  CurriculumStage({
    required String stageId,
    required List<CurriculumLevel> levels,
  }) : stageId = _requireText(stageId, 'stageId'),
       levels = List<CurriculumLevel>.unmodifiable(levels);

  final String stageId;
  final List<CurriculumLevel> levels;
}

/// A versioned course.
final class Course {
  /// [version] must be positive: it is part of the course's identity, so that a
  /// later re-ordering publishes a NEW version instead of silently
  /// invalidating progress already earned against the old one (design §1).
  Course({
    required String courseId,
    required this.version,
    required List<CurriculumStage> stages,
  }) : courseId = _requireText(courseId, 'courseId'),
       stages = List<CurriculumStage>.unmodifiable(stages) {
    if (version < 1) {
      throw ArgumentError.value(version, 'version', 'must be positive');
    }
  }

  final String courseId;
  final int version;
  final List<CurriculumStage> stages;

  /// Every mission in ladder order, stages then levels then missions.
  Iterable<CurriculumMission> get missionsInOrder => [
    for (final stage in stages)
      for (final level in stage.levels) ...level.missions,
  ];

  /// Everything wrong with this course, or empty when it is well formed.
  ///
  /// Returns a SET so one kind of problem is reported once however many times
  /// it occurs — the caller wants to know what is broken, and the ids are in
  /// the course itself.
  Set<CourseIssue> validate() {
    final issues = <CourseIssue>{};
    if (stages.isEmpty) issues.add(CourseIssue.empty);

    final seenIds = <String>{};
    void claim(String id) {
      if (!seenIds.add(id)) issues.add(CourseIssue.duplicateId);
    }

    claim(courseId);
    for (final stage in stages) {
      claim(stage.stageId);
      if (stage.levels.isEmpty) issues.add(CourseIssue.empty);
      for (final level in stage.levels) {
        claim(level.levelId);
        if (level.missions.isEmpty) issues.add(CourseIssue.empty);
        for (final mission in level.missions) {
          claim(mission.missionId);
        }
      }
    }

    // Reachability and ordering: walk the ladder once, accumulating the skills
    // taught so far. A gate may only need skills already trained ABOVE it.
    final taughtSoFar = <String>{};
    final taughtAnywhere = <String>{
      for (final mission in missionsInOrder) ...mission.trainedSkillIds,
    };
    for (final mission in missionsInOrder) {
      for (final needed in mission.unlock.prerequisiteSkillIds) {
        if (!taughtAnywhere.contains(needed)) {
          issues.add(CourseIssue.unreachablePrerequisite);
        } else if (!taughtSoFar.contains(needed)) {
          issues.add(CourseIssue.forwardPrerequisite);
        }
      }
      taughtSoFar.addAll(mission.trainedSkillIds);
    }
    return issues;
  }
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return trimmed;
}
