import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/speed_builder_policy.dart';
import 'package:strumsight/features/practice/domain/model/practice_validation.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';

void main() {
  group('SpeedBuilderPolicy A1', () {
    test('step BPM accepts the closed 1 to 20 range', () {
      expect(
        _policy(stepBpm: 0).validate(),
        _hasCode(SpeedBuilderValidationCode.stepBpmOutOfRange),
      );
      expect(_policy(stepBpm: 1).validate(), isEmpty);
      expect(_policy(stepBpm: 20).validate(), isEmpty);
      expect(
        _policy(stepBpm: 21).validate(),
        _hasCode(SpeedBuilderValidationCode.stepBpmOutOfRange),
      );
    });

    test('max attempts accepts the closed 1 to 100 range', () {
      expect(
        _policy(maxAttempts: 0).validate(),
        _hasCode(SpeedBuilderValidationCode.maxAttemptsOutOfRange),
      );
      expect(_policy(maxAttempts: 1).validate(), isEmpty);
      expect(_policy(maxAttempts: 100).validate(), isEmpty);
      expect(
        _policy(maxAttempts: 101).validate(),
        _hasCode(SpeedBuilderValidationCode.maxAttemptsOutOfRange),
      );
    });

    test('start BPM follows the Tempo closed range', () {
      expect(
        _policy(startBpm: 29).validate(),
        _hasCode(SpeedBuilderValidationCode.startBpmInvalid),
      );
      expect(_policy(startBpm: 30).validate(), isEmpty);
      expect(_policy(startBpm: 300, targetBpm: 300).validate(), isEmpty);
      expect(
        _policy(startBpm: 301, targetBpm: 301).validate(),
        _hasCode(SpeedBuilderValidationCode.startBpmInvalid),
      );
    });

    test('target BPM may equal or exceed start but not precede it', () {
      expect(
        _policy(startBpm: 80, targetBpm: 79).validate(),
        _hasCode(SpeedBuilderValidationCode.targetBeforeStart),
      );
      expect(_policy(startBpm: 80, targetBpm: 80).validate(), isEmpty);
      expect(_policy(startBpm: 80, targetBpm: 81).validate(), isEmpty);
    });

    test('target BPM follows the Tempo closed range', () {
      expect(
        _policy(startBpm: 30, targetBpm: 29).validate(),
        _hasCode(SpeedBuilderValidationCode.targetBpmInvalid),
      );
      expect(_policy(startBpm: 30, targetBpm: 30).validate(), isEmpty);
      expect(_policy(startBpm: 30, targetBpm: 300).validate(), isEmpty);
      expect(
        _policy(startBpm: 30, targetBpm: 301).validate(),
        _hasCode(SpeedBuilderValidationCode.targetBpmInvalid),
      );
    });

    test('rejects non-finite tempo and step values', () {
      expect(
        _policy(startBpm: double.nan).validate(),
        _hasCode(SpeedBuilderValidationCode.startBpmInvalid),
      );
      expect(
        _policy(targetBpm: double.infinity).validate(),
        _hasCode(SpeedBuilderValidationCode.targetBpmInvalid),
      );
      expect(
        _policy(stepBpm: double.nan).validate(),
        _hasCode(SpeedBuilderValidationCode.stepBpmOutOfRange),
      );
    });

    test('consecutive-pass and fail thresholds must be positive', () {
      expect(
        _policy(requiredConsecutivePasses: 0).validate(),
        _hasCode(SpeedBuilderValidationCode.requiredPassesNonPositive),
      );
      expect(
        _policy(requiredConsecutivePasses: -1).validate(),
        _hasCode(SpeedBuilderValidationCode.requiredPassesNonPositive),
      );
      expect(
        _policy(reduceAfterConsecutiveFails: 0).validate(),
        _hasCode(SpeedBuilderValidationCode.reduceFailsNonPositive),
      );
      expect(
        _policy(reduceAfterConsecutiveFails: -1).validate(),
        _hasCode(SpeedBuilderValidationCode.reduceFailsNonPositive),
      );
      expect(
        _policy(
          requiredConsecutivePasses: 1,
          reduceAfterConsecutiveFails: 1,
        ).validate(),
        isEmpty,
      );
    });

    test('returns every independent validation failure', () {
      final codes = _policy(
        startBpm: 29,
        targetBpm: 28,
        stepBpm: 0,
        maxAttempts: 0,
        requiredConsecutivePasses: 0,
        reduceAfterConsecutiveFails: 0,
      ).validate().map((failure) => failure.code).toSet();

      expect(
        codes,
        containsAll(<String>{
          SpeedBuilderValidationCode.startBpmInvalid,
          SpeedBuilderValidationCode.targetBpmInvalid,
          SpeedBuilderValidationCode.targetBeforeStart,
          SpeedBuilderValidationCode.stepBpmOutOfRange,
          SpeedBuilderValidationCode.maxAttemptsOutOfRange,
          SpeedBuilderValidationCode.requiredPassesNonPositive,
          SpeedBuilderValidationCode.reduceFailsNonPositive,
        }),
      );
    });
  });
}

SpeedBuilderPolicy _policy({
  double startBpm = 80,
  double targetBpm = 120,
  double stepBpm = 10,
  int maxAttempts = 20,
  int requiredConsecutivePasses = 2,
  int reduceAfterConsecutiveFails = 2,
}) => SpeedBuilderPolicy(
  startBpm: Tempo(startBpm),
  targetBpm: Tempo(targetBpm),
  stepBpm: stepBpm,
  maxAttempts: maxAttempts,
  requiredConsecutivePasses: requiredConsecutivePasses,
  reduceAfterConsecutiveFails: reduceAfterConsecutiveFails,
);

Matcher _hasCode(String code) => contains(
  predicate<PracticeValidationFailure>((failure) => failure.code == code),
);
