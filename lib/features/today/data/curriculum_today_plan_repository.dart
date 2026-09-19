/// The course, answering "what should I do today?".
///
/// ## Why this exists
///
/// `TodayPlanRepository`'s own doc said production reads
/// `UnavailableTodayPlanRepository` "until a future round wires the real plan
/// source" — an honest placeholder, left waiting. Meanwhile the curriculum knew
/// exactly which rung the learner was on and nothing outside it could ask. So the
/// Today hub greeted a learner halfway up the ladder with "no plan yet", and its
/// primary button sent them to a generic hub rather than to their own next step.
///
/// The dependency runs THIS way round on purpose: the Today hub is an aggregator,
/// so it may know about the curriculum; the curriculum must not know about a hub
/// that displays it.
///
/// ## Which rung is "today's"
///
/// `curriculumNextStep` decides, and it is shared with the ladder's own marker so
/// the hub's promise and the ladder cannot name different rungs. Its doc carries the
/// definition and why the obvious alternatives were rejected.
///
/// ## Why device capability is deliberately NOT consulted
///
/// `curriculumDeviceCapabilities` answers "what can be measured while audio is
/// arriving", and on the Today hub no audio is arriving — the live engine runs on
/// the practice screen. Feeding it `microphoneListening: false` would mark every
/// scored rung unmeasurable and have the hub recommend "tune up" forever; feeding
/// it `true` would assert a capability with no evidence, which
/// `device_capabilities.dart` exists to refuse.
///
/// So the plan answers the question it can answer honestly — how far up the ladder
/// the learner's own evidence reaches — and whether THIS device can measure the
/// rung is decided where it is knowable: on the practice screen, and on the ladder,
/// both of which already say so in words.
///
/// ## What "done today" means, and what it does not
///
/// One task, not a list: the course names a next step, and claiming a multi-item
/// daily plan the course does not define would be inventing one.
/// [TodayPlanSnapshot.completedTaskCount] reaches 1 only when an attempt for THAT
/// rung was recorded on the same local day — which is what makes
/// [TodayPlanSnapshot.isDayCompleted] mean "you have already practised today's
/// step" rather than "you have finished the course".
///
/// No clock is read here (AGENTS.md §6): `asOf` is supplied.
library;

import '../../curriculum/public.dart'
    show Course, CurriculumMission, CurriculumProgress, curriculumNextStep;
import '../domain/today_plan_repository.dart';
import '../domain/today_plan_snapshot.dart';

final class CurriculumTodayPlanRepository implements TodayPlanRepository {
  CurriculumTodayPlanRepository({
    required this.course,
    required this.progress,
    required this.asOf,
  });

  final Course course;
  final CurriculumProgress progress;
  final DateTime asOf;

  @override
  TodayPlanSnapshot load() {
    final estimates = progress.estimatesFor(course, asOf: asOf);
    // The SHARED definition, so the hub's promise and the ladder's marker can never
    // name different rungs (`next_step.dart`).
    final recommended = curriculumNextStep(course, estimates: estimates);
    if (recommended == null) {
      // A course offering no step at all gets the honest answer the placeholder
      // gave, never an invented one.
      return const TodayPlanSnapshot(
        availability: TodayPlanAvailability.unavailable,
      );
    }

    return TodayPlanSnapshot(
      // Not `offlineCached`, which would be a claim about a sync that does not
      // exist here: the course is shipped data and the evidence is local, so the
      // plan is simply current. `offlineCached` is for a plan fetched from
      // somewhere; saying it of this one would invent a server.
      availability: TodayPlanAvailability.ready,
      recommendedMissionId: recommended.missionId,
      totalTaskCount: 1,
      completedTaskCount: _practisedToday(recommended) ? 1 : 0,
    );
  }

  /// Whether an attempt for [mission] was recorded on the same local day as
  /// [asOf].
  ///
  /// Local day, not UTC: "today" is the learner's day, and a UTC boundary would end
  /// someone's practice day mid-evening in the wrong timezone.
  ///
  /// False for a rung that trains nothing, because there is no evidence such a rung
  /// could ever produce — "not knowable" renders as an incomplete day rather than
  /// as a completed one, so the hub never congratulates someone for a step it
  /// cannot see.
  bool _practisedToday(CurriculumMission mission) {
    final today = asOf.toLocal();
    for (final skillId in mission.trainedSkillIds) {
      for (final record in progress.evidenceRepository.allForSkill(skillId)) {
        final at = record.measuredAt.toLocal();
        if (at.year == today.year &&
            at.month == today.month &&
            at.day == today.day) {
          return true;
        }
      }
    }
    return false;
  }
}
