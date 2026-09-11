// The shipped beginner course: well-formed, and teaching what the research and
// the measurements say it should.
//
// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md`
// §1.1 and §5. These cells exist so a later edit cannot quietly reorder the
// teaching, or set a target the engine cannot actually score, without a test and
// the sourced rationale disagreeing with it.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/chords/chord_shape.dart';
import 'package:strumsight/features/curriculum/public.dart';
import 'package:strumsight/features/live/engine/dsp/chord_dictionary.dart';
import 'package:strumsight/features/practice_generator/public.dart';

/// Index of the first mission that trains [skillId], or -1.
int _rungOf(Course course, String skillId) {
  final missions = course.missionsInOrder.toList();
  for (var i = 0; i < missions.length; i++) {
    if (missions[i].trainedSkillIds.contains(skillId)) return i;
  }
  return -1;
}

void main() {
  final course = beginnerCourse();

  test('the course is well formed', () {
    // No empty level, no duplicate id, no gate on a skill the course never
    // teaches, and no gate on a skill taught only later.
    expect(course.validate(), isEmpty);
  });

  test('every scored chord is one the recogniser can NAME', () {
    // The engine's vocabulary is maj, min, 7, maj7, m7, sus4, dim, aug — there
    // is no 6, so a two-finger G6 would be scored as `G`, a label the app cannot
    // distinguish. A mission must never target something the engine cannot name.
    final vocabulary = {
      for (final profile in ChordDictionary().profiles)
        if (!profile.isNoChord) profile.label,
    };
    for (final chord in beginnerScoredChords) {
      expect(
        vocabulary,
        contains(chord),
        reason: '$chord must be in the recogniser vocabulary to be scored',
      );
    }
    expect(vocabulary, isNot(contains('G6')));
  });

  test('every scored chord is a plain triad', () {
    // MEASURED: Cmaj7 sat below the presence gate for 24 of 32 frames on a clean
    // voicing, against 3 for plain C — the maj7 Occam handicap doing its job
    // while plain C takes the margin. A learner must never play something
    // correctly and be credited with nothing, so extensions are not targets in
    // the beginner course.
    for (final chord in beginnerScoredChords) {
      expect(
        RegExp(r'^[A-G][#b]?m?$').hasMatch(chord),
        isTrue,
        reason: '$chord is not a plain major or minor triad',
      );
    }
  });

  test('every scored chord has a diagram and can be auditioned', () {
    // The course must not ask for a chord the learner cannot be SHOWN.
    for (final chord in beginnerScoredChords) {
      expect(
        ChordShapes.has(chord),
        isTrue,
        reason: '$chord needs a shape for the diagram and tap-to-hear',
      );
    }
  });

  group('the teaching order, as researched', () {
    test('the right hand is isolated before any chord', () {
      // Uniformly recommended, and it removes the confound: with no chord to get
      // right, a direction error cannot be mistaken for a fingering error.
      expect(
        _rungOf(course, BeginnerSkills.rhythmDownQuarters),
        lessThan(_rungOf(course, BeginnerSkills.chordEMinor)),
      );
    });

    test('Em comes before Am, and both before D, G and C', () {
      final em = _rungOf(course, BeginnerSkills.chordEMinor);
      final am = _rungOf(course, BeginnerSkills.chordAMinor);
      expect(em, lessThan(am), reason: 'Em is the two-finger shape');
      for (final later in const [
        BeginnerSkills.chordDMajor,
        BeginnerSkills.chordGMajor,
        BeginnerSkills.chordCMajor,
      ]) {
        expect(am, lessThan(_rungOf(course, later)));
      }
    });

    test('C and G are last, and C is not before G', () {
      final missions = course.missionsInOrder.toList();
      final g = _rungOf(course, BeginnerSkills.chordGMajor);
      final c = _rungOf(course, BeginnerSkills.chordCMajor);
      expect(g, lessThan(c), reason: 'the sources group C with the hardest');
      expect(c, missions.length - 2, reason: 'C major is the last new shape');
    });

    test('a playable song arrives EARLY, not at the end', () {
      // Withholding real music until the whole chord set is learned is a
      // documented attrition risk. The song must come right after the first
      // change, and well before the last chord.
      final song = _rungOf(course, BeginnerSkills.twoChordSong);
      final firstChange = _rungOf(course, BeginnerSkills.changeEmToAm);
      final lastChord = _rungOf(course, BeginnerSkills.chordCMajor);
      expect(song, greaterThan(firstChange));
      expect(song, lessThan(lastChord));
      expect(
        song,
        lessThanOrEqualTo(course.missionsInOrder.length ~/ 2),
        reason: 'the song belongs in the first half of the ladder',
      );
    });

    test('the first chord change teaches not stopping the strumming hand', () {
      // Three independent teaching sources treat this as a rule applied from the
      // VERY FIRST change, not a later milestone — and it is the one thing a
      // chord-only recogniser cannot check and this app can, so the first change
      // mission must score direction, not only the chord.
      final missions = course.missionsInOrder;
      final firstChange = missions.firstWhere(
        (m) => m.trainedSkillIds.contains(BeginnerSkills.changeEmToAm),
      );
      expect(
        firstChange.successCriteria.requiredCapabilities,
        contains(ExerciseCapability.supportsDirectionScoring),
      );
      expect(firstChange.successCriteria.description, contains('WITHOUT'));
    });

    test('the strumming pattern is not gated behind the whole chord set', () {
      // Most sources introduce a pattern early, running it alongside a couple of
      // chords. Gating it behind D, G and C would be later than any source does.
      final pattern = _rungOf(course, BeginnerSkills.strumPattern);
      expect(pattern, lessThan(_rungOf(course, BeginnerSkills.chordDMajor)));
    });

    test('no barre chord and no F anywhere in the course', () {
      // The one point every source agreed on.
      final trained = {
        for (final mission in course.missionsInOrder)
          ...mission.trainedSkillIds,
      };
      expect(trained.where((s) => s.contains('fMajor')), isEmpty);
      expect(beginnerScoredChords, isNot(contains('F')));
      expect(beginnerScoredChords, isNot(contains('B')));
    });
  });

  group('honesty', () {
    test('the setup rung is open to everyone and claims nothing', () {
      final setup = course.missionsInOrder.first;
      expect(setup.unlock.isMeasured, isFalse);
      expect(setup.isOutcomeMeasured, isFalse);
      expect(setup.trainedSkillIds, isEmpty);
    });

    test('every other mission is measured and names what it measures', () {
      for (final mission in course.missionsInOrder.skip(1)) {
        expect(
          mission.isOutcomeMeasured,
          isTrue,
          reason: '${mission.missionId} should be measured',
        );
        expect(mission.trainedSkillIds, isNotEmpty);
        expect(mission.successCriteria.minimumAccuracy, isNotNull);
      }
    });

    test('every mission works offline', () {
      // Android-first, offline-first: the course must not need the network.
      for (final mission in course.missionsInOrder) {
        expect(
          mission.successCriteria.requiredCapabilities,
          contains(ExerciseCapability.supportsOffline),
          reason: mission.missionId,
        );
      }
    });

    test('skill ids reuse the vocabulary already shipped', () {
      // `legacy_mapping_table.dart` ships `chord.gMajor`, `chord.cMajor`,
      // `chord.dMajor` and `chord.gToC`. Inventing a parallel scheme would
      // disconnect the course from the evidence the planner already records.
      final trained = {
        for (final mission in course.missionsInOrder)
          ...mission.trainedSkillIds,
      };
      expect(
        trained,
        containsAll(const [
          'chord.gMajor',
          'chord.cMajor',
          'chord.dMajor',
          'chord.gToC',
        ]),
      );
    });
  });
}
