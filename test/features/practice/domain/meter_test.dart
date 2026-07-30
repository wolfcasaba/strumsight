import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_validation.dart';

void main() {
  group('Meter validation', () {
    test('accepts 4/4, 3/4, and supported 6/8 meter', () {
      expect(const Meter(beatsPerBar: 4).validate(), isEmpty);
      expect(const Meter(beatsPerBar: 3).validate(), isEmpty);
      expect(const Meter(beatsPerBar: 6, beatUnit: 8).validate(), isEmpty);
    });

    test('rejects beats-per-bar values outside 1 through 16', () {
      for (final beatsPerBar in [0, 17]) {
        expect(
          Meter(
            beatsPerBar: beatsPerBar,
          ).validate().map((failure) => failure.code),
          [PracticeValidationCode.meterBeatsPerBarOutOfRange],
        );
      }
    });

    test('rejects unsupported beat units', () {
      expect(
        const Meter(
          beatsPerBar: 4,
          beatUnit: 5,
        ).validate().map((failure) => failure.code),
        [PracticeValidationCode.meterBeatUnitUnsupported],
      );
    });

    test('aggregates independent field failures', () {
      final failures = const Meter(beatsPerBar: 0, beatUnit: 5).validate();

      expect(
        failures.map((failure) => failure.code),
        unorderedEquals({
          PracticeValidationCode.meterBeatsPerBarOutOfRange,
          PracticeValidationCode.meterBeatUnitUnsupported,
        }),
      );
    });
  });

  group('Meter tick arithmetic', () {
    test('computes exact ticks per bar for supported meters', () {
      expect(const Meter(beatsPerBar: 4).ticksPerBar, 1920);
      expect(const Meter(beatsPerBar: 3).ticksPerBar, 1440);
      expect(const Meter(beatsPerBar: 6, beatUnit: 8).ticksPerBar, 1440);
      expect(const Meter(beatsPerBar: 2, beatUnit: 2).ticksPerBar, 1920);
    });

    test('fails fast symmetrically for every invalid input field', () {
      for (final beatsPerBar in [0, -1, 17]) {
        expect(
          () => Meter(beatsPerBar: beatsPerBar).ticksPerBar,
          throwsStateError,
        );
      }
      expect(
        () => const Meter(beatsPerBar: 4, beatUnit: 5).ticksPerBar,
        throwsStateError,
      );
    });
  });

  group('Meter value semantics', () {
    test('uses both fields as its value identity', () {
      const meter = Meter(beatsPerBar: 3);
      const sameValue = Meter(beatsPerBar: 3);

      expect(meter, sameValue);
      expect(meter.hashCode, sameValue.hashCode);
      expect(meter, isNot(const Meter(beatsPerBar: 4)));
      expect(meter, isNot(const Meter(beatsPerBar: 3, beatUnit: 8)));
      expect(meter.toString(), 'Meter(3/4)');
    });
  });
}
