// A chord measurement must never be mistaken for a direction one, and a rung that
// cannot produce a chord score must never write one.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/curriculum/public.dart';
import 'package:strumsight/features/practice_generator/public.dart';

final DateTime _at = DateTime.utc(2026, 9, 12, 10);

CurriculumMission _mission(String id) => beginnerCourse().missionsInOrder
    .firstWhere((mission) => mission.missionId == id);

ChordAttempt _attempt(
  CurriculumMission mission, {
  int heardBars = 4,
  bool wrongChord = false,
}) {
  final assignment = mission.rhythm!;
  final cycle = missionChordCycle(mission);
  final barUs = (60000000 / assignment.bpm * assignment.grid.beatsPerBar)
      .round();
  return gradeChords(
    cycle: cycle,
    bars: assignment.bars,
    bpm: assignment.bpm,
    beatsPerBar: assignment.grid.beatsPerBar,
    detections: [
      for (var bar = 0; bar < heardBars; bar++)
        DetectedChord(
          atUs: bar * barUs + 1000,
          // A chord the cycle never asks for, so every bar reads as wrong.
          label: wrongChord ? 'F' : cycle[bar % cycle.length],
          isConfirmed: true,
        ),
    ],
  );
}

List<SkillEvidence> _evidence(
  CurriculumMission mission,
  ChordAttempt attempt,
) => chordAttemptEvidence(
  mission: mission,
  attempt: attempt,
  measuredAt: _at,
  capturedAt: _at,
);

void main() {
  group('what a clean chord attempt writes down', () {
    test('one record per trained CHORD skill, with the chord metric', () {
      final mission = _mission('mission.eMinor');
      final records = _evidence(mission, _attempt(mission));
      final record = records.single;
      expect(record.skillId, 'chord.eMinor');
      expect(record.performance!.metricCode, chordShapeAccuracyMetric);
      expect(chordShapeAccuracyMetric, 'chord.shapeAccuracy');
      expect(record.performance!.value, 1.0);
      expect(record.performance!.sampleCount, 4);
      expect(record.confidence, 1.0);
      expect(record.source, EvidenceSource.curriculum);
    });

    test('the chord record and the direction record of the same run are two '
        'different records', () {
      // Shared ids would make whichever was written second erase the other, since
      // the store keeps exactly one record per outcome id.
      expect(
        chordAttemptOutcomeId(
          missionId: 'mission.eMinor',
          skillId: 'chord.eMinor',
          measuredAt: _at,
        ),
        isNot(
          rhythmAttemptOutcomeId(
            missionId: 'mission.eMinor',
            skillId: 'chord.eMinor',
            measuredAt: _at,
          ),
        ),
      );
    });
  });

  group('the refusals', () {
    test('a rung whose exercise scores no chord writes nothing', () {
      // A damped grid has no chord to name, so a chord score from one would be a
      // score of a label the engine cannot produce.
      final muted = _mission('mission.downQuarters');
      expect(muted.rhythm!.mode.scoresChord, isFalse);
      expect(
        _evidence(
          muted,
          gradeChords(
            cycle: const ['Em'],
            bars: 4,
            bpm: 70,
            beatsPerBar: 4,
            detections: [
              for (var bar = 0; bar < 4; bar++)
                DetectedChord(
                  atUs: bar * 3428571 + 1000,
                  label: 'Em',
                  isConfirmed: true,
                ),
            ],
          ),
        ),
        isEmpty,
      );
    });

    test('a rung with no exercise at all writes nothing', () {
      final song = _mission('mission.twoChordSong');
      expect(song.rhythm, isNull);
      expect(_evidence(song, const ChordAttempt(bars: [])), isEmpty);
    });

    test('below the coverage floor writes nothing', () {
      final mission = _mission('mission.eMinor');
      final attempt = _attempt(mission, heardBars: 1);
      expect(attempt.isReportable, isFalse);
      expect(_evidence(mission, attempt), isEmpty);
    });

    test('a DIRECTION-skill rung writes no chord evidence, even though its '
        'exercise does score a chord', () {
      // The pattern rung scores a chord (it is played over Em/Am), but the skill
      // it trains is the strumming pattern. Crediting that skill from a chord
      // accuracy would be the same class of error in the other direction.
      final pattern = _mission('mission.dDuUdU');
      expect(pattern.rhythm!.mode.scoresChord, isTrue);
      expect(_evidence(pattern, _attempt(pattern)), isEmpty);
    });
  });

  group('a wrong chord is evidence, and honest about it', () {
    test('every bar heard as another shape: value 0.0 at full confidence', () {
      final mission = _mission('mission.eMinor');
      final attempt = _attempt(mission, wrongChord: true);
      expect(attempt.heard, 4);
      expect(attempt.accuracy, 0.0);
      final record = _evidence(mission, attempt).single;
      expect(record.performance!.value, 0.0);
      expect(record.confidence, 1.0);
    });
  });

  group('coverage goes to confidence, not into the value', () {
    test('two of four bars heard, both right: value stays 1.0', () {
      final mission = _mission('mission.eMinor');
      final attempt = _attempt(mission, heardBars: 2);
      final record = _evidence(mission, attempt).single;
      expect(record.performance!.value, 1.0);
      expect(record.confidence, closeTo(0.5, 1e-9));
      expect(record.performance!.sampleCount, 2);
    });
  });
}
