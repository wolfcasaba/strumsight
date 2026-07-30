import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';

void main() {
  group('canonical practice chord labels', () {
    test('accepts null and sharp-spelled major or minor labels', () {
      for (final label in <String?>['C', 'C#m', 'Bm', null]) {
        expect(isCanonicalPracticeChordLabel(label), isTrue, reason: '$label');
        expect(
          PracticeEvent(
            id: 'event',
            position: const BeatPosition(0),
            chord: label,
            direction: StrumDirection.down,
          ).validate(),
          isEmpty,
          reason: '$label',
        );
      }
    });

    test(
      'rejects empty, no-chord, flat, extended, lowercase, and padded labels',
      () {
        for (final label in ['', 'N.C.', 'Bb', 'Cmaj7', 'c', ' C']) {
          expect(isCanonicalPracticeChordLabel(label), isFalse, reason: label);
          expect(
            PracticeEvent(
              id: 'event',
              position: const BeatPosition(0),
              chord: label,
            ).validate().map((failure) => failure.code),
            contains('event.chord.invalid'),
            reason: label,
          );
        }
      },
    );
  });

  group('PracticeEvent validation', () {
    test('accepts scored events and a marker without scored attributes', () {
      expect(
        const PracticeEvent(
          id: 'down',
          position: BeatPosition(0),
          direction: StrumDirection.down,
        ).validate(),
        isEmpty,
      );
      expect(
        const PracticeEvent(
          id: 'marker',
          position: BeatPosition(480),
          marker: true,
        ).validate(),
        isEmpty,
      );
    });

    test('reports an empty ID with the pinned code literal', () {
      expect(
        const PracticeEvent(
          id: '',
          position: BeatPosition(0),
          direction: StrumDirection.down,
        ).validate().map((failure) => failure.code),
        contains('event.id.empty'),
      );
    });

    test('rejects a zero duration with the pinned code literal', () {
      expect(
        const PracticeEvent(
          id: 'event',
          position: BeatPosition(0),
          duration: BeatPosition(0),
          direction: StrumDirection.down,
        ).validate().map((failure) => failure.code),
        contains('event.duration.nonPositive'),
      );
    });

    test('requires a scored attribute on a non-marker event', () {
      expect(
        const PracticeEvent(
          id: 'event',
          position: BeatPosition(0),
        ).validate().map((failure) => failure.code),
        contains('event.scorable.missing'),
      );
    });

    test('forbids scored attributes on marker events', () {
      expect(
        const PracticeEvent(
          id: 'marker',
          position: BeatPosition(0),
          marker: true,
          direction: StrumDirection.up,
        ).validate().map((failure) => failure.code),
        contains('event.marker.scorable'),
      );
    });

    test('aggregates independent event failures', () {
      final codes = const PracticeEvent(
        id: '',
        position: BeatPosition(0),
        duration: BeatPosition(0),
        chord: 'Bb',
        marker: true,
      ).validate().map((failure) => failure.code);

      expect(
        codes,
        containsAll({
          'event.id.empty',
          'event.chord.invalid',
          'event.duration.nonPositive',
          'event.marker.scorable',
        }),
      );
    });
  });

  group('PracticeEvent value semantics', () {
    test('supports structural equality, hashing, Set, and Map keys', () {
      final event = PracticeEvent(
        id: 'event',
        position: const BeatPosition(240),
        duration: const BeatPosition(120),
        chord: 'C#m',
        direction: StrumDirection.up,
        accent: true,
        optional: true,
      );
      final sameValue = PracticeEvent(
        id: 'event',
        position: const BeatPosition(240),
        duration: const BeatPosition(120),
        chord: 'C#m',
        direction: StrumDirection.up,
        accent: true,
        optional: true,
      );
      const different = PracticeEvent(
        id: 'event',
        position: BeatPosition(240),
        duration: BeatPosition(120),
        chord: 'C#m',
        direction: StrumDirection.up,
        accent: false,
        optional: true,
      );

      expect(identical(event, sameValue), isFalse);
      expect(event, sameValue);
      expect(event.hashCode, sameValue.hashCode);
      expect(event, isNot(different));
      final eventSet = <PracticeEvent>{event}..add(sameValue);
      expect(eventSet, hasLength(1));
      expect({event: 'value'}[sameValue], 'value');
    });
  });
}
