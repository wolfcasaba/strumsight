import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';

void main() {
  const validProfile = ScoringProfile(
    id: 'strum',
    matchWindow: Duration(milliseconds: 280),
    perfectWindow: Duration(milliseconds: 50),
    goodWindow: Duration(milliseconds: 120),
    extraStrumPolicy: ExtraStrumPolicy.ignore,
    weights: {
      PracticeScoreDimension.rhythm: 55,
      PracticeScoreDimension.direction: 45,
    },
    completionThresholdPercent: 85,
    overallThresholdPercent: 70,
  );

  group('ScoringProfile validation', () {
    test('accepts a valid weighted profile and an empty weight map', () {
      expect(validProfile.validate(), isEmpty);
      expect(
        const ScoringProfile(
          id: 'free',
          matchWindow: Duration(milliseconds: 280),
          perfectWindow: Duration(milliseconds: 50),
          goodWindow: Duration(milliseconds: 120),
          extraStrumPolicy: ExtraStrumPolicy.ignore,
          weights: {},
          completionThresholdPercent: 85,
          overallThresholdPercent: 70,
        ).validate(),
        isEmpty,
      );
    });

    test('accepts closed threshold endpoints and equal positive windows', () {
      expect(
        const ScoringProfile(
          id: 'closed-boundaries',
          matchWindow: Duration(milliseconds: 50),
          perfectWindow: Duration(milliseconds: 50),
          goodWindow: Duration(milliseconds: 50),
          extraStrumPolicy: ExtraStrumPolicy.ignore,
          weights: {
            PracticeScoreDimension.rhythm: 55,
            PracticeScoreDimension.direction: 45,
          },
          completionThresholdPercent: 0,
          overallThresholdPercent: 100,
        ).validate(),
        isEmpty,
      );
    });

    test('pins the legacy Learn parity profile literals', () {
      const profile = ScoringProfile.legacyLearnParity;

      expect(profile.id, 'legacyLearnParity');
      expect(profile.matchWindow, const Duration(milliseconds: 280));
      expect(profile.perfectWindow, const Duration(milliseconds: 50));
      expect(profile.goodWindow, const Duration(milliseconds: 120));
      expect(profile.extraStrumPolicy, ExtraStrumPolicy.ignore);
      expect(profile.completionThresholdPercent, 85);
      expect(profile.overallThresholdPercent, 70);
      expect(profile.weights, {
        PracticeScoreDimension.rhythm: 55,
        PracticeScoreDimension.direction: 45,
      });
      expect(profile.validate(), isEmpty);
    });

    test(
      'validates the four built-in non-strum profiles and pins literals',
      () {
        expect(ScoringProfile.chordChangeDefault.validate(), isEmpty);
        expect(ScoringProfile.chordChangeDefault.id, 'chordChangeDefault');
        expect(
          ScoringProfile.chordChangeDefault.matchWindow,
          const Duration(milliseconds: 280),
        );
        expect(
          ScoringProfile.chordChangeDefault.perfectWindow,
          const Duration(milliseconds: 50),
        );
        expect(
          ScoringProfile.chordChangeDefault.goodWindow,
          const Duration(milliseconds: 120),
        );
        expect(
          ScoringProfile.chordChangeDefault.extraStrumPolicy,
          ExtraStrumPolicy.ignore,
        );
        expect(
          ScoringProfile.chordChangeDefault.completionThresholdPercent,
          85,
        );
        expect(ScoringProfile.chordChangeDefault.overallThresholdPercent, 70);
        expect(ScoringProfile.chordChangeDefault.weights, {
          PracticeScoreDimension.chord: 60,
          PracticeScoreDimension.rhythm: 40,
        });

        expect(ScoringProfile.chordProgressionDefault.validate(), isEmpty);
        expect(
          ScoringProfile.chordProgressionDefault.id,
          'chordProgressionDefault',
        );
        expect(ScoringProfile.chordProgressionDefault.weights, {
          PracticeScoreDimension.rhythm: 40,
          PracticeScoreDimension.direction: 25,
          PracticeScoreDimension.chord: 35,
        });

        expect(ScoringProfile.rhythmOnlyDefault.validate(), isEmpty);
        expect(ScoringProfile.rhythmOnlyDefault.id, 'rhythmOnlyDefault');
        expect(ScoringProfile.rhythmOnlyDefault.weights, {
          PracticeScoreDimension.rhythm: 100,
        });

        expect(ScoringProfile.freePracticeOpen.validate(), isEmpty);
        expect(ScoringProfile.freePracticeOpen.id, 'freePracticeOpen');
        expect(ScoringProfile.freePracticeOpen.weights, isEmpty);
        expect(ScoringProfile.freePracticeOpen.completionThresholdPercent, 0);
        expect(ScoringProfile.freePracticeOpen.overallThresholdPercent, 0);
      },
    );

    test('built-in non-strum profile weights exactly match their mode scored '
        'dimensions', () {
      expect(
        ScoringProfile.chordChangeDefault.weights.keys.toSet(),
        PracticeMode.chordChanges.scoredDimensions,
      );
      expect(
        ScoringProfile.chordProgressionDefault.weights.keys.toSet(),
        PracticeMode.chordProgression.scoredDimensions,
      );
      expect(
        ScoringProfile.rhythmOnlyDefault.weights.keys.toSet(),
        PracticeMode.rhythmOnly.scoredDimensions,
      );
      expect(
        ScoringProfile.freePracticeOpen.weights.keys.toSet(),
        PracticeMode.freePractice.scoredDimensions,
      );
    });

    test('reports an empty identifier with the pinned code literal', () {
      final codes = ScoringProfile(
        id: '',
        matchWindow: validProfile.matchWindow,
        perfectWindow: validProfile.perfectWindow,
        goodWindow: validProfile.goodWindow,
        extraStrumPolicy: validProfile.extraStrumPolicy,
        weights: validProfile.weights,
        completionThresholdPercent: validProfile.completionThresholdPercent,
        overallThresholdPercent: validProfile.overallThresholdPercent,
      ).validate().map((failure) => failure.code);

      expect(codes, contains('scoringProfile.id.empty'));
    });

    test('rejects zero and negative windows', () {
      for (final window in [Duration.zero, const Duration(milliseconds: -1)]) {
        final codes = ScoringProfile(
          id: validProfile.id,
          matchWindow: window,
          perfectWindow: validProfile.perfectWindow,
          goodWindow: validProfile.goodWindow,
          extraStrumPolicy: validProfile.extraStrumPolicy,
          weights: validProfile.weights,
          completionThresholdPercent: validProfile.completionThresholdPercent,
          overallThresholdPercent: validProfile.overallThresholdPercent,
        ).validate().map((failure) => failure.code);

        expect(codes, contains('scoringProfile.window.nonPositive'));
      }
    });

    test('rejects perfect greater than good and good greater than match', () {
      final perfectAfterGood = ScoringProfile(
        id: validProfile.id,
        matchWindow: validProfile.matchWindow,
        perfectWindow: const Duration(milliseconds: 121),
        goodWindow: const Duration(milliseconds: 120),
        extraStrumPolicy: validProfile.extraStrumPolicy,
        weights: validProfile.weights,
        completionThresholdPercent: validProfile.completionThresholdPercent,
        overallThresholdPercent: validProfile.overallThresholdPercent,
      );
      final goodAfterMatch = ScoringProfile(
        id: validProfile.id,
        matchWindow: const Duration(milliseconds: 280),
        perfectWindow: validProfile.perfectWindow,
        goodWindow: const Duration(milliseconds: 281),
        extraStrumPolicy: validProfile.extraStrumPolicy,
        weights: validProfile.weights,
        completionThresholdPercent: validProfile.completionThresholdPercent,
        overallThresholdPercent: validProfile.overallThresholdPercent,
      );

      expect(
        perfectAfterGood.validate().map((failure) => failure.code),
        contains('scoringProfile.window.ordering'),
      );
      expect(
        goodAfterMatch.validate().map((failure) => failure.code),
        contains('scoringProfile.window.ordering'),
      );
    });

    test('rejects weight sums of 99 and 101', () {
      for (final rhythmWeight in [54, 56]) {
        final codes = ScoringProfile(
          id: validProfile.id,
          matchWindow: validProfile.matchWindow,
          perfectWindow: validProfile.perfectWindow,
          goodWindow: validProfile.goodWindow,
          extraStrumPolicy: validProfile.extraStrumPolicy,
          weights: {
            PracticeScoreDimension.rhythm: rhythmWeight,
            PracticeScoreDimension.direction: 45,
          },
          completionThresholdPercent: validProfile.completionThresholdPercent,
          overallThresholdPercent: validProfile.overallThresholdPercent,
        ).validate().map((failure) => failure.code);

        expect(codes, contains('scoringProfile.weights.sumNotHundred'));
      }
    });

    test('rejects a negative weight independently of the exact sum', () {
      final codes = ScoringProfile(
        id: validProfile.id,
        matchWindow: validProfile.matchWindow,
        perfectWindow: validProfile.perfectWindow,
        goodWindow: validProfile.goodWindow,
        extraStrumPolicy: validProfile.extraStrumPolicy,
        weights: const {
          PracticeScoreDimension.rhythm: -1,
          PracticeScoreDimension.direction: 101,
        },
        completionThresholdPercent: validProfile.completionThresholdPercent,
        overallThresholdPercent: validProfile.overallThresholdPercent,
      ).validate().map((failure) => failure.code);

      expect(codes, contains('scoringProfile.weights.negative'));
      expect(codes, isNot(contains('scoringProfile.weights.sumNotHundred')));
    });

    test('rejects thresholds outside the closed zero to 100 range', () {
      final codes = ScoringProfile(
        id: validProfile.id,
        matchWindow: validProfile.matchWindow,
        perfectWindow: validProfile.perfectWindow,
        goodWindow: validProfile.goodWindow,
        extraStrumPolicy: validProfile.extraStrumPolicy,
        weights: validProfile.weights,
        completionThresholdPercent: -1,
        overallThresholdPercent: 101,
      ).validate().map((failure) => failure.code);

      expect(codes, contains('scoringProfile.threshold.outOfRange'));
    });

    test('aggregates independent failures in one call', () {
      const invalid = ScoringProfile(
        id: '',
        matchWindow: Duration.zero,
        perfectWindow: Duration(milliseconds: 200),
        goodWindow: Duration(milliseconds: 100),
        extraStrumPolicy: ExtraStrumPolicy.ignore,
        weights: {PracticeScoreDimension.rhythm: 99},
        completionThresholdPercent: -1,
        overallThresholdPercent: 101,
      );

      expect(
        invalid.validate().map((failure) => failure.code),
        containsAll({
          'scoringProfile.id.empty',
          'scoringProfile.window.nonPositive',
          'scoringProfile.window.ordering',
          'scoringProfile.weights.sumNotHundred',
          'scoringProfile.threshold.outOfRange',
        }),
      );
      expect(invalid.validate(), hasLength(greaterThanOrEqualTo(3)));
    });
  });

  group('ScoringProfile value semantics', () {
    test('compares the weight map structurally and hashes it by value', () {
      final profile = ScoringProfile(
        id: validProfile.id,
        matchWindow: validProfile.matchWindow,
        perfectWindow: validProfile.perfectWindow,
        goodWindow: validProfile.goodWindow,
        extraStrumPolicy: validProfile.extraStrumPolicy,
        weights: const {
          PracticeScoreDimension.rhythm: 55,
          PracticeScoreDimension.direction: 45,
        },
        completionThresholdPercent: validProfile.completionThresholdPercent,
        overallThresholdPercent: validProfile.overallThresholdPercent,
      );
      final sameValue = ScoringProfile(
        id: validProfile.id,
        matchWindow: validProfile.matchWindow,
        perfectWindow: validProfile.perfectWindow,
        goodWindow: validProfile.goodWindow,
        extraStrumPolicy: validProfile.extraStrumPolicy,
        weights: const {
          PracticeScoreDimension.direction: 45,
          PracticeScoreDimension.rhythm: 55,
        },
        completionThresholdPercent: validProfile.completionThresholdPercent,
        overallThresholdPercent: validProfile.overallThresholdPercent,
      );

      expect(profile, sameValue);
      expect(profile.hashCode, sameValue.hashCode);
      expect(
        profile,
        isNot(
          ScoringProfile(
            id: validProfile.id,
            matchWindow: validProfile.matchWindow,
            perfectWindow: validProfile.perfectWindow,
            goodWindow: validProfile.goodWindow,
            extraStrumPolicy: ExtraStrumPolicy.penalizeRhythm,
            weights: validProfile.weights,
            completionThresholdPercent: validProfile.completionThresholdPercent,
            overallThresholdPercent: validProfile.overallThresholdPercent,
          ),
        ),
      );
    });
  });
}
