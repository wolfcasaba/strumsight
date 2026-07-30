import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/practice_validation.dart';

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
        }),
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
