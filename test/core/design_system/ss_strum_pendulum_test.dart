// The strum pendulum: the motion profile, the clock discipline, and the rule
// that reduced motion removes travel but never information.
//
// The whole visual is a pure function of the clock position, so most of this
// file needs no widget tree at all.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

/// A clock the test positions by hand.
final class _FakeClock implements SsBeatClock {
  _FakeClock([this.position]);
  @override
  Duration? position;
}

const _beat = Duration(milliseconds: 500); // 120 bpm
const _eighths = [true, true, true, true, true, true, true, true];
const _downQuarters = [true, false, true, false, true, false, true, false];

SsStrumPendulumFrame _frame(int ms, {List<bool> struck = _eighths}) =>
    SsStrumPendulum.frameAt(
      position: Duration(milliseconds: ms),
      beatDuration: _beat,
      struck: struck,
    )!;

void main() {
  group('the motion profile', () {
    test('the pick is AT the strings when it crosses them', () {
      // The strike is the crossing, so travel must be zero exactly there.
      expect(SsStrumPendulum.travelAt(0), 0);
      expect(SsStrumPendulum.travelAt(1), closeTo(0, 1e-12));
    });

    test('the turnaround is at the far point, halfway between strokes', () {
      expect(SsStrumPendulum.travelAt(0.5), 1);
    });

    test('speed is maximal at the strings and zero at the turnaround', () {
      // Constant acceleration: the measured profile. Sampling the derivative
      // numerically keeps this a statement about the CURVE, not about one value.
      double speed(double u) {
        const h = 1e-6;
        return ((SsStrumPendulum.travelAt(u + h) -
                    SsStrumPendulum.travelAt(u - h)) /
                (2 * h))
            .abs();
      }

      expect(speed(0.5), lessThan(0.01), reason: 'stopped at the turnaround');
      expect(speed(0.02), greaterThan(3.5), reason: 'fast at the strings');
      expect(speed(0.98), greaterThan(3.5));
    });

    test('acceleration is UNIFORM — the profile the study measured best', () {
      // The sinusoidal control it beat would have a varying second derivative.
      double accel(double u) {
        const h = 1e-4;
        return (SsStrumPendulum.travelAt(u + h) -
                2 * SsStrumPendulum.travelAt(u) +
                SsStrumPendulum.travelAt(u - h)) /
            (h * h);
      }

      final samples = [0.2, 0.35, 0.5, 0.65, 0.8].map(accel).toList();
      for (final sample in samples) {
        expect(sample, closeTo(samples.first, 0.01));
      }
    });

    test('the approach is visible well before the strike, not a flash', () {
      // People anticipate rather than react, so there must be travel to aim at.
      // A quarter of the way into the half-cycle the pick is already moving.
      expect(SsStrumPendulum.travelAt(0.75).abs(), greaterThan(0.5));
    });
  });

  group('direction comes from the grid, never from the caller', () {
    test('even crossings go down, odd crossings go up', () {
      expect(_frame(0).direction, SsStrumDirection.down);
      expect(_frame(250).direction, SsStrumDirection.up);
      expect(_frame(500).direction, SsStrumDirection.down);
      expect(_frame(750).direction, SsStrumDirection.up);
    });

    test('the pick dips BELOW the strings after a downstroke', () {
      expect(_frame(125).travel, greaterThan(0));
      expect(
        _frame(375).travel,
        lessThan(0),
        reason: 'above, after an upstroke',
      );
    });

    test('two crossings per beat, because that is what a hand does', () {
      expect(SsStrumPendulum.crossingsPerBeat, 2);
      // 500 ms beat -> a crossing every 250 ms.
      expect(_frame(0).crossingIndex, 0);
      expect(_frame(249).crossingIndex, 0);
      expect(_frame(251).crossingIndex, 1);
    });
  });

  group('ghost strokes', () {
    test('a ghost crossing still moves the hand', () {
      // Down-quarters: the return is real travel that is simply not asked for.
      final ghost = _frame(375, struck: _downQuarters);
      expect(ghost.isStruck, isFalse);
      expect(
        ghost.travel.abs(),
        greaterThan(0.5),
        reason: 'the hand is moving',
      );
    });

    test('a ghost crossing never lights up', () {
      expect(_frame(250, struck: _downQuarters).strikeGlow, 0);
      expect(_frame(255, struck: _downQuarters).strikeGlow, 0);
    });

    test('the struck crossings of down-quarters are the beats', () {
      for (final ms in [0, 500, 1000, 1500]) {
        expect(
          _frame(ms, struck: _downQuarters).isStruck,
          isTrue,
          reason: '$ms',
        );
      }
      for (final ms in [250, 750, 1250, 1750]) {
        expect(
          _frame(ms, struck: _downQuarters).isStruck,
          isFalse,
          reason: '$ms',
        );
      }
    });
  });

  group('the strike glow', () {
    test('full at contact, decaying after it', () {
      expect(_frame(0).strikeGlow, 1);
      expect(_frame(80).strikeGlow, lessThan(1));
      expect(_frame(80).strikeGlow, greaterThan(0));
    });

    test('two strokes are never lit at once, at any tempo', () {
      // The bound, not the nominal 160 ms, is what guarantees this: the glow is
      // clipped to a fraction of the half-cycle.
      for (final bpm in [60, 90, 120, 200, 400]) {
        final beat = Duration(microseconds: (60000000 / bpm).round());
        final halfCycleMs = 60000 / bpm / 2;
        final justBeforeNext = SsStrumPendulum.frameAt(
          position: Duration(microseconds: ((halfCycleMs - 1) * 1000).round()),
          beatDuration: beat,
          struck: _eighths,
        )!;
        expect(
          justBeforeNext.strikeGlow,
          0,
          reason: 'at $bpm bpm the previous stroke is still lit',
        );
      }
    });
  });

  group('the strike SWEEPS across the strings', () {
    const halfCycle = Duration(milliseconds: 250);

    double glow(int string, int sinceMs, SsStrumDirection direction) =>
        SsStrumPendulum.stringGlowAt(
          stringIndex: string,
          sinceCrossing: Duration(milliseconds: sinceMs),
          direction: direction,
          halfCycle: halfCycle,
        );

    test('a downstroke reaches the THICKEST string first', () {
      // At the instant of the crossing only the top string is lit; the pick has
      // not arrived at the others yet. That is what makes direction readable
      // from a single frozen frame.
      expect(glow(0, 0, SsStrumDirection.down), 1.0);
      expect(glow(5, 0, SsStrumDirection.down), 0.0);
    });

    test('an upstroke reaches the THINNEST string first', () {
      expect(glow(5, 0, SsStrumDirection.up), 1.0);
      expect(glow(0, 0, SsStrumDirection.up), 0.0);
    });

    test('the sweep starts AT the beat and runs forward', () {
      // Measured, not assumed: the engine places a strum 0.0-3.4 ms from the
      // FIRST string of a six-string spread, so the beat is the sweep's
      // beginning rather than its centre.
      expect(glow(0, 0, SsStrumDirection.down), 1.0);
      for (var string = 1; string < SsStrumPendulum.stringCount; string++) {
        expect(
          glow(string, 0, SsStrumDirection.down),
          0.0,
          reason: 'string $string cannot be lit before the pick reaches it',
        );
      }
    });

    test('every string is reached, in order', () {
      var previousArrival = -1;
      for (var string = 0; string < SsStrumPendulum.stringCount; string++) {
        var arrival = -1;
        for (var ms = 0; ms <= 120; ms++) {
          if (glow(string, ms, SsStrumDirection.down) > 0) {
            arrival = ms;
            break;
          }
        }
        expect(arrival, isNonNegative, reason: 'string $string never lit');
        expect(arrival, greaterThanOrEqualTo(previousArrival));
        previousArrival = arrival;
      }
    });

    test('the whole sweep stays clear of the next stroke, at any tempo', () {
      for (final bpm in [60, 120, 240, 400]) {
        final cycle = Duration(microseconds: (60000000 / bpm / 2).round());
        final justBefore = Duration(microseconds: cycle.inMicroseconds - 1000);
        for (var string = 0; string < SsStrumPendulum.stringCount; string++) {
          expect(
            SsStrumPendulum.stringGlowAt(
              stringIndex: string,
              sinceCrossing: justBefore,
              direction: SsStrumDirection.down,
              halfCycle: cycle,
            ),
            0,
            reason:
                'at $bpm bpm string $string is still lit at the next stroke',
          );
        }
      }
    });

    test('an out-of-range string index is 0, not a crash', () {
      expect(glow(-1, 0, SsStrumDirection.down), 0);
      expect(glow(6, 0, SsStrumDirection.down), 0);
    });
  });

  group('clock discipline (ADR 0274)', () {
    test('no tempo means no live frame — not a guessed one', () {
      expect(
        SsStrumPendulum.frameAt(
          position: Duration.zero,
          beatDuration: Duration.zero,
          struck: _eighths,
        ),
        isNull,
      );
      expect(
        SsStrumPendulum.frameAt(
          position: Duration.zero,
          beatDuration: const Duration(milliseconds: -1),
          struck: _eighths,
        ),
        isNull,
      );
    });

    test('nothing to play means no live frame', () {
      expect(
        SsStrumPendulum.frameAt(
          position: Duration.zero,
          beatDuration: _beat,
          struck: const [],
        ),
        isNull,
      );
    });

    test('the phase is DERIVED from the position, so it loops exactly', () {
      // One bar of eighths at 120 bpm is 2 s. The same phase must come back
      // bit-identical rather than drifting, which is what derived-not-
      // accumulated buys.
      expect(_frame(2000), _frame(0));
      expect(_frame(2125), _frame(125));
      expect(_frame(10000), _frame(0));
    });

    test('a position before zero is handled, not crashed on', () {
      // A clock can report a negative position during a pre-roll count-in.
      final frame = SsStrumPendulum.frameAt(
        position: const Duration(milliseconds: -125),
        beatDuration: _beat,
        struck: _eighths,
      )!;
      expect(frame.crossingIndex, 7);
      expect(frame.travel.abs(), closeTo(1, 1e-9));
    });
  });

  group('in a widget tree', () {
    Widget host(_FakeClock clock, {bool reduceMotion = false, String? label}) =>
        MaterialApp(
          theme: SsDarkTheme.data(),
          home: SsMotionScope(
            appOverride: reduceMotion,
            child: Scaffold(
              body: SsStrumPendulum(
                clock: clock,
                beatDuration: _beat,
                struck: _eighths,
                semanticLabel: label,
              ),
            ),
          ),
        );

    testWidgets('renders, and picks the clock up on the next frame', (
      tester,
    ) async {
      final clock = _FakeClock();
      await tester.pumpWidget(host(clock));
      expect(find.byKey(SsStrumPendulum.pickKey), findsOneWidget);

      clock.position = const Duration(milliseconds: 125);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(SsStrumPendulum.pickKey), findsOneWidget);
    });

    testWidgets('a stopped clock leaves the strings drawn and nothing moving', (
      tester,
    ) async {
      final clock = _FakeClock(const Duration(milliseconds: 125));
      await tester.pumpWidget(host(clock));
      await tester.pump(const Duration(milliseconds: 16));
      clock.position = null;
      await tester.pump(const Duration(milliseconds: 16));
      // Still painted — the band is the resting state, not a blank box.
      expect(find.byKey(SsStrumPendulum.pickKey), findsOneWidget);
    });

    testWidgets('reduced motion keeps the widget and its information', (
      tester,
    ) async {
      final clock = _FakeClock(const Duration(milliseconds: 125));
      await tester.pumpWidget(host(clock, reduceMotion: true));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(SsStrumPendulum.pickKey), findsOneWidget);
    });

    testWidgets('decorative by default, announced only when asked', (
      tester,
    ) async {
      final clock = _FakeClock(Duration.zero);
      await tester.pumpWidget(host(clock));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.bySemanticsLabel('lefelé'), findsNothing);

      await tester.pumpWidget(host(clock, label: 'lefelé'));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.bySemanticsLabel('lefelé'), findsOneWidget);
    });

    testWidgets('disposes its ticker', (tester) async {
      final clock = _FakeClock(Duration.zero);
      await tester.pumpWidget(host(clock));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpWidget(const SizedBox.shrink());
      // A leaked ticker fails the test framework's own assertion on teardown.
      expect(find.byKey(SsStrumPendulum.pickKey), findsNothing);
    });
  });

  group('the frame as a value', () {
    test('equal frames compare equal, so repaints are skipped', () {
      expect(_frame(125), _frame(125));
      expect(_frame(125).hashCode, _frame(125).hashCode);
      expect(_frame(125), isNot(_frame(130)));
    });
  });

  _soundingGroup();
}

void _soundingGroup() {
  const halfCycle = Duration(milliseconds: 250);

  group('unplayed strings are crossed, not sounded', () {
    // Am is ×02210 and D is ××0232 in standard notation: the × strings are not
    // played, and the instruction that goes with the notation is to strum from
    // the lowest non-× string.
    const am = [false, true, true, true, true, true];
    const d = [false, false, true, true, true, true];

    test('a muted string never lights, at any point in the sweep', () {
      for (var ms = 0; ms <= 200; ms += 10) {
        expect(
          SsStrumPendulum.stringGlowAt(
            stringIndex: 0,
            sinceCrossing: Duration(milliseconds: ms),
            direction: SsStrumDirection.down,
            halfCycle: halfCycle,
            sounding: am,
          ),
          0,
          reason: 'the bass E of an Am must never ring, at +${ms}ms',
        );
      }
    });

    test('a DOWNstroke begins at the lowest SOUNDING string', () {
      // The cell this feature exists for. Without `sounding` the sweep started
      // at string 0 for every chord, animating the exact motion that makes an Am
      // muddy — shown to the learner as the thing to copy.
      final atCrossing = SsStrumPendulum.stringGlowAt(
        stringIndex: 1, // the A string: an Am's lowest sounding one
        sinceCrossing: Duration.zero,
        direction: SsStrumDirection.down,
        halfCycle: halfCycle,
        sounding: am,
      );
      expect(atCrossing, 1.0, reason: 'it is reached AT the crossing');
    });

    test('on a D the stroke begins at the D string, two in', () {
      expect(
        SsStrumPendulum.stringGlowAt(
          stringIndex: 2,
          sinceCrossing: Duration.zero,
          direction: SsStrumDirection.down,
          halfCycle: halfCycle,
          sounding: d,
        ),
        1.0,
      );
      // And the strings above it stay dark for the whole stroke.
      for (final index in [0, 1]) {
        expect(
          SsStrumPendulum.stringGlowAt(
            stringIndex: index,
            sinceCrossing: const Duration(milliseconds: 20),
            direction: SsStrumDirection.down,
            halfCycle: halfCycle,
            sounding: d,
          ),
          0,
        );
      }
    });

    test('an UPstroke begins at the thinnest sounding string', () {
      expect(
        SsStrumPendulum.stringGlowAt(
          stringIndex: 5,
          sinceCrossing: Duration.zero,
          direction: SsStrumDirection.up,
          halfCycle: halfCycle,
          sounding: d,
        ),
        1.0,
      );
    });

    test('the sounding strings are still swept IN ORDER, not together', () {
      // The sweep is what makes a strum legible as a strum rather than a stab,
      // so narrowing it to four strings must not collapse it to one instant.
      final reached = <int, int>{};
      for (final index in [2, 3, 4, 5]) {
        for (var ms = 0; ms <= 120; ms++) {
          final glow = SsStrumPendulum.stringGlowAt(
            stringIndex: index,
            sinceCrossing: Duration(milliseconds: ms),
            direction: SsStrumDirection.down,
            halfCycle: halfCycle,
            sounding: d,
          );
          if (glow > 0) {
            reached[index] = ms;
            break;
          }
        }
      }
      expect(reached.keys, hasLength(4));
      expect(
        reached[2]! <= reached[3]! &&
            reached[3]! <= reached[4]! &&
            reached[4]! <= reached[5]!,
        isTrue,
        reason: 'thickest sounding first on a downstroke: $reached',
      );
      expect(
        reached[5]! > reached[2]!,
        isTrue,
        reason: 'the sweep still takes time across the four strings',
      );
    });

    test('omitting it is the same as all six sounding', () {
      for (var i = 0; i < SsStrumPendulum.stringCount; i++) {
        expect(
          SsStrumPendulum.stringGlowAt(
            stringIndex: i,
            sinceCrossing: const Duration(milliseconds: 30),
            direction: SsStrumDirection.down,
            halfCycle: halfCycle,
            sounding: const [true, true, true, true, true, true],
          ),
          SsStrumPendulum.stringGlowAt(
            stringIndex: i,
            sinceCrossing: const Duration(milliseconds: 30),
            direction: SsStrumDirection.down,
            halfCycle: halfCycle,
          ),
        );
      }
    });

    test('a single sounding string lights at the crossing', () {
      // Degenerate but reachable: the sweep has nowhere to travel, and dividing
      // by (count - 1) would be a division by zero.
      expect(
        SsStrumPendulum.stringGlowAt(
          stringIndex: 3,
          sinceCrossing: Duration.zero,
          direction: SsStrumDirection.down,
          halfCycle: halfCycle,
          sounding: const [false, false, false, true, false, false],
        ),
        1.0,
      );
    });
  });
}
