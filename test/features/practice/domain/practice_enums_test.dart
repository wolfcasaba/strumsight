import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/practice_attempt_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';

void main() {
  group('PracticeMode stable codes', () {
    const expected = {
      PracticeMode.strumPattern: 'strumPattern',
      PracticeMode.chordChanges: 'chordChanges',
      PracticeMode.chordProgression: 'chordProgression',
      PracticeMode.rhythmOnly: 'rhythmOnly',
      PracticeMode.freePractice: 'freePractice',
    };

    test('pins every code, round-trips, and rejects unknown codes', () {
      expect(expected.keys, unorderedEquals(PracticeMode.values));
      expect(expected.values.toSet().length, expected.length);

      for (final entry in expected.entries) {
        expect(entry.key.code, entry.value);
        expect(practiceModeFromCode(entry.value), entry.key);
      }
      expect(practiceModeFromCode('unknown'), isNull);
    });

    test('exposes the exact scored dimensions for each mode', () {
      expect(PracticeMode.strumPattern.scoredDimensions, {
        PracticeScoreDimension.rhythm,
        PracticeScoreDimension.direction,
      });
      expect(PracticeMode.chordChanges.scoredDimensions, {
        PracticeScoreDimension.chord,
        PracticeScoreDimension.rhythm,
      });
      expect(PracticeMode.chordProgression.scoredDimensions, {
        PracticeScoreDimension.rhythm,
        PracticeScoreDimension.direction,
        PracticeScoreDimension.chord,
      });
      expect(PracticeMode.rhythmOnly.scoredDimensions, {
        PracticeScoreDimension.rhythm,
      });
      expect(PracticeMode.freePractice.scoredDimensions, isEmpty);
    });
  });

  group('PracticeSource stable codes', () {
    const expected = {
      PracticeSource.builtin: 'builtin',
      PracticeSource.lesson: 'lesson',
      PracticeSource.song: 'song',
      PracticeSource.analyze: 'analyze',
      PracticeSource.setlist: 'setlist',
      PracticeSource.dailyChallenge: 'dailyChallenge',
      PracticeSource.userCreated: 'userCreated',
      PracticeSource.futureAi: 'futureAi',
    };

    test('pins every code, round-trips, and rejects unknown codes', () {
      expect(expected.keys, unorderedEquals(PracticeSource.values));
      expect(expected.values.toSet().length, expected.length);

      for (final entry in expected.entries) {
        expect(entry.key.code, entry.value);
        expect(practiceSourceFromCode(entry.value), entry.key);
      }
      expect(practiceSourceFromCode('unknown'), isNull);
    });
  });

  group('PracticeDifficulty stable codes', () {
    const expected = {
      PracticeDifficulty.beginner: 'beginner',
      PracticeDifficulty.intermediate: 'intermediate',
      PracticeDifficulty.advanced: 'advanced',
    };

    test('pins every code, round-trips, and rejects unknown codes', () {
      expect(expected.keys, unorderedEquals(PracticeDifficulty.values));
      expect(expected.values.toSet().length, expected.length);

      for (final entry in expected.entries) {
        expect(entry.key.code, entry.value);
        expect(practiceDifficultyFromCode(entry.value), entry.key);
      }
      expect(practiceDifficultyFromCode('unknown'), isNull);
    });
  });

  group('PracticeScoreDimension stable codes', () {
    const expected = {
      PracticeScoreDimension.completion: 'completion',
      PracticeScoreDimension.rhythm: 'rhythm',
      PracticeScoreDimension.direction: 'direction',
      PracticeScoreDimension.chord: 'chord',
      PracticeScoreDimension.consistency: 'consistency',
      PracticeScoreDimension.overall: 'overall',
    };

    test('pins every code, round-trips, and rejects unknown codes', () {
      expect(expected.keys, unorderedEquals(PracticeScoreDimension.values));
      expect(expected.values.toSet().length, expected.length);

      for (final entry in expected.entries) {
        expect(entry.key.code, entry.value);
        expect(practiceScoreDimensionFromCode(entry.value), entry.key);
      }
      expect(practiceScoreDimensionFromCode('unknown'), isNull);
    });
  });

  group('ExtraStrumPolicy stable codes', () {
    const expected = {
      ExtraStrumPolicy.ignore: 'ignore',
      ExtraStrumPolicy.countInformationally: 'countInformationally',
      ExtraStrumPolicy.penalizeRhythm: 'penalizeRhythm',
    };

    test('pins every code, round-trips, and rejects unknown codes', () {
      expect(expected.keys, unorderedEquals(ExtraStrumPolicy.values));
      expect(expected.values.toSet().length, expected.length);

      for (final entry in expected.entries) {
        expect(entry.key.code, entry.value);
        expect(extraStrumPolicyFromCode(entry.value), entry.key);
      }
      expect(extraStrumPolicyFromCode('unknown'), isNull);
    });
  });

  group('TimingGrade stable codes', () {
    const expected = {
      TimingGrade.perfect: 'perfect',
      TimingGrade.good: 'good',
      TimingGrade.early: 'early',
      TimingGrade.late: 'late',
      TimingGrade.missed: 'missed',
      TimingGrade.notApplicable: 'notApplicable',
    };

    test('pins every code, round-trips, and rejects unknown codes', () {
      expect(expected.keys, unorderedEquals(TimingGrade.values));
      expect(expected.values.toSet().length, expected.length);

      for (final entry in expected.entries) {
        expect(entry.key.code, entry.value);
        expect(timingGradeFromCode(entry.value), entry.key);
      }
      expect(timingGradeFromCode('unknown'), isNull);
    });
  });

  group('PracticeAttemptOutcome stable codes', () {
    const expected = {
      PracticeAttemptOutcome.passed: 'passed',
      PracticeAttemptOutcome.failed: 'failed',
      PracticeAttemptOutcome.incomplete: 'incomplete',
      PracticeAttemptOutcome.notScored: 'notScored',
    };

    test('pins every code, round-trips, and rejects unknown codes', () {
      expect(expected.keys, unorderedEquals(PracticeAttemptOutcome.values));
      expect(expected.values.toSet().length, expected.length);

      for (final entry in expected.entries) {
        expect(entry.key.code, entry.value);
        expect(practiceAttemptOutcomeFromCode(entry.value), entry.key);
      }
      expect(practiceAttemptOutcomeFromCode('unknown'), isNull);
    });
  });

  group('PracticeFinishReason stable codes', () {
    const expected = {
      PracticeFinishReason.completedAllTargets: 'completedAllTargets',
      PracticeFinishReason.userFinished: 'userFinished',
      PracticeFinishReason.cancelled: 'cancelled',
      PracticeFinishReason.timedOut: 'timedOut',
      PracticeFinishReason.interrupted: 'interrupted',
      PracticeFinishReason.failed: 'failed',
    };

    test('pins every code, round-trips, and rejects unknown codes', () {
      expect(expected.keys, unorderedEquals(PracticeFinishReason.values));
      expect(expected.values.toSet().length, expected.length);

      for (final entry in expected.entries) {
        expect(entry.key.code, entry.value);
        expect(practiceFinishReasonFromCode(entry.value), entry.key);
      }
      expect(practiceFinishReasonFromCode('unknown'), isNull);
    });
  });
}
