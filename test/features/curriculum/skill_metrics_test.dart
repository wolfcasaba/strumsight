// A rung must be able to PRODUCE the measurement its own skills are made of.
//
// This is the guard that stops the one bug the classification exists to prevent:
// one run produces both a direction measurement and a chord measurement, so the
// obvious wiring credits every trained skill from both — and a chord skill
// credited from a direction accuracy is a number in the right field measuring the
// wrong thing, which nothing downstream can detect.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/curriculum/public.dart';

void main() {
  final course = beginnerCourse();

  group('the shipped course is coherent about what it measures', () {
    test('every measured rung can produce the measurement its skills need', () {
      final broken = <String>[];
      for (final mission in course.missionsInOrder) {
        if (!mission.isOutcomeMeasured) continue;
        final unmeasurable = unmeasurableSkillsOf(mission);
        if (unmeasurable.isNotEmpty) {
          broken.add('${mission.missionId} cannot measure $unmeasurable');
        }
      }
      expect(
        broken,
        isEmpty,
        reason:
            'a rung that claims progress in something its own exercise does not '
            'produce either writes the wrong measurement or writes nothing while '
            'looking like it counted',
      );
    });

    test('an UNMEASURED rung is allowed to have no exercise', () {
      // `mission.tuneAndSit` measures nothing and says so; that is the honest
      // case, not a gap. It must not be swept up by the rule above.
      final setup = course.missionsInOrder.firstWhere(
        (mission) => mission.missionId == 'mission.tuneAndSit',
      );
      expect(setup.isOutcomeMeasured, isFalse);
      expect(setup.trainedSkillIds, isEmpty);
    });

    test('the song rung claims no measurement, because there is none', () {
      // This cell is the one the guard above produced. `mission.twoChordSong` used
      // to declare an accuracy threshold of 0.6 with no song-performance
      // measurement anywhere in the app — it promised a score and delivered
      // nothing. It is now a completion rung: no skill, no claim, no microphone.
      final song = course.missionsInOrder.firstWhere(
        (mission) => mission.missionId == 'mission.twoChordSong',
      );
      expect(song.rhythm, isNull);
      expect(song.isOutcomeMeasured, isFalse);
      expect(song.trainedSkillIds, isEmpty);
      expect(song.unlock.isMeasured, isTrue, reason: 'opening it still is');
    });
  });

  group('the classification', () {
    test('rhythm and pattern skills are direction measurements', () {
      expect(
        curriculumSkillMetric('rhythm.downQuarters'),
        CurriculumSkillMetric.strumDirection,
      );
      expect(
        curriculumSkillMetric('strumPattern.dDuUdU'),
        CurriculumSkillMetric.strumDirection,
      );
    });

    test('chord and change skills are chord measurements', () {
      expect(
        curriculumSkillMetric('chord.eMinor'),
        CurriculumSkillMetric.chordShape,
      );
      expect(
        curriculumSkillMetric('chord.emToAm'),
        CurriculumSkillMetric.chordShape,
      );
    });

    test('an unknown namespace earns nothing rather than borrowing', () {
      expect(
        curriculumSkillMetric('tone.cleanRinging'),
        CurriculumSkillMetric.notMeasuredHere,
        reason:
            'a new skill nobody has taught this file about must earn no evidence, '
            'not whichever measurement happens to be nearby',
      );
    });

    test('every skill the shipped course trains is classified', () {
      final unclassified = <String>[];
      for (final mission in course.missionsInOrder) {
        for (final skillId in mission.trainedSkillIds) {
          if (curriculumSkillMetric(skillId) ==
              CurriculumSkillMetric.notMeasuredHere) {
            unclassified.add(skillId);
          }
        }
      }
      expect(unclassified, isEmpty);
    });
  });

  group('what an assignment can produce', () {
    test('a damped grid produces direction only — a muted string has no chord '
        'to name', () {
      final muted = course.missionsInOrder.firstWhere(
        (mission) => mission.missionId == 'mission.downQuarters',
      );
      expect(assignmentMetrics(muted.rhythm!), {
        CurriculumSkillMetric.strumDirection,
      });
    });

    test('a chord-scoring grid produces both', () {
      final withChord = course.missionsInOrder.firstWhere(
        (mission) => mission.missionId == 'mission.eMinor',
      );
      expect(assignmentMetrics(withChord.rhythm!), {
        CurriculumSkillMetric.strumDirection,
        CurriculumSkillMetric.chordShape,
      });
    });
  });
}
