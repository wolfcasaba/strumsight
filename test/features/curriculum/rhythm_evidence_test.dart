// Turning a graded attempt into evidence, under the honesty rules.
//
// Each cell here is a place where the easy choice would have written down a
// claim the measurement does not support: a score for a quiet room, a chord
// verdict derived from a direction measurement, or one skill's record silently
// overwriting another's.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/curriculum/public.dart';
import 'package:strumsight/features/practice_generator/public.dart';

RhythmGrid _downQuarters() => RhythmGrid.pendulum(
  subdivision: RhythmSubdivision.quarter,
  struck: List<bool>.filled(4, true),
);

/// [count] of the grid's notated slots played cleanly, the rest silent.
List<DetectedStroke> _played(
  RhythmGrid grid, {
  required int count,
  double bpm = 120,
  bool flipDirection = false,
  bool confirmed = true,
}) {
  final struck = grid.slots.where((slot) => slot.isStruck).toList();
  return [
    for (var i = 0; i < count && i < struck.length; i++)
      DetectedStroke(
        atUs: grid.onsetUs(bar: 0, slotIndex: struck[i].index, bpm: bpm),
        direction: flipDirection
            ? (struck[i].direction == StrumDirection.down
                  ? StrumDirection.up
                  : StrumDirection.down)
            : struck[i].direction,
        isConfirmed: confirmed,
      ),
  ];
}

RhythmAttempt _attempt({
  required int played,
  bool flipDirection = false,
  bool confirmed = true,
}) {
  final grid = _downQuarters();
  return gradeRhythm(
    grid,
    bpm: 120,
    bars: 1,
    strokes: _played(
      grid,
      count: played,
      flipDirection: flipDirection,
      confirmed: confirmed,
    ),
  );
}

/// The shipped rung the whole chain actually runs on.
CurriculumMission _rhythmMission() => beginnerCourse().missionsInOrder
    .firstWhere((m) => m.missionId == 'mission.downQuarters');

/// A shipped rung that measures a chord and carries no rhythm assignment.
CurriculumMission _chordMission() => beginnerCourse().missionsInOrder
    .firstWhere((m) => m.missionId == 'mission.eMinor');

final DateTime _at = DateTime.utc(2026, 9, 12, 10);

List<SkillEvidence> _evidence(
  CurriculumMission mission,
  RhythmAttempt attempt,
) => rhythmAttemptEvidence(
  mission: mission,
  attempt: attempt,
  measuredAt: _at,
  capturedAt: _at,
);

void main() {
  group('what a clean attempt writes down', () {
    test(
      'one record per trained skill, carrying the direction measurement',
      () {
        final mission = _rhythmMission();
        final records = _evidence(mission, _attempt(played: 4));

        expect(records, hasLength(mission.trainedSkillIds.length));
        final record = records.single;
        expect(record.skillId, 'rhythm.downQuarters');
        expect(record.performance!.value, 1.0);
        expect(record.performance!.sampleCount, 4);
        expect(record.confidence, 1.0);
        expect(record.source, EvidenceSource.curriculum);
        expect(record.measuredAt, _at);
      },
    );

    test(
      'the metric says DIRECTION, so nothing can later read it as a chord or a '
      'timing score',
      () {
        expect(
          _evidence(
            _rhythmMission(),
            _attempt(played: 4),
          ).single.performance!.metricCode,
          rhythmDirectionAccuracyMetric,
        );
        // gradeRhythm grades which way the hand travelled and nothing else.
        expect(rhythmDirectionAccuracyMetric, 'rhythm.directionAccuracy');
      },
    );

    test('no self-expiry: the policy fades evidence by age rather than cutting '
        'it off on a date', () {
      final record = _evidence(_rhythmMission(), _attempt(played: 4)).single;
      expect(record.validUntil, isNull);
      expect(record.isValidAt(_at.add(const Duration(days: 3650))), isTrue);
    });
  });

  group('the four refusals — no evidence, which is NOT a low score', () {
    test('an attempt below the coverage floor writes nothing', () {
      // One of four strokes heard: coverage 0.25, under minimumRhythmCoverage.
      final attempt = _attempt(played: 1);
      expect(attempt.isReportable, isFalse);
      expect(
        _evidence(_rhythmMission(), attempt),
        isEmpty,
        reason:
            'I could not hear enough of that is not a score — writing a low one '
            'would make a quiet room look like bad playing',
      );
    });

    test('an attempt nothing was heard in writes nothing', () {
      final attempt = _attempt(played: 0);
      expect(attempt.directionAccuracy, isNull);
      expect(_evidence(_rhythmMission(), attempt), isEmpty);
    });

    test('unconfirmed strokes are not evidence', () {
      final attempt = _attempt(played: 4, confirmed: false);
      expect(attempt.heard, 0);
      expect(_evidence(_rhythmMission(), attempt), isEmpty);
    });

    test('a mission with no rhythm assignment writes nothing, however good the '
        'attempt', () {
      final mission = _chordMission();
      expect(mission.rhythm, isNull);
      expect(
        _evidence(mission, _attempt(played: 4)),
        isEmpty,
        reason:
            'nothing here was graded by gradeRhythm, so crediting a chord skill '
            'with a direction measurement would be a claim with no evidence',
      );
    });
  });

  group('a wrong-direction attempt is evidence, and it is honest about it', () {
    test('every stroke heard, every one the other way: value 0.0 at full '
        'confidence', () {
      final attempt = _attempt(played: 4, flipDirection: true);
      expect(attempt.heard, 4);
      expect(attempt.directionAccuracy, 0.0);
      final record = _evidence(_rhythmMission(), attempt).single;
      // 0.0 is a MEASUREMENT — the strokes were confirmed and they travelled the
      // wrong way. That is the one thing only this app can tell a learner, and
      // suppressing it would throw the lesson away.
      expect(record.performance!.value, 0.0);
      expect(record.confidence, 1.0);
    });
  });

  group('coverage is recorded, never folded into the value', () {
    test('three of four heard, all correct: the value stays 1.0 and coverage '
        'goes to confidence', () {
      final attempt = _attempt(played: 3);
      expect(attempt.isReportable, isTrue);
      final record = _evidence(_rhythmMission(), attempt).single;
      expect(
        record.performance!.value,
        1.0,
        reason:
            'a missed slot subtracts nothing: silence is absence of evidence, '
            'not evidence of a wrong stroke',
      );
      expect(record.confidence, closeTo(0.75, 1e-9));
      expect(record.performance!.sampleCount, 3);
    });
  });

  group('the dedup key', () {
    test('two skills of one attempt get DIFFERENT ids, or one would overwrite '
        'the other in the store', () {
      final first = rhythmAttemptOutcomeId(
        missionId: 'mission.x',
        skillId: 'skill.a',
        measuredAt: _at,
      );
      final second = rhythmAttemptOutcomeId(
        missionId: 'mission.x',
        skillId: 'skill.b',
        measuredAt: _at,
      );
      expect(first, isNot(second));
    });

    test('the same attempt reported twice resolves to one id', () {
      expect(
        rhythmAttemptOutcomeId(
          missionId: 'mission.x',
          skillId: 'skill.a',
          measuredAt: _at,
        ),
        rhythmAttemptOutcomeId(
          missionId: 'mission.x',
          skillId: 'skill.a',
          measuredAt: _at.toLocal(),
        ),
      );
    });

    test('two attempts of the same mission do not', () {
      expect(
        rhythmAttemptOutcomeId(
          missionId: 'mission.x',
          skillId: 'skill.a',
          measuredAt: _at,
        ),
        isNot(
          rhythmAttemptOutcomeId(
            missionId: 'mission.x',
            skillId: 'skill.a',
            measuredAt: _at.add(const Duration(seconds: 1)),
          ),
        ),
      );
    });
  });
}
