// The rhythm exercise a mission drills, and the contradictions it refuses.
//
// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §3.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/curriculum/public.dart';
import 'package:strumsight/features/practice_generator/public.dart';

RhythmGrid _mutedQuarters() => RhythmGrid.pendulum(
  subdivision: RhythmSubdivision.quarter,
  struck: const [true, true, true, true],
  muted: true,
);

RhythmGrid _ringingEighths() => RhythmGrid.pendulum(
  subdivision: RhythmSubdivision.eighth,
  struck: const [true, false, true, true, false, true, true, true],
);

void main() {
  group('the assignment refuses contradictions', () {
    test('a chord cannot be scored on damped strings', () {
      // A muted string has no chord to name. Scoring one would credit a label
      // the engine cannot produce — the same reason G6 and Cmaj7 are not
      // scored targets in this course.
      expect(
        () => RhythmAssignment(
          mode: RhythmMode.withChord,
          grid: _mutedQuarters(),
          bpm: 70,
          bars: 4,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the muted-strokes mode needs an actually damped grid', () {
      expect(
        () => RhythmAssignment(
          mode: RhythmMode.mutedStrokes,
          grid: _ringingEighths(),
          bpm: 80,
          bars: 4,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a nonsense tempo or bar count is refused', () {
      for (final bpm in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          () => RhythmAssignment(
            mode: RhythmMode.silentGrid,
            grid: _ringingEighths(),
            bpm: bpm,
            bars: 4,
          ),
          throwsA(isA<ArgumentError>()),
          reason: 'bpm $bpm',
        );
      }
      expect(
        () => RhythmAssignment(
          mode: RhythmMode.silentGrid,
          grid: _ringingEighths(),
          bpm: 80,
          bars: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('what the assignment computes', () {
    test('notated strokes count the ghosts OUT, and the bars IN', () {
      final assignment = RhythmAssignment(
        mode: RhythmMode.withChord,
        grid: _ringingEighths(),
        bpm: 80,
        bars: 4,
      );
      expect(assignment.notatedStrokes, 24, reason: '6 struck slots × 4 bars');
    });

    test('onsets line up with the grid, and with the grader', () {
      final assignment = RhythmAssignment(
        mode: RhythmMode.mutedStrokes,
        grid: _mutedQuarters(),
        bpm: 120,
        bars: 2,
      );
      expect(assignment.onsetsUs(), [
        0,
        500000,
        1000000,
        1500000,
        2000000,
        2500000,
        3000000,
        3500000,
      ]);
      expect(assignment.onsetsUs(startUs: 1000).first, 1000);
    });

    test('an assignment graded against its own perfect run is perfect', () {
      // The seam between the assignment and the grader, end to end.
      final assignment = RhythmAssignment(
        mode: RhythmMode.withChord,
        grid: _ringingEighths(),
        bpm: 80,
        bars: 4,
      );
      final struck = assignment.grid.struckSlots;
      final attempt = gradeRhythm(
        assignment.grid,
        bpm: assignment.bpm,
        bars: assignment.bars,
        strokes: [
          for (var bar = 0; bar < assignment.bars; bar++)
            for (final slot in struck)
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
      );
      expect(attempt.notatedStrokes, assignment.notatedStrokes);
      expect(attempt.credited, assignment.notatedStrokes);
      expect(attempt.coverage, 1.0);
    });

    test('assignments compare by value', () {
      RhythmAssignment build() => RhythmAssignment(
        mode: RhythmMode.withChord,
        grid: _ringingEighths(),
        bpm: 80,
        bars: 4,
      );
      expect(build(), build());
      expect(build().hashCode, build().hashCode);
      expect(
        build(),
        isNot(
          RhythmAssignment(
            mode: RhythmMode.withChord,
            grid: _ringingEighths(),
            bpm: 90,
            bars: 4,
          ),
        ),
      );
    });
  });

  group('a mission and its rhythm must agree', () {
    CurriculumMission build({
      required RhythmAssignment rhythm,
      required Set<ExerciseCapability> capabilities,
    }) => CurriculumMission(
      missionId: 'mission.test',
      goalType: PracticeGoalType.rhythm,
      trainedSkillIds: const {'rhythm.test'},
      unlock: UnlockRule.always,
      successCriteria: SuccessCriteria(
        kind: SuccessCriterionKind.accuracyThreshold,
        description: 'play it',
        requiredCapabilities: capabilities,
        minimumAccuracy: 0.7,
      ),
      isOutcomeMeasured: true,
      rhythm: rhythm,
    );

    final muted = RhythmAssignment(
      mode: RhythmMode.mutedStrokes,
      grid: _mutedQuarters(),
      bpm: 70,
      bars: 4,
    );
    final withChord = RhythmAssignment(
      mode: RhythmMode.withChord,
      grid: _ringingEighths(),
      bpm: 80,
      bars: 4,
    );

    test('a rhythm rung must require direction scoring', () {
      // It measures which way the hand travelled. A rung that does not require
      // that capability would be scored on something else entirely.
      expect(
        () => build(
          rhythm: muted,
          capabilities: const {
            ExerciseCapability.requiresMicrophone,
            ExerciseCapability.supportsOffline,
          },
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a muted rung cannot claim a chord score', () {
      expect(
        () => build(
          rhythm: muted,
          capabilities: const {
            ExerciseCapability.requiresMicrophone,
            ExerciseCapability.supportsDirectionScoring,
            ExerciseCapability.supportsChordScoring,
            ExerciseCapability.supportsOffline,
          },
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a with-chord rung must claim one', () {
      expect(
        () => build(
          rhythm: withChord,
          capabilities: const {
            ExerciseCapability.requiresMicrophone,
            ExerciseCapability.supportsDirectionScoring,
            ExerciseCapability.supportsOffline,
          },
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the agreeing combinations are accepted', () {
      expect(
        build(
          rhythm: muted,
          capabilities: const {
            ExerciseCapability.requiresMicrophone,
            ExerciseCapability.supportsDirectionScoring,
            ExerciseCapability.supportsOffline,
          },
        ).rhythm,
        muted,
      );
      expect(
        build(
          rhythm: withChord,
          capabilities: const {
            ExerciseCapability.requiresMicrophone,
            ExerciseCapability.supportsDirectionScoring,
            ExerciseCapability.supportsChordScoring,
            ExerciseCapability.supportsOffline,
          },
        ).rhythm,
        withChord,
      );
    });

    test('a non-rhythm mission carries no assignment and is unaffected', () {
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
      expect(tuning.rhythm, isNull);
    });
  });

  group('the shipped course', () {
    final course = beginnerCourse();

    test('every rung the app can measure carries an exercise, and the ones it '
        'cannot do not', () {
      final withRhythm = [
        for (final mission in course.missionsInOrder)
          if (mission.rhythm != null) mission.missionId,
      ];
      // The three right-hand rungs plus every chord and change rung. An exercise
      // is what makes a rung PLAYABLE, and therefore measurable: without one the
      // rung sat on the ladder and could never be earned, which left every rung
      // gated behind it permanently out of reach.
      expect(withRhythm, [
        'mission.downQuarters',
        'mission.eMinor',
        'mission.aMinor',
        'mission.emToAm',
        'mission.downUpEighths',
        'mission.dDuUdU',
        'mission.dMajor',
        'mission.amToD',
        'mission.gMajor',
        'mission.dToG',
        'mission.cMajor',
        'mission.gToC',
      ]);

      // The two that deliberately carry none, each for its own stated reason.
      final withoutRhythm = [
        for (final mission in course.missionsInOrder)
          if (mission.rhythm == null) mission.missionId,
      ];
      expect(withoutRhythm, [
        // Measured by nothing and says so.
        'mission.tuneAndSit',
        // A song played through is not a grid exercise, and this app does not
        // measure it yet — so it stays unplayable here rather than being
        // scored as something else.
        'mission.twoChordSong',
      ]);
    });

    test('every shipped grid is a PENDULUM grid', () {
      // The beginner course requires the derived kind. The authored escape
      // hatch exists for the waltz, which is not in this stage.
      for (final mission in course.missionsInOrder) {
        final rhythm = mission.rhythm;
        if (rhythm == null) continue;
        expect(rhythm.grid.followsPendulum, isTrue, reason: mission.missionId);
      }
    });

    test('the tempos are the ones the app already teaches at', () {
      // `first-strums`/`first-win` run at 70 and `eighth-drive` at 80 in
      // `lesson.dart`. Two answers to the same question would be two teachings.
      final byId = {
        for (final mission in course.missionsInOrder)
          mission.missionId: mission.rhythm,
      };
      expect(byId['mission.downQuarters']!.bpm, 70);
      expect(byId['mission.downUpEighths']!.bpm, 80);
      expect(byId['mission.dDuUdU']!.bpm, 80);
      expect(beginnerQuarterBpm, 70);
      expect(beginnerEighthBpm, 80);
    });

    test('the right hand is isolated on DAMPED strings first, then rings', () {
      final byId = {
        for (final mission in course.missionsInOrder)
          mission.missionId: mission.rhythm,
      };
      expect(
        byId['mission.downQuarters']!.grid.slots.every((slot) => slot.muted),
        isTrue,
      );
      expect(
        byId['mission.downUpEighths']!.grid.slots.every((slot) => slot.muted),
        isTrue,
      );
      expect(
        byId['mission.dDuUdU']!.grid.slots.any((slot) => slot.muted),
        isFalse,
        reason: 'the pattern rung is played on a chord, so it must ring',
      );
    });

    test('quarters come before eighths, and the pattern has the ghosts', () {
      final byId = {
        for (final mission in course.missionsInOrder)
          mission.missionId: mission.rhythm,
      };
      expect(
        byId['mission.downQuarters']!.grid.subdivision,
        RhythmSubdivision.quarter,
      );
      expect(
        byId['mission.downUpEighths']!.grid.subdivision,
        RhythmSubdivision.eighth,
      );
      // D DU UDU: six struck of eight, the "&" of 1 and the beat 3 ghosted.
      final pattern = byId['mission.dDuUdU']!.grid;
      expect(pattern.struckSlots.length, 6);
      expect(pattern.slots[1].isStruck, isFalse);
      expect(pattern.slots[4].isStruck, isFalse);
    });

    test('only the pattern rung scores a chord', () {
      final byId = {
        for (final mission in course.missionsInOrder)
          mission.missionId: mission.rhythm,
      };
      expect(byId['mission.downQuarters']!.mode.scoresChord, isFalse);
      expect(byId['mission.downUpEighths']!.mode.scoresChord, isFalse);
      expect(byId['mission.dDuUdU']!.mode.scoresChord, isTrue);
    });

    test('four bars per attempt, so one stray stroke cannot decide it', () {
      for (final mission in course.missionsInOrder) {
        final rhythm = mission.rhythm;
        if (rhythm == null) continue;
        expect(rhythm.bars, beginnerBarsPerAttempt);
        expect(rhythm.bars, greaterThan(1));
      }
    });

    test('the course still validates with the exercises attached', () {
      expect(course.validate(), isEmpty);
    });
  });
}
