import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';

/// E01-R10 — [Strum] and [StrumDirection] are the canonical shared domain
/// (they moved out of `features/live/model/`). Songs, setlists, saved analyze
/// sessions, lessons and diagnostics all persist or compare them, so the value
/// identity AND the wire names are contracts, not implementation details.
void main() {
  group('Strum — value identity', () {
    test('same fields ⇒ equal and same hash', () {
      const a = Strum(direction: StrumDirection.down, confidence: 0.8);
      const b = Strum(direction: StrumDirection.down, confidence: 0.8);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('every field participates in equality', () {
      const base = Strum(direction: StrumDirection.down, confidence: 0.8);
      expect(
        base == const Strum(direction: StrumDirection.up, confidence: 0.8),
        isFalse,
      );
      expect(
        base == const Strum(direction: StrumDirection.down, confidence: 0.7),
        isFalse,
      );
      expect(
        base ==
            const Strum(
              direction: StrumDirection.down,
              confidence: 0.8,
              accent: true,
            ),
        isFalse,
      );
      expect(
        base ==
            const Strum(
              direction: StrumDirection.down,
              confidence: 0.8,
              muted: true,
            ),
        isFalse,
      );
    });

    test('accent and muted default to false', () {
      const s = Strum(direction: StrumDirection.up, confidence: 0.5);
      expect(s.accent, isFalse);
      expect(s.muted, isFalse);
    });

    test('isDown / isUp mirror the direction', () {
      const down = Strum(direction: StrumDirection.down, confidence: 1);
      const up = Strum(direction: StrumDirection.up, confidence: 1);
      expect(down.isDown, isTrue);
      expect(down.isUp, isFalse);
      expect(up.isUp, isTrue);
      expect(up.isDown, isFalse);
    });

    test('confidence outside 0..1 trips the assert', () {
      expect(
        () => Strum(direction: StrumDirection.down, confidence: 1.5),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => Strum(direction: StrumDirection.down, confidence: -0.1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('StrumDirection — persisted wire names', () {
    // AnalyzeResult writes `direction.name` and reads it back with
    // requireEnumByName; songs and diagnostics do the same. Renaming or
    // reordering a value would silently break every stored document, so the
    // names and their order are pinned here.
    test('the enum serializes as "down" / "up", in that order', () {
      expect(StrumDirection.values.map((d) => d.name).toList(), ['down', 'up']);
    });

    test('name → value round-trips', () {
      for (final d in StrumDirection.values) {
        expect(StrumDirection.values.byName(d.name), d);
      }
    });
  });
}
