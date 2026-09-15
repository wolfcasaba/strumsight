import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

/// Geometry contract of the strummed six-string band: the pick reaches the
/// strings in order, an unresolved direction excites all six at once, a LATE
/// verdict moves the pick without restarting the ring-out, and everything is
/// gone by the end of the ring window.
void main() {
  const count = SsStrumStringsModel.stringCount;

  SsStrumStroke stroke({
    double start = 1.0,
    bool? isDown,
    double strength = 1.0,
  }) => SsStrumStroke(startSec: start, strength: strength, isDown: isDown);

  List<double> displacements(SsStrumStroke s, double nowSec) => [
    for (var i = 0; i < count; i++)
      SsStrumStringsModel.displacementAt(s, i, nowSec),
  ];

  test('the constants match the specified band', () {
    expect(count, 6);
    expect(SsStrumStringsModel.sweepSec, 0.06);
    expect(SsStrumStringsModel.ringSec, 0.6);
    // 60 ms across six strings → ~12 ms per string.
    expect(SsStrumStringsModel.stringStepSec, closeTo(0.012, 1e-12));
    // Higher strings flutter faster; the low E swings farther.
    expect(SsStrumStringsModel.frequencyHz(0), 9);
    expect(SsStrumStringsModel.frequencyHz(count - 1), 14);
    expect(
      SsStrumStringsModel.gaugeScale(0),
      greaterThan(SsStrumStringsModel.gaugeScale(count - 1)),
    );
    // No string can swing into its neighbour's lane.
    expect(SsStrumStringsModel.maxAmplitude, lessThan(0.5));
  });

  group('excitation order follows the pick', () {
    test('a down-stroke starts on the low E (string 0)', () {
      final s = stroke(isDown: true);

      for (var i = 0; i < count; i++) {
        expect(
          SsStrumStringsModel.excitationSec(s, i),
          closeTo(1.0 + i * SsStrumStringsModel.stringStepSec, 1e-12),
        );
      }

      // Half a step in, only the low E has been touched.
      final now = 1.0 + SsStrumStringsModel.stringStepSec / 2;
      expect(SsStrumStringsModel.displacementAt(s, 0, now), greaterThan(0));
      for (var i = 1; i < count; i++) {
        expect(SsStrumStringsModel.displacementAt(s, i, now), 0);
      }
    });

    test('an up-stroke mirrors it: the high E (string 5) first', () {
      final s = stroke(isDown: false);

      for (var i = 0; i < count; i++) {
        expect(
          SsStrumStringsModel.excitationSec(s, i),
          closeTo(
            1.0 + (count - 1 - i) * SsStrumStringsModel.stringStepSec,
            1e-12,
          ),
        );
      }

      final now = 1.0 + SsStrumStringsModel.stringStepSec / 2;
      expect(
        SsStrumStringsModel.displacementAt(s, count - 1, now),
        greaterThan(0),
      );
      for (var i = 0; i < count - 1; i++) {
        expect(SsStrumStringsModel.displacementAt(s, i, now), 0);
      }
    });

    test('an unknown direction excites every string simultaneously', () {
      final s = stroke();

      for (var i = 0; i < count; i++) {
        expect(SsStrumStringsModel.excitationSec(s, i), 1.0);
      }
      // All six are already moving where a down-stroke would still be silent.
      final now = 1.0 + SsStrumStringsModel.stringStepSec / 2;
      for (final d in displacements(s, now)) {
        expect(d, greaterThan(0));
      }
      // ...and no pick is drawn, because no direction has been claimed.
      expect(SsStrumStringsModel.pickPositionAt(s, now), isNull);
    });
  });

  group('a late verdict moves the pick, not the physics', () {
    test('the sweep is drawn from the resolve instant', () {
      final s = stroke(start: 1.0);
      const resolvedAt = 1.04;

      final ringingBefore = displacements(s, 1.05);
      s.resolveDirection(true, resolvedAt);
      expect(s.isDown, isTrue);
      expect(s.directionResolvedSec, resolvedAt);

      // The ring-out did NOT restart: same strings, same phase, still from the
      // onset.
      expect(displacements(s, 1.05), ringingBefore);
      for (var i = 0; i < count; i++) {
        expect(SsStrumStringsModel.excitationSec(s, i), 1.0);
      }

      // The pick, however, runs its full sweep from the verdict.
      expect(SsStrumStringsModel.pickPositionAt(s, 1.039), isNull);
      expect(
        SsStrumStringsModel.pickPositionAt(s, resolvedAt),
        closeTo(-SsStrumStringsModel.pickOvershoot, 1e-12),
      );
      expect(
        SsStrumStringsModel.pickPositionAt(
          s,
          resolvedAt + SsStrumStringsModel.sweepSec / 2,
        ),
        closeTo((count - 1) / 2, 1e-9),
      );
      expect(
        SsStrumStringsModel.pickPositionAt(
          s,
          resolvedAt + SsStrumStringsModel.sweepSec,
        ),
        isNull,
      );
    });

    test('the first verdict wins — a repeat never restarts the sweep', () {
      final s = stroke(start: 1.0)..resolveDirection(true, 1.04);
      s.resolveDirection(false, 1.20);

      expect(s.isDown, isTrue);
      expect(s.directionResolvedSec, 1.04);
    });

    test('a verdict cannot be drawn before its own onset', () {
      final s = stroke(start: 1.0)..resolveDirection(true, 0.97);

      expect(s.directionResolvedSec, 1.0);
      expect(SsStrumStringsModel.pickPositionAt(s, 1.0), isNotNull);
    });

    test('a direction known at the onset sweeps from the onset', () {
      final s = stroke(start: 1.0, isDown: true);

      expect(s.directionResolvedSec, isNull);
      expect(SsStrumStringsModel.pickPositionAt(s, 1.0), isNotNull);
      // A stroke that already knows its direction is not overwritten.
      s.resolveDirection(false, 1.03);
      expect(s.isDown, isTrue);
      expect(s.directionResolvedSec, isNull);
    });
  });

  group('pick travel', () {
    test('an up-stroke is the exact mirror of a down-stroke', () {
      final down = stroke(isDown: true);
      final up = stroke(isDown: false);

      for (final fraction in const [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 0.999]) {
        final now = 1.0 + fraction * SsStrumStringsModel.sweepSec;
        final d = SsStrumStringsModel.pickPositionAt(down, now)!;
        final u = SsStrumStringsModel.pickPositionAt(up, now)!;
        // Reflection about the middle of the band.
        expect(d + u, closeTo(count - 1, 1e-9));
      }
    });

    test('it crosses the whole band, overshooting both ends', () {
      final down = stroke(isDown: true);
      const overshoot = SsStrumStringsModel.pickOvershoot;

      expect(
        SsStrumStringsModel.pickPositionAt(down, 1.0),
        closeTo(-overshoot, 1e-12),
      );
      expect(
        SsStrumStringsModel.pickPositionAt(
          down,
          1.0 + SsStrumStringsModel.sweepSec * 0.999,
        )!,
        greaterThan(count - 1),
      );

      var previous = double.negativeInfinity;
      for (var step = 0; step <= 20; step++) {
        final now = 1.0 + SsStrumStringsModel.sweepSec * step / 21;
        final position = SsStrumStringsModel.pickPositionAt(down, now)!;
        expect(position, greaterThan(previous));
        expect(position, inInclusiveRange(-overshoot, count - 1 + overshoot));
        previous = position;
      }
    });

    test('there is no pick outside the sweep window', () {
      final down = stroke(isDown: true);

      expect(SsStrumStringsModel.pickPositionAt(down, 0.99), isNull);
      expect(
        SsStrumStringsModel.pickPositionAt(
          down,
          1.0 + SsStrumStringsModel.sweepSec,
        ),
        isNull,
      );
    });
  });

  group('ring-out', () {
    test('every string decays below 2 % of its peak by ringSec', () {
      final s = stroke(start: 0, isDown: true);

      for (var i = 0; i < count; i++) {
        final excitation = SsStrumStringsModel.excitationSec(s, i);
        final peak = SsStrumStringsModel.peakAmplitude(s, i);
        expect(peak, greaterThan(0));

        // It really swings first — a quarter period after the pick.
        final quarterPeriod = 0.25 / SsStrumStringsModel.frequencyHz(i);
        expect(
          SsStrumStringsModel.displacementAt(s, i, excitation + quarterPeriod),
          greaterThan(0.5 * peak),
        );

        // ...and is visually gone by the end of the window.
        final late = SsStrumStringsModel.displacementAt(
          s,
          i,
          excitation + SsStrumStringsModel.ringSec * 0.999,
        );
        expect(late.abs(), lessThan(0.02 * peak));

        // Cut off, so a stale stroke draws nothing at all.
        expect(
          SsStrumStringsModel.displacementAt(
            s,
            i,
            excitation + SsStrumStringsModel.ringSec * 1.001,
          ),
          0,
        );
      }
    });

    test('the window closes exactly at ringSec', () {
      // Excitation sits on 0 for an unresolved stroke, so the boundary is
      // reached exactly — no float slack hiding the edge.
      final s = stroke(start: 0);

      expect(
        SsStrumStringsModel.displacementAt(
          s,
          0,
          SsStrumStringsModel.ringSec * 0.999,
        ).abs(),
        greaterThan(0),
      );
      expect(
        SsStrumStringsModel.displacementAt(s, 0, SsStrumStringsModel.ringSec),
        0,
      );
    });

    test('a harder strum and a fatter string swing farther', () {
      final hard = stroke(isDown: true);
      final soft = stroke(isDown: true, strength: 0.4);

      expect(
        SsStrumStringsModel.peakAmplitude(hard, 0),
        greaterThan(SsStrumStringsModel.peakAmplitude(soft, 0)),
      );
      expect(
        SsStrumStringsModel.peakAmplitude(hard, 0),
        greaterThan(SsStrumStringsModel.peakAmplitude(hard, count - 1)),
      );
      // Out-of-range strength is clamped, never amplified.
      expect(
        SsStrumStringsModel.peakAmplitude(stroke(strength: 4), 0),
        SsStrumStringsModel.peakAmplitude(hard, 0),
      );
      expect(SsStrumStringsModel.peakAmplitude(stroke(strength: -1), 0), 0);
    });

    test('nothing is drawn before the onset', () {
      final s = stroke(start: 1.0, isDown: true);

      for (final d in displacements(s, 0.99)) {
        expect(d, 0);
      }
    });
  });

  group('isDone', () {
    test('waits for the last string of a swept stroke', () {
      // Down-stroke: the high E is excited a full sweep after the onset, so the
      // stroke lives sweepSec longer than the ring window.
      final s = stroke(start: 1.0, isDown: true);

      expect(SsStrumStringsModel.isDone(s, 1.59), isFalse);
      expect(SsStrumStringsModel.isDone(s, 1.65), isFalse);
      expect(SsStrumStringsModel.isDone(s, 1.67), isTrue);
    });

    test('an unresolved stroke ends one ring window after the onset', () {
      final s = stroke(start: 1.0);

      expect(SsStrumStringsModel.isDone(s, 1.59), isFalse);
      expect(SsStrumStringsModel.isDone(s, 1.61), isTrue);
    });

    test('a very late verdict keeps the stroke alive for its pick', () {
      final s = stroke(start: 1.0)..resolveDirection(true, 1.58);

      // The ring-out alone would have ended at 1.60.
      expect(SsStrumStringsModel.isDone(s, 1.61), isFalse);
      expect(SsStrumStringsModel.isDone(s, 1.65), isTrue);
    });

    test('agrees with the geometry it prunes', () {
      final s = stroke(start: 1.0, isDown: true);
      const done = 1.67;

      expect(SsStrumStringsModel.isDone(s, done), isTrue);
      for (final d in displacements(s, done)) {
        expect(d, 0);
      }
      expect(SsStrumStringsModel.pickPositionAt(s, done), isNull);
    });

    test('a stroke starting in the future is inert but NOT done', () {
      // Same invariant as HitBurst: a rewound clock must be handled by the
      // caller clearing its list, never by pruning.
      final s = stroke(start: 30, isDown: true);

      expect(SsStrumStringsModel.isDone(s, 0), isFalse);
      for (final d in displacements(s, 0)) {
        expect(d, 0);
      }
      expect(SsStrumStringsModel.pickPositionAt(s, 0), isNull);
    });
  });
}
