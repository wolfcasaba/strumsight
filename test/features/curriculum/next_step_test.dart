// Which rung is next — the answer two surfaces share, so it has to be right once.
//
// The Today hub's primary button promises "continue this", and the ladder marks the
// rung it promised. Two implementations would drift and the learner would see the
// hub point at one rung and the ladder at another.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/curriculum/public.dart';
import 'package:strumsight/features/practice_generator/public.dart';

final DateTime _start = DateTime.utc(2026, 9, 12, 10);

CurriculumProgress _progress() => CurriculumProgress(
  evidenceRepository: InMemoryPracticeEvidenceRepository(),
);

CurriculumMission _mission(Course course, String id) =>
    course.missionsInOrder.firstWhere((m) => m.missionId == id);

/// One clean run of [mission]: every notated stroke the right way, and the asked
/// chord confirmed in every bar.
void _playClean(
  CurriculumProgress progress,
  CurriculumMission mission, {
  required int times,
  required int fromDay,
}) {
  final assignment = mission.rhythm!;
  final cycle = missionChordCycle(mission);
  final barUs = (60000000 / assignment.bpm * assignment.grid.beatsPerBar)
      .round();
  for (var i = 0; i < times; i++) {
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
      at: _start.add(Duration(days: fromDay + i)),
    );
  }
}

void main() {
  final course = beginnerCourse();

  String? nextOf(CurriculumProgress progress, {int onDay = 30}) =>
      curriculumNextStep(
        course,
        estimates: progress.estimatesFor(
          course,
          asOf: _start.add(Duration(days: onDay)),
        ),
      )?.missionId;

  group('a learner with no evidence', () {
    test('is sent to the first rung that actually asks for something', () {
      // NOT `mission.tuneAndSit`, which is rung 1 and always open: it trains no
      // skill, so nothing downstream waits on it and it can never be the thing
      // blocking progress. Recommending it would have the hub tell a learner to
      // tune up every single day.
      expect(nextOf(_progress(), onDay: 0), 'mission.downQuarters');
    });
  });

  group('it follows the teaching order, not the frontier', () {
    test('after the right-hand rung, the SHAPE comes before the eighths', () {
      final progress = _progress();
      _playClean(
        progress,
        _mission(course, 'mission.downQuarters'),
        times: 2,
        fromDay: 0,
      );
      // Both `mission.eMinor` (rung 3) and `mission.downUpEighths` (rung 6) are now
      // unlocked. The furthest-unlocked rule would pick rung 6; the course's
      // researched order puts the shape first, and so does this.
      expect(nextOf(progress, onDay: 2), 'mission.eMinor');
    });

    test('and it advances through the chord chain in order', () {
      final progress = _progress();
      _playClean(
        progress,
        _mission(course, 'mission.downQuarters'),
        times: 2,
        fromDay: 0,
      );
      _playClean(
        progress,
        _mission(course, 'mission.eMinor'),
        times: 2,
        fromDay: 2,
      );
      expect(nextOf(progress, onDay: 4), 'mission.aMinor');

      _playClean(
        progress,
        _mission(course, 'mission.aMinor'),
        times: 2,
        fromDay: 4,
      );
      expect(nextOf(progress, onDay: 6), 'mission.emToAm');
    });
  });

  group('one attempt does not move it on', () {
    test('the same rung is still next after a single clean attempt', () {
      // The measured gate needs two (`curriculum_progress_test.dart`), so a
      // definition based on "has been attempted" would advance too early and leave
      // the learner stuck behind a gate nothing was pointing them at.
      final progress = _progress();
      _playClean(
        progress,
        _mission(course, 'mission.downQuarters'),
        times: 1,
        fromDay: 0,
      );
      expect(nextOf(progress, onDay: 1), 'mission.downQuarters');
    });
  });

  group('at the top of the ladder', () {
    test(
      'the last unlocked rung is the answer, because nothing is beyond it',
      () {
        // Walk the whole course cleanly, then ask.
        final progress = _progress();
        var day = 0;
        for (final mission in course.missionsInOrder) {
          if (mission.rhythm == null) continue;
          _playClean(progress, mission, times: 2, fromDay: day);
          day += 2;
        }
        final next = nextOf(progress, onDay: day);
        expect(next, isNotNull);
        expect(
          next,
          course.missionsInOrder.last.missionId,
          reason:
              'with nothing locked there is nothing to aim at, so the frontier is '
              'the honest answer rather than a silent null',
        );
      },
    );
  });

  group('it never names a locked rung', () {
    test('whatever the evidence, the answer is always unlocked', () {
      final progress = _progress();
      for (var played = 0; played <= 3; played++) {
        if (played > 0) {
          _playClean(
            progress,
            _mission(course, 'mission.downQuarters'),
            times: 1,
            fromDay: played - 1,
          );
        }
        final estimates = progress.estimatesFor(
          course,
          asOf: _start.add(Duration(days: played)),
        );
        final next = curriculumNextStep(course, estimates: estimates);
        expect(next, isNotNull);
        expect(
          next!.unlock.isSatisfiedBy(estimates),
          isTrue,
          reason:
              'offering a rung the ladder has not opened would be the hub '
              'promising something the ladder refuses',
        );
      }
    });
  });
}
