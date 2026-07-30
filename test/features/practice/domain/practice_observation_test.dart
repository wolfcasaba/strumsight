import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';

void main() {
  group('PracticeObservation validation', () {
    test('accepts closed confidence boundaries for both observation types', () {
      for (final confidence in [0.0, 1.0]) {
        expect(
          StrumObservation(
            at: Duration.zero,
            sequence: 0,
            direction: StrumDirection.down,
            confidence: confidence,
          ).validate(),
          isEmpty,
        );
        expect(
          ChordObservation(
            at: Duration.zero,
            label: 'C',
            confidence: confidence,
          ).validate(),
          isEmpty,
        );
      }
    });

    test('rejects a negative timestamp', () {
      expect(
        const StrumObservation(
          at: Duration(microseconds: -1),
          sequence: 0,
          direction: StrumDirection.down,
          confidence: 1,
        ).validate().map((failure) => failure.code),
        contains('observation.at.negative'),
      );
    });

    test('rejects a negative strum sequence', () {
      expect(
        const StrumObservation(
          at: Duration.zero,
          sequence: -1,
          direction: StrumDirection.down,
          confidence: 1,
        ).validate().map((failure) => failure.code),
        contains('observation.sequence.negative'),
      );
    });

    test('reports non-finite confidence without a duplicate range failure', () {
      for (final confidence in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          StrumObservation(
            at: Duration.zero,
            sequence: 0,
            direction: StrumDirection.down,
            confidence: confidence,
          ).validate().map((failure) => failure.code),
          ['observation.confidence.notFinite'],
        );
      }
    });

    test('rejects finite confidence outside zero through one', () {
      for (final confidence in [-0.01, 1.01]) {
        expect(
          StrumObservation(
            at: Duration.zero,
            sequence: 0,
            direction: StrumDirection.down,
            confidence: confidence,
          ).validate().map((failure) => failure.code),
          contains('observation.confidence.outOfRange'),
        );
      }
    });

    test('uses the canonical chord-label contract including null', () {
      for (final label in <String?>['C', 'C#m', 'Bm', null]) {
        expect(
          ChordObservation(
            at: Duration.zero,
            label: label,
            confidence: 1,
          ).validate(),
          isEmpty,
          reason: '$label',
        );
      }
      for (final label in ['', 'N.C.', 'Bb', 'Cmaj7', 'c', ' C']) {
        expect(
          ChordObservation(
            at: Duration.zero,
            label: label,
            confidence: 1,
          ).validate().map((failure) => failure.code),
          contains('observation.chord.invalid'),
          reason: label,
        );
      }
    });
  });

  group('PracticeObservation value semantics', () {
    test('compares each concrete subtype structurally', () {
      final strum = StrumObservation(
        at: const Duration(milliseconds: 10),
        sequence: 2,
        direction: StrumDirection.up,
        confidence: 0.8,
      );
      final sameStrum = StrumObservation(
        at: const Duration(milliseconds: 10),
        sequence: 2,
        direction: StrumDirection.up,
        confidence: 0.8,
      );
      final chord = ChordObservation(
        at: const Duration(milliseconds: 10),
        label: 'C#m',
        confidence: 0.8,
      );
      final sameChord = ChordObservation(
        at: const Duration(milliseconds: 10),
        label: 'C#m',
        confidence: 0.8,
      );

      expect(identical(strum, sameStrum), isFalse);
      expect(strum, sameStrum);
      expect(strum.hashCode, sameStrum.hashCode);
      expect(
        strum,
        isNot(
          const StrumObservation(
            at: Duration(milliseconds: 10),
            sequence: 3,
            direction: StrumDirection.up,
            confidence: 0.8,
          ),
        ),
      );
      expect(identical(chord, sameChord), isFalse);
      expect(chord, sameChord);
      expect(chord.hashCode, sameChord.hashCode);
      expect(
        chord,
        isNot(
          const ChordObservation(
            at: Duration(milliseconds: 10),
            label: 'D',
            confidence: 0.8,
          ),
        ),
      );
    });
  });
}
