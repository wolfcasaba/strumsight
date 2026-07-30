import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_config.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';

void main() {
  group('PracticeSessionConfig validation', () {
    test('accepts all closed range boundaries', () {
      expect(
        _config(
          countInBars: 0,
          loopCount: 1,
          inputLatency: Duration.zero,
          visualLatency: Duration.zero,
        ).validate(),
        isEmpty,
      );
      expect(
        _config(
          countInBars: 4,
          loopCount: 32,
          inputLatency: const Duration(milliseconds: 500),
          visualLatency: const Duration(milliseconds: 500),
        ).validate(),
        isEmpty,
      );
    });

    test('reports empty IDs and an invalid snapshot version', () {
      final codes = _config(
        definitionId: '',
        definitionSnapshotVersion: 0,
        scoringProfileId: '',
      ).validate().map((failure) => failure.code);

      expect(
        codes,
        containsAll({
          'config.definitionId.empty',
          'config.snapshotVersion.invalid',
          'config.scoringProfileId.empty',
        }),
      );
    });

    test('rejects count-in values outside zero through four', () {
      for (final countInBars in [-1, 5]) {
        expect(
          _config(
            countInBars: countInBars,
          ).validate().map((failure) => failure.code),
          contains('config.countInBars.outOfRange'),
        );
      }
    });

    test('rejects loop counts outside one through 32', () {
      for (final loopCount in [0, 33]) {
        expect(
          _config(
            loopCount: loopCount,
          ).validate().map((failure) => failure.code),
          contains('config.loopCount.outOfRange'),
        );
      }
    });

    test('rejects input latency outside zero through 500 milliseconds', () {
      for (final latency in [
        const Duration(microseconds: -1),
        const Duration(milliseconds: 500, microseconds: 1),
      ]) {
        expect(
          _config(
            inputLatency: latency,
          ).validate().map((failure) => failure.code),
          contains('config.inputLatency.outOfRange'),
        );
      }
    });

    test('rejects visual latency outside zero through 500 milliseconds', () {
      for (final latency in [
        const Duration(microseconds: -1),
        const Duration(milliseconds: 500, microseconds: 1),
      ]) {
        expect(
          _config(
            visualLatency: latency,
          ).validate().map((failure) => failure.code),
          contains('config.visualLatency.outOfRange'),
        );
      }
    });

    test('requires a strictly positive session timeout', () {
      for (final timeout in [Duration.zero, const Duration(microseconds: -1)]) {
        expect(
          _config(
            sessionTimeout: timeout,
          ).validate().map((failure) => failure.code),
          contains('config.sessionTimeout.nonPositive'),
        );
      }
    });

    test('passes nested Tempo failures through unchanged', () {
      expect(
        _config(
          effectiveTempo: const Tempo(500),
        ).validate().map((failure) => failure.code),
        contains('tempo.bpm.outOfRange'),
      );
    });

    test('aggregates at least three independent failures', () {
      final invalid = _config(
        definitionId: '',
        definitionSnapshotVersion: 0,
        effectiveTempo: const Tempo(500),
        countInBars: -1,
        loopCount: 0,
        scoringProfileId: '',
        sessionTimeout: Duration.zero,
      );

      expect(invalid.validate(), hasLength(greaterThanOrEqualTo(3)));
      expect(
        invalid.validate().map((failure) => failure.code),
        containsAll({
          'config.definitionId.empty',
          'config.snapshotVersion.invalid',
          'tempo.bpm.outOfRange',
          'config.countInBars.outOfRange',
          'config.loopCount.outOfRange',
          'config.scoringProfileId.empty',
          'config.sessionTimeout.nonPositive',
        }),
      );
    });
  });

  group('PracticeSessionConfig value semantics', () {
    test(
      'compares all fields and copyWith preserves or changes explicitly',
      () {
        final config = _config(easyVariationId: 'easy');
        final sameValue = _config(easyVariationId: 'easy');
        final changed = config.copyWith(loopCount: 3);
        final cleared = config.copyWith(clearEasyVariationId: true);

        expect(config, sameValue);
        expect(config.hashCode, sameValue.hashCode);
        expect(config, isNot(changed));
        expect(changed.loopCount, 3);
        expect(changed.definitionId, config.definitionId);
        expect(cleared.easyVariationId, isNull);
      },
    );
  });
}

PracticeSessionConfig _config({
  String definitionId = 'definition',
  int definitionSnapshotVersion = 1,
  Tempo effectiveTempo = const Tempo(120),
  int countInBars = 1,
  int loopCount = 2,
  bool metronomeEnabled = true,
  bool accentEnabled = true,
  bool backingEnabled = false,
  String scoringProfileId = 'legacyLearnParity',
  String? easyVariationId,
  Duration inputLatency = const Duration(milliseconds: 10),
  Duration visualLatency = const Duration(milliseconds: 20),
  bool expectedChordHintEnabled = true,
  Duration sessionTimeout = const Duration(minutes: 10),
  bool reducedMotion = false,
}) => PracticeSessionConfig(
  definitionId: definitionId,
  definitionSnapshotVersion: definitionSnapshotVersion,
  effectiveTempo: effectiveTempo,
  countInBars: countInBars,
  loopCount: loopCount,
  metronomeEnabled: metronomeEnabled,
  accentEnabled: accentEnabled,
  backingEnabled: backingEnabled,
  scoringProfileId: scoringProfileId,
  easyVariationId: easyVariationId,
  inputLatency: inputLatency,
  visualLatency: visualLatency,
  expectedChordHintEnabled: expectedChordHintEnabled,
  sessionTimeout: sessionTimeout,
  reducedMotion: reducedMotion,
);
