import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/practice_validation.dart';

void main() {
  group('BeatPosition subdivisions', () {
    test('uses 480 ticks per quarter-note beat', () {
      expect(BeatPosition.ticksPerBeat, 480);
      expect(BeatPosition.quarters(1).ticks, 480);
      expect(BeatPosition.eighths(1).ticks, 240);
      expect(BeatPosition.sixteenths(1).ticks, 120);
      expect(BeatPosition.eighthTriplets(1).ticks, 160);
    });

    test('represents supported fractions with exact integer equality', () {
      expect(BeatPosition.eighthTriplets(3), BeatPosition.quarters(1));
      expect(BeatPosition.sixteenths(2), BeatPosition.eighths(1));
      expect(BeatPosition.eighthTriplets(6), BeatPosition.quarters(2));
      expect(BeatPosition.eighthTriplets(6).ticks, 960);
    });
  });

  group('BeatPosition legacy bridge', () {
    test('converts the current half-beat grid without deviation', () {
      const legacyBeats = <double>[0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0];
      const expectedTicks = <int>[0, 240, 480, 720, 960, 1200, 1440];

      for (var index = 0; index < legacyBeats.length; index++) {
        final position = BeatPosition.fromLegacyBeats(legacyBeats[index]);

        expect(position.ticks, expectedTicks[index]);
        expect(position.toLegacyBeats(), legacyBeats[index]);
      }
    });

    test('round-trips every supported deterministic subdivision position', () {
      const ticks = <int>[0, 120, 160, 240, 320, 480, 720, 960, 1440, 1920];

      for (final tick in ticks) {
        final position = BeatPosition.fromTicks(tick);

        expect(
          BeatPosition.fromLegacyBeats(position.toLegacyBeats()),
          position,
        );
      }
    });

    test('rounds one third of a beat to the nearest exact triplet tick', () {
      final position = BeatPosition.fromLegacyBeats(1 / 3);

      expect(position, BeatPosition.eighthTriplets(1));
      expect(position.ticks, 160);
    });

    test('rejects non-finite legacy input explicitly', () {
      expect(
        () => BeatPosition.fromLegacyBeats(double.nan),
        throwsArgumentError,
      );
      expect(
        () => BeatPosition.fromLegacyBeats(double.infinity),
        throwsArgumentError,
      );
      expect(
        () => BeatPosition.fromLegacyBeats(double.negativeInfinity),
        throwsArgumentError,
      );
    });
  });

  group('BeatPosition invariants', () {
    test('rejects negative data-driven positions in every runtime path', () {
      final negativeFailure = isA<ArgumentError>().having(
        (error) => error.message.toString(),
        'message',
        contains(PracticeValidationCode.beatPositionNegative),
      );

      expect(() => BeatPosition.fromTicks(-1), throwsA(negativeFailure));
      expect(
        () => BeatPosition.fromLegacyBeats(-0.5),
        throwsA(negativeFailure),
      );
      expect(() => BeatPosition.eighths(-1), throwsA(negativeFailure));
      expect(
        () => BeatPosition.eighths(1) - BeatPosition.quarters(1),
        throwsA(negativeFailure),
      );
    });

    test('keeps the const constructor guarded in checked builds', () {
      expect(() => BeatPosition(-1), throwsA(isA<AssertionError>()));
    });
  });

  group('BeatPosition value operations', () {
    test('sorts deterministically and compareTo agrees with equality', () {
      final positions = [
        BeatPosition.quarters(2),
        const BeatPosition(0),
        BeatPosition.eighthTriplets(1),
        BeatPosition.eighths(1),
        BeatPosition.quarters(1),
      ]..sort();

      expect(
        positions.map((position) => position.ticks),
        orderedEquals([0, 160, 240, 480, 960]),
      );

      final left = BeatPosition.fromTicks(480);
      final right = BeatPosition.quarters(1);
      expect(left.compareTo(right), 0);
      expect(left, right);
      expect(left.hashCode, right.hashCode);
    });

    test('adds and subtracts positions exactly', () {
      expect(
        BeatPosition.quarters(1) + BeatPosition.eighths(1),
        BeatPosition.fromTicks(720),
      );
      expect(
        BeatPosition.quarters(1) - BeatPosition.eighths(1),
        BeatPosition.eighths(1),
      );
    });

    test('has a deterministic diagnostic representation', () {
      expect(BeatPosition.fromTicks(480).toString(), 'BeatPosition(480 ticks)');
    });
  });
}
