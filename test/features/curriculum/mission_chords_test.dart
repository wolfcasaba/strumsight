// Every chord the course asks for must be one the app can SHOW and RECOGNISE.
//
// This is the guard behind `mission_chords.dart`'s claim. The course doc already
// measured the failure mode it protects against: the two-finger `G6` is not in the
// decoder's vocabulary at all and reads as `G`, and `Cmaj7` does not reliably
// confirm — so asking a learner for either would mean they play it correctly and
// are told nothing happened. Checking it here rather than trusting the comment is
// the difference between a rule and a note.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/chords/public.dart';
import 'package:strumsight/features/curriculum/public.dart';
import 'package:strumsight/features/live/engine/dsp/chord_dictionary.dart';

void main() {
  final course = beginnerCourse();

  group('every label the course can ask for', () {
    test('has a shipped fingering, so the app can show it', () {
      for (final label in curriculumChordLabels) {
        expect(
          ChordShapes.forLabel(label),
          isNotNull,
          reason: '$label has no shipped fingering — nothing to put on screen',
        );
      }
    });

    test('is in the decoder vocabulary, so the app can hear it', () {
      final vocabulary = ChordDictionary().profiles
          .map((profile) => profile.label)
          .toSet();
      for (final label in curriculumChordLabels) {
        expect(
          vocabulary,
          contains(label),
          reason:
              '$label is not a label the decoder can emit, so a learner playing '
              'it correctly would be told nothing happened',
        );
      }
    });

    test('is a major or minor triad — nothing the decoder only half-hears', () {
      // The course's own measured decision: major and minor triads only. A
      // simplified voicing may be SHOWN as an unscored hint but never set as a
      // target, because `Cmaj7` sat below the presence gate for 24 of 32 frames
      // against 3 for plain C.
      for (final label in curriculumChordLabels) {
        final quality = label.replaceFirst(RegExp(r'^[A-G][#b]?'), '');
        expect(
          quality,
          anyOf('', 'm'),
          reason: '$label is neither a plain major nor a plain minor triad',
        );
      }
    });
  });

  group('every chord-scoring rung asks for something', () {
    test('a chord-scoring mission has a non-empty cycle', () {
      for (final mission in course.missionsInOrder) {
        final assignment = mission.rhythm;
        if (assignment == null || !assignment.mode.scoresChord) continue;
        expect(
          missionChordCycle(mission),
          isNotEmpty,
          reason:
              '${mission.missionId} scores a chord but names none, so the lane '
              'would ask for nothing while the attempt graded something',
        );
      }
    });

    test('a rung that scores NO chord asks for none', () {
      for (final mission in course.missionsInOrder) {
        final assignment = mission.rhythm;
        if (assignment != null && assignment.mode.scoresChord) continue;
        expect(
          missionChordCycle(mission),
          isEmpty,
          reason:
              '${mission.missionId} would show a shape the learner is not meant '
              'to fret',
        );
      }
    });

    test('a CHANGE rung alternates, a single-chord rung does not', () {
      final cycles = {
        for (final mission in course.missionsInOrder)
          mission.missionId: missionChordCycle(mission),
      };
      // The change rungs: two chords, and they must differ — a "change" between a
      // chord and itself would be credited without the learner changing anything.
      for (final id in const [
        'mission.emToAm',
        'mission.amToD',
        'mission.dToG',
        'mission.gToC',
      ]) {
        final cycle = cycles[id]!;
        expect(cycle, hasLength(2), reason: id);
        expect(cycle.first, isNot(cycle.last), reason: id);
      }
      // The shape rungs: one chord, held.
      for (final id in const [
        'mission.eMinor',
        'mission.aMinor',
        'mission.dMajor',
        'mission.gMajor',
        'mission.cMajor',
      ]) {
        expect(cycles[id], hasLength(1), reason: id);
      }
    });

    test('a change rung asks for the two chords its own name says', () {
      // The cycle has to be the change the SKILL is, or the rung would measure a
      // different change from the one it claims to teach.
      expect(
        missionChordCycle(
          course.missionsInOrder.firstWhere(
            (m) => m.missionId == 'mission.emToAm',
          ),
        ),
        ['Em', 'Am'],
      );
      expect(
        missionChordCycle(
          course.missionsInOrder.firstWhere(
            (m) => m.missionId == 'mission.gToC',
          ),
        ),
        ['G', 'C'],
      );
    });
  });
}
