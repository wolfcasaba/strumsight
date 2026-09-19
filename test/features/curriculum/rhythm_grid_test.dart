// The strumming grid: the pendulum, the ghosts, and the counterexample the
// model must NOT outlaw.
//
// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §3.
// Research: `docs/research/strumming-direction-pedagogy-2026-09.md`.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/curriculum/public.dart';

const _d = StrumDirection.down;
const _u = StrumDirection.up;

/// Eighth-note grid with every slot struck — the continuous pendulum.
RhythmGrid _allEighths() => RhythmGrid.pendulum(
  subdivision: RhythmSubdivision.eighth,
  struck: List<bool>.filled(8, true),
);

void main() {
  group('the pendulum decides direction', () {
    test('eighths: the beats are DOWN and the "&"s are UP', () {
      // "Downstrokes happen on the numbers, upstrokes on the ands" — uniform
      // across the sources checked.
      final grid = _allEighths();
      expect(
        [for (final slot in grid.slots) slot.direction],
        [_d, _u, _d, _u, _d, _u, _d, _u],
      );
    });

    test('quarters: every stroke is a DOWNstroke', () {
      // At quarter resolution the hand's return travel is not a slot, so there
      // is no up-slot to fill. This is the absolute beginner's first strum.
      final grid = RhythmGrid.pendulum(
        subdivision: RhythmSubdivision.quarter,
        struck: List<bool>.filled(4, true),
      );
      expect([for (final slot in grid.slots) slot.direction], [_d, _d, _d, _d]);
    });

    test('a ghosted slot still carries its direction', () {
      // The pendulum never stops: a hole in the pattern is a stroke the hand
      // travels through without touching the strings, not a missing stroke.
      final grid = RhythmGrid.pendulum(
        subdivision: RhythmSubdivision.eighth,
        struck: const [true, false, true, true, false, true, true, true],
      );
      expect(grid.slots[1].direction, _u, reason: 'the hand still goes up');
      expect(grid.slots[1].isStruck, isFalse);
      expect(grid.slots[4].direction, _d);
    });

    test('an author cannot ask for an upstroke on a beat by accident', () {
      // The whole point of deriving: `struck` says WHETHER, never WHICH WAY.
      for (final struck in [
        const [true, true, true, true, true, true, true, true],
        const [true, false, false, true, false, true, false, false],
      ]) {
        final grid = RhythmGrid.pendulum(
          subdivision: RhythmSubdivision.eighth,
          struck: struck,
        );
        for (final slot in grid.slots) {
          expect(
            slot.direction,
            slot.index.isEven ? _d : _u,
            reason: 'slot ${slot.index}',
          );
        }
      }
    });

    test('the D-DU-UDU pattern comes out as the shipped lesson has it', () {
      // `lesson.dart` ships this as [D, ., D, U, ., U, D, U]. The grid must
      // agree with the content the app already teaches.
      final grid = RhythmGrid.pendulum(
        subdivision: RhythmSubdivision.eighth,
        struck: const [true, false, true, true, false, true, true, true],
      );
      expect(
        [for (final slot in grid.slots) slot.isStruck ? slot.direction : null],
        [_d, null, _d, _u, null, _u, _d, _u],
      );
    });
  });

  group('the counterexample the model must not outlaw', () {
    test(
      'the taught D-U-U waltz is expressible, and reports as non-pendulum',
      () {
        // A bass note down on ONE and light chords UP on two and three — the
        // documented "oom-pah-pah" waltz, which this app already ships as the
        // `waltz-time` lesson and which teaching sources give as "down-up-up".
        // A model that could not express it would call real teaching wrong; a
        // model that called it a pendulum would be lying about why it is right.
        final waltz = RhythmGrid.authored(
          subdivision: RhythmSubdivision.quarter,
          beatsPerBar: 3,
          strokes: const [_d, _u, _u],
        );
        expect(waltz.followsPendulum, isFalse);
        expect([for (final slot in waltz.slots) slot.direction], [_d, _u, _u]);
      },
    );

    test('a pendulum grid always reports that it is one', () {
      expect(_allEighths().followsPendulum, isTrue);
      expect(
        RhythmGrid.pendulum(
          subdivision: RhythmSubdivision.quarter,
          struck: const [true, false, true, false],
        ).followsPendulum,
        isTrue,
      );
    });

    test('an authored grid that happens to agree reports as a pendulum', () {
      expect(
        RhythmGrid.authored(
          subdivision: RhythmSubdivision.eighth,
          strokes: const [_d, _u, _d, _u, _d, _u, _d, _u],
        ).followsPendulum,
        isTrue,
      );
    });

    test('an authored ghost still travels the pendulum way', () {
      // Notation chooses the struck directions; it does not get to choose which
      // way the hand moves when it is not playing.
      final grid = RhythmGrid.authored(
        subdivision: RhythmSubdivision.eighth,
        strokes: const [_d, null, _u, null, _d, null, _u, null],
      );
      expect(grid.slots[1].direction, _u);
      expect(grid.slots[3].direction, _u);
      expect(
        grid.slots[2].direction,
        _u,
        reason: 'authored, against the grain',
      );
      expect(grid.followsPendulum, isFalse);
    });
  });

  group('a malformed bar is refused, not silently reshaped', () {
    test('a short pattern would spill into the next bar', () {
      // The same failure `lesson.dart` guards with an assert, as a thrown error
      // so it holds in release builds too.
      expect(
        () => RhythmGrid.pendulum(
          subdivision: RhythmSubdivision.eighth,
          struck: const [true, true, true],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('3/4 needs six eighth slots, not eight', () {
      expect(
        () => RhythmGrid.pendulum(
          subdivision: RhythmSubdivision.eighth,
          beatsPerBar: 3,
          struck: List<bool>.filled(8, true),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        RhythmGrid.pendulum(
          subdivision: RhythmSubdivision.eighth,
          beatsPerBar: 3,
          struck: List<bool>.filled(6, true),
        ).slotCount,
        6,
      );
    });

    test('a grid with nothing to play is not an exercise', () {
      expect(
        () => RhythmGrid.pendulum(
          subdivision: RhythmSubdivision.eighth,
          struck: List<bool>.filled(8, false),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => RhythmGrid.authored(
          subdivision: RhythmSubdivision.eighth,
          strokes: List<StrumDirection?>.filled(8, null),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a ghosted slot cannot be accented — there is nothing to hear', () {
      expect(
        () => RhythmGrid.pendulum(
          subdivision: RhythmSubdivision.eighth,
          struck: const [true, false, true, true, true, true, true, true],
          accents: const {1},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an accent outside the bar is refused', () {
      expect(
        () => RhythmGrid.pendulum(
          subdivision: RhythmSubdivision.eighth,
          struck: List<bool>.filled(8, true),
          accents: const {8},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a bar with no beats is refused', () {
      expect(
        () => RhythmGrid.pendulum(
          subdivision: RhythmSubdivision.eighth,
          beatsPerBar: 0,
          struck: const [],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('timing', () {
    test('eighths at 120 bpm fall every 250 ms', () {
      final grid = _allEighths();
      expect(grid.onsetUs(bar: 0, slotIndex: 0, bpm: 120), 0);
      expect(grid.onsetUs(bar: 0, slotIndex: 1, bpm: 120), 250000);
      expect(grid.onsetUs(bar: 0, slotIndex: 7, bpm: 120), 1750000);
    });

    test('bar 1 starts one whole bar later', () {
      final grid = _allEighths();
      expect(grid.onsetUs(bar: 1, slotIndex: 0, bpm: 120), 2000000);
      expect(grid.onsetUs(bar: 3, slotIndex: 0, bpm: 120), 6000000);
    });

    test('rounding error does not accumulate down the bars', () {
      // At 126 bpm an eighth is 238095.238… µs. Computing from the absolute
      // slot number keeps the error at most half a microsecond; adding
      // slot-by-slot would drift ~8 µs over 32 slots and more over a long
      // exercise — small, but a drift that grows is the wrong shape of error
      // when the whole judgement is a 50 ms window.
      final grid = _allEighths();
      const exact = 60000000 / (126 * 2);
      for (final slot in [1, 7, 8, 31]) {
        final bar = slot ~/ 8;
        expect(
          grid.onsetUs(bar: bar, slotIndex: slot % 8, bpm: 126),
          (slot * exact).round(),
        );
      }
    });

    test('a 3/4 bar is three beats long, not four', () {
      final waltz = RhythmGrid.pendulum(
        subdivision: RhythmSubdivision.quarter,
        beatsPerBar: 3,
        struck: const [true, true, true],
      );
      expect(waltz.onsetUs(bar: 1, slotIndex: 0, bpm: 120), 1500000);
    });

    test('a nonsense tempo or position is refused', () {
      final grid = _allEighths();
      expect(
        () => grid.onsetUs(bar: 0, slotIndex: 0, bpm: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => grid.onsetUs(bar: 0, slotIndex: 0, bpm: double.nan),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => grid.onsetUs(bar: -1, slotIndex: 0, bpm: 120),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => grid.onsetUs(bar: 0, slotIndex: 8, bpm: 120),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('the grid as a value', () {
    test('only the struck slots are scoreable', () {
      final grid = RhythmGrid.pendulum(
        subdivision: RhythmSubdivision.eighth,
        struck: const [true, false, true, true, false, true, true, true],
      );
      expect(grid.slotCount, 8);
      expect(grid.struckSlots.length, 6);
      expect(grid.struckSlots.every((slot) => slot.isStruck), isTrue);
    });

    test('the muted flag reaches every slot — the right-hand-only rungs', () {
      final grid = RhythmGrid.pendulum(
        subdivision: RhythmSubdivision.quarter,
        struck: List<bool>.filled(4, true),
        muted: true,
      );
      expect(grid.slots.every((slot) => slot.muted), isTrue);
    });

    test('slots compare by value', () {
      expect(_allEighths().slots.first, _allEighths().slots.first);
      expect(
        _allEighths().slots.first.hashCode,
        _allEighths().slots.first.hashCode,
      );
      expect(_allEighths().slots[0], isNot(_allEighths().slots[1]));
    });

    test('the slot list cannot be mutated from outside', () {
      expect(
        () => _allEighths().slots.add(
          const RhythmSlot(index: 9, direction: _d, sound: StrokeSound.struck),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
