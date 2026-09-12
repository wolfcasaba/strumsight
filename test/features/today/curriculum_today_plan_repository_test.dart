// The Today hub's plan, read from the shipped course.
//
// Until this source existed the hub told a learner halfway up the ladder that they
// had no plan, and its primary button sent them to a generic hub. These cells are
// about the two things that could go wrong in the other direction: naming a rung the
// ladder has not opened, and congratulating someone for work it cannot see.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/curriculum/public.dart';
import 'package:strumsight/features/practice_generator/public.dart';
import 'package:strumsight/features/today/data/curriculum_today_plan_repository.dart';
import 'package:strumsight/features/today/domain/today_plan_snapshot.dart';

final DateTime _noon = DateTime.utc(2026, 9, 12, 12);

CurriculumMission _mission(Course course, String id) =>
    course.missionsInOrder.firstWhere((m) => m.missionId == id);

/// A clean run of [mission] recorded at [at].
void _playClean(
  CurriculumProgress progress,
  CurriculumMission mission, {
  required DateTime at,
}) {
  final assignment = mission.rhythm!;
  final cycle = missionChordCycle(mission);
  final barUs = (60000000 / assignment.bpm * assignment.grid.beatsPerBar)
      .round();
  progress.recordAttempt(
    mission: mission,
    rhythm: gradeRhythm(
      assignment.grid,
      bpm: assignment.bpm,
      bars: assignment.bars,
      strokes: [
        for (var bar = 0; bar < assignment.bars; bar++)
          for (final slot in assignment.grid.slots)
            if (slot.isStruck)
              DetectedStroke(
                atUs: assignment.grid.onsetUs(
                  bar: bar,
                  slotIndex: slot.index,
                  bpm: assignment.bpm,
                ),
                direction: slot.direction,
                isConfirmed: true,
              ),
      ],
    ),
    chord: cycle.isEmpty
        ? null
        : gradeChords(
            cycle: cycle,
            bars: assignment.bars,
            bpm: assignment.bpm,
            beatsPerBar: assignment.grid.beatsPerBar,
            detections: [
              for (var bar = 0; bar < assignment.bars; bar++)
                DetectedChord(
                  atUs: bar * barUs + 1000,
                  label: cycle[bar % cycle.length],
                  isConfirmed: true,
                ),
            ],
          ),
    at: at,
  );
}

void main() {
  final course = beginnerCourse();

  ({CurriculumProgress progress, TodayPlanSnapshot Function(DateTime) load})
  subject() {
    final progress = CurriculumProgress(
      evidenceRepository: InMemoryPracticeEvidenceRepository(),
    );
    return (
      progress: progress,
      load: (asOf) => CurriculumTodayPlanRepository(
        course: course,
        progress: progress,
        asOf: asOf,
      ).load(),
    );
  }

  group('a learner with no evidence', () {
    test('gets a READY plan naming the first rung that asks for something', () {
      final snapshot = subject().load(_noon);
      expect(snapshot.availability, TodayPlanAvailability.ready);
      expect(snapshot.recommendedMissionId, 'mission.downQuarters');
      expect(snapshot.hasPlan, isTrue);
      expect(snapshot.totalTaskCount, 1);
      expect(snapshot.completedTaskCount, 0);
      expect(snapshot.isDayCompleted, isFalse);
    });

    test('the plan carries an ID, not a label — the surface localises it', () {
      // A label filled in here would be English prose in a projection with no
      // localisations, and the l10n parity gate would never notice because nothing
      // would be missing from the arb files.
      expect(subject().load(_noon).recommendedTaskLabel, isNull);
    });
  });

  group('the plan never claims a sync it does not have', () {
    test(
      'it is ready or unavailable, never offline-cached or sync-pending',
      () {
        // The course is shipped data and the evidence is local. Saying
        // "offline-cached" of it would invent a server it was cached FROM.
        final s = subject();
        for (final day in [0, 1, 5]) {
          final at = _noon.add(Duration(days: day));
          if (day > 0) {
            _playClean(
              s.progress,
              _mission(course, 'mission.downQuarters'),
              at: at,
            );
          }
          expect(s.load(at).availability, TodayPlanAvailability.ready);
        }
      },
    );
  });

  group('"practised today" is the learner\'s own day', () {
    test('an attempt recorded today counts the task done', () {
      final s = subject();
      _playClean(
        s.progress,
        _mission(course, 'mission.downQuarters'),
        at: _noon,
      );
      final snapshot = s.load(_noon);
      expect(snapshot.recommendedMissionId, 'mission.downQuarters');
      expect(snapshot.completedTaskCount, 1);
      expect(
        snapshot.isDayCompleted,
        isTrue,
        reason:
            'a day with the step already practised must read as done, so the hub '
            'shows a recap rather than nagging for work already finished',
      );
    });

    test('an attempt recorded YESTERDAY does not', () {
      final s = subject();
      _playClean(
        s.progress,
        _mission(course, 'mission.downQuarters'),
        at: _noon.subtract(const Duration(days: 1)),
      );
      final snapshot = s.load(_noon);
      expect(snapshot.completedTaskCount, 0);
      expect(snapshot.isDayCompleted, isFalse);
    });

    test('a rung that trains nothing reads as NOT done, because it cannot be '
        'seen', () {
      // The fall-through at the top of the ladder can land on a rung with no
      // trained skill. "Not knowable" must render as incomplete, never as
      // congratulations for a step the app cannot observe.
      final s = subject();
      var at = _noon;
      for (final mission in course.missionsInOrder) {
        if (mission.rhythm == null) continue;
        for (var i = 0; i < 2; i++) {
          _playClean(s.progress, mission, at: at);
          at = at.add(const Duration(days: 1));
        }
      }
      final snapshot = s.load(at);
      final recommended = _mission(course, snapshot.recommendedMissionId!);
      if (recommended.trainedSkillIds.isEmpty) {
        expect(snapshot.completedTaskCount, 0);
      }
    });
  });

  group('it agrees with the ladder, by construction', () {
    test('the recommended rung is the shared next-step answer', () {
      final s = subject();
      _playClean(
        s.progress,
        _mission(course, 'mission.downQuarters'),
        at: _noon,
      );
      _playClean(
        s.progress,
        _mission(course, 'mission.downQuarters'),
        at: _noon.add(const Duration(days: 1)),
      );
      final at = _noon.add(const Duration(days: 2));
      final snapshot = s.load(at);
      expect(
        snapshot.recommendedMissionId,
        curriculumNextStep(
          course,
          estimates: s.progress.estimatesFor(course, asOf: at),
        )?.missionId,
        reason:
            'the hub promising one rung while the ladder marks another would be '
            'two answers to the same question',
      );
      expect(snapshot.recommendedMissionId, 'mission.eMinor');
    });
  });
}
