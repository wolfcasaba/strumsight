import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_validation.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';

void main() {
  group('PracticeValidationCode', () {
    test('defines the complete stable code set', () {
      expect(
        PracticeValidationCode.values,
        unorderedEquals({
          'tempo.bpm.notFinite',
          'tempo.bpm.outOfRange',
          'meter.beatsPerBar.outOfRange',
          'meter.beatUnit.unsupported',
          'beatPosition.negative',
          'event.id.empty',
          'event.chord.invalid',
          'event.duration.nonPositive',
          'event.scorable.missing',
          'event.marker.scorable',
          'events.empty',
          'events.unsorted',
          'events.idDuplicate',
          'events.positionDuplicate',
          'event.position.outOfRange',
          'definition.id.empty',
          'definition.schemaVersion.invalid',
          'definition.titleKey.empty',
          'definition.descriptionKey.empty',
          'definition.totalBeats.nonPositive',
          'definition.scoringProfile.incompatibleWithMode',
          'config.definitionId.empty',
          'config.snapshotVersion.invalid',
          'config.countInBars.outOfRange',
          'config.loopCount.outOfRange',
          'config.inputLatency.outOfRange',
          'config.visualLatency.outOfRange',
          'config.sessionTimeout.nonPositive',
          'config.scoringProfileId.empty',
          'observation.at.negative',
          'observation.sequence.negative',
          'observation.confidence.notFinite',
          'observation.confidence.outOfRange',
          'observation.chord.invalid',
          'verdict.targetEventId.empty',
          'verdict.eventScore.notFinite',
          'verdict.eventScore.outOfRange',
          'verdict.match.inconsistent',
          'verdict.coachingCode.unknown',
          'metric.value.notFinite',
          'metric.value.outOfRange',
          'metric.insufficientData.reasonEmpty',
          'metrics.totalTargets.negative',
          'metrics.resolvedTargets.exceedsTotal',
          'metrics.maxCombo.negative',
          'metrics.scorePoints.negative',
          'metrics.meanAbsoluteOffset.negative',
          'attempt.index.negative',
          'attempt.verdicts.targetDuplicate',
          'session.id.empty',
          'session.attempts.empty',
          'session.attempts.unordered',
          'session.duration.negative',
          'session.coachingSummary.unknownCode',
          'scoringProfile.id.empty',
          'scoringProfile.window.nonPositive',
          'scoringProfile.window.ordering',
          'scoringProfile.weights.negative',
          'scoringProfile.weights.sumNotHundred',
          'scoringProfile.threshold.outOfRange',
        }),
      );
    });

    test('pins the five pre-existing codes at their producing boundaries', () {
      expect(const Tempo(301).validate().map((failure) => failure.code), [
        'tempo.bpm.outOfRange',
      ]);
      expect(Tempo(double.nan).validate().map((failure) => failure.code), [
        'tempo.bpm.notFinite',
      ]);
      expect(
        const Meter(beatsPerBar: 0).validate().map((failure) => failure.code),
        ['meter.beatsPerBar.outOfRange'],
      );
      expect(
        const Meter(
          beatsPerBar: 4,
          beatUnit: 5,
        ).validate().map((failure) => failure.code),
        ['meter.beatUnit.unsupported'],
      );
      expect(
        () => BeatPosition.fromTicks(-1),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message.toString(),
            'message',
            contains('beatPosition.negative'),
          ),
        ),
      );
    });
  });

  group('PracticeValidationFailure', () {
    test('has value semantics', () {
      const failure = PracticeValidationFailure(
        code: PracticeValidationCode.tempoBpmOutOfRange,
        message: 'Tempo must be between 30.0 and 300.0 BPM.',
      );
      const sameValue = PracticeValidationFailure(
        code: PracticeValidationCode.tempoBpmOutOfRange,
        message: 'Tempo must be between 30.0 and 300.0 BPM.',
      );
      const differentCode = PracticeValidationFailure(
        code: PracticeValidationCode.tempoBpmNotFinite,
        message: 'Tempo must be between 30.0 and 300.0 BPM.',
      );
      const differentMessage = PracticeValidationFailure(
        code: PracticeValidationCode.tempoBpmOutOfRange,
        message: 'Different message.',
      );

      expect(failure, sameValue);
      expect(failure.hashCode, sameValue.hashCode);
      expect(failure, isNot(differentCode));
      expect(failure, isNot(differentMessage));
    });

    test('has a deterministic diagnostic representation', () {
      const failure = PracticeValidationFailure(
        code: PracticeValidationCode.beatPositionNegative,
        message: 'Musical positions cannot be negative.',
      );

      expect(
        failure.toString(),
        'PracticeValidationFailure('
        'code: beatPosition.negative, '
        'message: Musical positions cannot be negative.)',
      );
    });
  });
}
