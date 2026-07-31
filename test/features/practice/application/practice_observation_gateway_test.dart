import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/application/practice_observation_gateway.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/practice_validation.dart';
import '../../../support/fake_practice_observation_gateway.dart';

void main() {
  group('PracticeObservationConfig', () {
    test('uses the brief defaults', () {
      const config = PracticeObservationConfig();

      expect(config.strumMinConfidence, 0.55);
      expect(config.chordMinConfidence, 0.60);
      expect(config.chordStableDuration, const Duration(milliseconds: 180));
      expect(config.maxFrameDeliveryLag, const Duration(milliseconds: 500));
    });

    test('has value equality', () {
      const first = PracticeObservationConfig();
      const same = PracticeObservationConfig();
      const different = PracticeObservationConfig(strumMinConfidence: 0.7);

      expect(first, same);
      expect(first.hashCode, same.hashCode);
      expect(first, isNot(different));
    });

    test('validates every confidence and duration boundary', () {
      final invalid = const PracticeObservationConfig(
        strumMinConfidence: double.nan,
        chordMinConfidence: 1.5,
        chordStableDuration: Duration.zero,
        maxFrameDeliveryLag: Duration.zero,
      ).validate();

      expect(
        invalid.map((failure) => failure.code),
        containsAll(<String>[
          PracticeValidationCode.observationConfigConfidenceOutOfRange,
          PracticeValidationCode.observationConfigStableDurationNonPositive,
          PracticeValidationCode.observationConfigMaxLagNonPositive,
        ]),
      );
    });

    test('invalid config is represented by configuration.invalid', () {
      final config = const PracticeObservationConfig(strumMinConfidence: 1.5);
      final failures = config.validate();
      final failure = ConfigurationFailure(cause: failures);

      expect(failure.code, FailureCode.configurationInvalid);
      expect(failure.cause, failures);
    });
  });

  group('FakePracticeObservationGateway', () {
    test('keeps start and stop idempotent', () async {
      final gateway = FakePracticeObservationGateway();
      addTearDown(gateway.dispose);
      const config = PracticeObservationConfig();

      expect((await gateway.start(config: config)).isSuccess, isTrue);
      expect((await gateway.start(config: config)).isSuccess, isTrue);
      expect(gateway.startCalls, 1);

      expect((await gateway.stop()).isSuccess, isTrue);
      expect((await gateway.stop()).isSuccess, isTrue);
      expect(gateway.stopCalls, 1);
    });

    test('records expected chord and exposes a controllable stream', () async {
      final gateway = FakePracticeObservationGateway();
      addTearDown(gateway.dispose);
      final observations = <PracticeObservation>[];
      final subscription = gateway.observations.listen(observations.add);
      addTearDown(subscription.cancel);

      gateway.setExpectedChord('G');
      gateway.emit(
        const StrumObservation(
          at: Duration.zero,
          sequence: 0,
          direction: StrumDirection.down,
          confidence: 0.8,
        ),
      );
      await pumpEventQueue();

      expect(gateway.expectedChordCalls, ['G']);
      expect(observations, hasLength(1));
      expect(observations.single, isA<StrumObservation>());
    });

    test('returns the injected start result', () async {
      const failure = AudioFailure(code: FailureCode.audioCaptureFailed);
      final gateway = FakePracticeObservationGateway(
        startResult: const Failure(failure),
      );
      addTearDown(gateway.dispose);

      final result = await gateway.start(
        config: const PracticeObservationConfig(),
      );

      expect(result.failureOrNull, failure);
      expect(gateway.startCalls, 1);
    });

    test('rejects operations after dispose', () async {
      final gateway = FakePracticeObservationGateway();
      await gateway.dispose();

      expect(
        (await gateway.start(
          config: const PracticeObservationConfig(),
        )).failureOrNull?.code,
        FailureCode.practiceObservationGatewayDisposed,
      );
      expect(
        (await gateway.stop()).failureOrNull?.code,
        FailureCode.practiceObservationGatewayDisposed,
      );
    });
  });
}
