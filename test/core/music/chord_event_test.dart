import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/core/music/chord_event.dart';
import 'package:strumsight/core/music/strum.dart';

/// E01-R10 — [ChordEvent] is the shared timeline element. `seq` is the stable
/// identity the Live view keys its cards by, so copyWith must never move it.
void main() {
  const base = ChordEvent(
    chord: Chord('Am'),
    confidence: 0.6,
    seq: 7,
    timeSec: 1.25,
  );

  test('copyWith updates only the strum-driven fields', () {
    final updated = base.copyWith(
      direction: StrumDirection.up,
      confidence: 0.9,
    );
    expect(updated.direction, StrumDirection.up);
    expect(updated.confidence, 0.9);
    // Identity is immutable: a card must not jump or re-enter mid-animation.
    expect(updated.chord, const Chord('Am'));
    expect(updated.seq, 7);
    expect(updated.timeSec, 1.25);
  });

  test('copyWith with no arguments keeps every field', () {
    expect(base.copyWith(), base);
  });

  test('a null direction argument does not clear an existing direction', () {
    final withDir = base.copyWith(direction: StrumDirection.down);
    expect(withDir.copyWith(confidence: 0.4).direction, StrumDirection.down);
  });

  test('equality covers every field', () {
    expect(base, base.copyWith());
    expect(base.hashCode, base.copyWith().hashCode);
    expect(base == base.copyWith(confidence: 0.61), isFalse);
    expect(base == base.copyWith(direction: StrumDirection.down), isFalse);
    expect(
      base ==
          const ChordEvent(
            chord: Chord('Am'),
            confidence: 0.6,
            seq: 8,
            timeSec: 1.25,
          ),
      isFalse,
    );
  });

  test('direction defaults to null until a strum lands', () {
    expect(base.direction, isNull);
  });

  test('toString carries the label, direction and seq', () {
    expect(base.toString(), contains('Am'));
    expect(base.toString(), contains('seq=7'));
  });
}
