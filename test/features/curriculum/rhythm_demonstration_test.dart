// The listen-and-repeat pre-roll: what is played, when, and what refuses to exist.
//
// The measurement behind the timeline is
// `test/features/live/demonstration_preroll_test.dart` (the pre-roll is heard as 15
// strokes, all of them dropped, and the attempt reads identically to a silent
// control). These cells pin the DECISIONS that measurement rests on, and the one
// refusal that keeps the mode honest.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/curriculum/data/beginner_course.dart';
import 'package:strumsight/features/curriculum/domain/rhythm_assignment.dart';
import 'package:strumsight/features/curriculum/domain/rhythm_demonstration.dart';
import 'package:strumsight/features/curriculum/domain/rhythm_grid.dart';
import 'package:strumsight/features/curriculum/domain/rhythm_mode.dart';

/// `D DU UDU` in eighths — the pattern the ear rung asks for.
RhythmGrid _patternGrid({bool muted = true}) => RhythmGrid.pendulum(
  subdivision: RhythmSubdivision.eighth,
  struck: const [true, false, true, true, false, true, true, true],
  muted: muted,
);

RhythmAssignment _earAssignment({double bpm = beginnerEighthBpm}) =>
    RhythmAssignment(
      mode: RhythmMode.listenAndRepeat,
      grid: _patternGrid(),
      bpm: bpm,
      bars: beginnerBarsPerAttempt,
    );

void main() {
  group('only a demonstrating mode gets a demonstration', () {
    test('the three reading modes get null, not an empty one', () {
      // Null and "an empty demonstration" are different TIMELINES: an empty one
      // would still carry the gap bar, which would push every other mode's bar 1
      // a bar later and silently shift every stored attempt's frame of reference.
      for (final mode in RhythmMode.values.where(
        (mode) => !mode.demonstratesFirst,
      )) {
        final assignment = RhythmAssignment(
          mode: mode,
          grid: _patternGrid(muted: !mode.scoresChord),
          bpm: beginnerEighthBpm,
          bars: 4,
        );
        expect(
          RhythmDemonstration.forAssignment(assignment),
          isNull,
          reason: mode.code,
        );
      }
    });

    test('listen-and-repeat gets one', () {
      expect(RhythmDemonstration.forAssignment(_earAssignment()), isNotNull);
    });
  });

  group('what is played', () {
    test('the pattern twice, so it can be heard as recurring', () {
      final demonstration = RhythmDemonstration.forAssignment(
        _earAssignment(),
      )!;
      expect(demonstration.bars, 2);
      expect(
        demonstration.strokes.length,
        _patternGrid().struckSlots.length * 2,
        reason:
            'one presentation of a one-bar pattern gives nothing to recognise as '
            'recurring, which is the first step every by-ear source describes',
      );
    });

    test('only beat 1 is accented, and nothing encodes direction', () {
      final demonstration = RhythmDemonstration.forAssignment(
        _earAssignment(),
      )!;
      final grid = _patternGrid();
      final barUs = demonstration.barUs;

      // Exactly two accents in two bars, and both on a bar boundary.
      final accented = demonstration.strokes.where((s) => s.accent).toList();
      expect(accented.length, 2);
      for (final stroke in accented) {
        expect(stroke.atUs % barUs, 0);
      }

      // And the accent does NOT track direction. This is the cell that would fail
      // if someone made up-strokes sound different to help the learner: a pitch
      // meaning "up" would teach a cue a guitar does not make, and the pendulum
      // rule — not the ear — is what supplies direction here.
      final upStrokeTimes = <int>{
        for (var bar = 0; bar < demonstration.bars; bar++)
          for (final slot in grid.struckSlots)
            if (slot.direction == StrumDirection.up)
              bar * barUs +
                  grid.onsetUs(
                    bar: 0,
                    slotIndex: slot.index,
                    bpm: beginnerEighthBpm,
                  ),
      };
      expect(
        upStrokeTimes,
        isNotEmpty,
        reason: 'this pattern must contain up-strokes or the cell is vacuous',
      );
      for (final stroke in demonstration.strokes) {
        if (upStrokeTimes.contains(stroke.atUs)) {
          expect(
            stroke.accent,
            isFalse,
            reason: 'an up-stroke sounded different from a down-stroke',
          );
        }
      }
    });

    test('the strokes sit exactly where the grid puts them, bar after bar', () {
      final demonstration = RhythmDemonstration.forAssignment(
        _earAssignment(),
      )!;
      final grid = _patternGrid();
      final expected = <int>[
        for (var bar = 0; bar < demonstration.bars; bar++)
          for (final slot in grid.struckSlots)
            bar * demonstration.barUs +
                grid.onsetUs(
                  bar: 0,
                  slotIndex: slot.index,
                  bpm: beginnerEighthBpm,
                ),
      ];
      expect(demonstration.strokes.map((s) => s.atUs), expected);
    });
  });

  group('the silent bar', () {
    test('it is one bar, on the metre, and it is inside the pre-roll', () {
      final demonstration = RhythmDemonstration.forAssignment(
        _earAssignment(),
      )!;
      expect(demonstration.gapBars, 1);
      expect(
        demonstration.totalUs,
        demonstration.playingUs + demonstration.barUs,
      );
      // On the metre, not an arbitrary pause: the demonstration just established a
      // pulse, and an off-metre gap would break the thing it established.
      expect(demonstration.totalUs % demonstration.barUs, 0);
    });

    test('isGap answers only inside it', () {
      final demonstration = RhythmDemonstration.forAssignment(
        _earAssignment(),
      )!;
      expect(demonstration.isGap(0), isFalse);
      expect(demonstration.isGap(demonstration.playingUs - 1), isFalse);
      expect(demonstration.isGap(demonstration.playingUs), isTrue);
      expect(demonstration.isGap(demonstration.totalUs - 1), isTrue);
      expect(demonstration.isGap(demonstration.totalUs), isFalse);
    });

    test('the bar number counts the played bars only', () {
      final demonstration = RhythmDemonstration.forAssignment(
        _earAssignment(),
      )!;
      expect(demonstration.barNumberAt(-1), isNull);
      expect(demonstration.barNumberAt(0), 1);
      expect(demonstration.barNumberAt(demonstration.barUs), 2);
      expect(
        demonstration.barNumberAt(demonstration.playingUs),
        isNull,
        reason: 'the silent bar is not "bar 3 of 2"',
      );
    });

    test('the last demonstrated stroke clears bar 1 by more than the gap bar', () {
      // The load-bearing separation, stated in the domain's own units so a tempo or
      // pattern change cannot quietly erode it. The measurement in
      // demonstration_preroll_test drives the real engine over the same shape.
      final demonstration = RhythmDemonstration.forAssignment(
        _earAssignment(),
      )!;
      final lastStroke = demonstration.strokes.last.atUs;
      expect(
        demonstration.totalUs - lastStroke,
        greaterThan(demonstration.barUs * 0.5),
        reason:
            'the demonstration would run into the count-in, and with one click '
            'timbre a learner could not hear which was which',
      );
    });
  });

  group('the mode refuses what it could not teach', () {
    test('no arrow row plus authored directions is rejected', () {
      // The taught 3/4 waltz departs from the pendulum legitimately, and
      // `RhythmGrid.authored` exists for exactly that. But a mode that hides the
      // notation has no way to tell a learner about the departure: the
      // demonstration carries timing, the pendulum rule carries direction, and an
      // authored direction is carried by neither. Scoring it would fault a learner
      // for information the app never gave them.
      expect(
        () => RhythmAssignment(
          mode: RhythmMode.listenAndRepeat,
          grid: RhythmGrid.authored(
            subdivision: RhythmSubdivision.eighth,
            strokes: const [
              StrumDirection.down,
              null,
              StrumDirection.up,
              null,
              StrumDirection.up,
              null,
              StrumDirection.down,
              null,
            ],
            muted: true,
          ),
          bpm: beginnerEighthBpm,
          bars: 4,
        ),
        throwsArgumentError,
      );
    });

    test('a pendulum grid is accepted, and an arrow-row mode may author', () {
      // The refusal is about the COMBINATION, not about authored grids as such —
      // outlawing them would call a correctly taught folk waltz wrong.
      expect(_earAssignment, returnsNormally);
      expect(
        () => RhythmAssignment(
          mode: RhythmMode.mutedStrokes,
          grid: RhythmGrid.authored(
            subdivision: RhythmSubdivision.eighth,
            strokes: const [
              StrumDirection.down,
              null,
              StrumDirection.up,
              null,
              StrumDirection.up,
              null,
              StrumDirection.down,
              null,
            ],
            muted: true,
          ),
          bpm: beginnerEighthBpm,
          bars: 4,
        ),
        returnsNormally,
      );
    });
  });

  group('the shipped ear rung', () {
    test(
      'it is the same pattern as the notated rung, damped, with no arrows',
      () {
        final course = beginnerCourse();
        final notated = course.missionsInOrder.firstWhere(
          (mission) => mission.missionId == 'mission.dDuUdU',
        );
        final byEar = course.missionsInOrder.firstWhere(
          (mission) => mission.missionId == 'mission.byEar',
        );
        expect(byEar.rhythm!.mode, RhythmMode.listenAndRepeat);
        expect(byEar.rhythm!.mode.showsArrowRow, isFalse);
        expect(
          byEar.rhythm!.grid.struckSlots.map((slot) => slot.index),
          notated.rhythm!.grid.struckSlots.map((slot) => slot.index),
          reason:
              'the ear rung withdraws the crutch, it does not also change the '
              'pattern — one new thing to get wrong per rung',
        );
        expect(
          byEar.rhythm!.grid.slots.every((slot) => slot.muted),
          isTrue,
          reason:
              'damped so the chord is not a confound, and because a damped stroke '
              'is percussive like the click that demonstrates it',
        );
        expect(byEar.rhythm!.bpm, notated.rhythm!.bpm);
      },
    );

    test('it trains its own skill, measured as direction', () {
      final byEar = beginnerCourse().missionsInOrder.firstWhere(
        (mission) => mission.missionId == 'mission.byEar',
      );
      expect(byEar.trainedSkillIds, {BeginnerSkills.rhythmByEar});
      expect(
        BeginnerSkills.rhythmByEar.startsWith('rhythm.'),
        isTrue,
        reason:
            'the namespace is what routes this to the direction metric '
            '(skill_metrics.dart); a different prefix would make it unmeasured',
      );
    });
  });
}
