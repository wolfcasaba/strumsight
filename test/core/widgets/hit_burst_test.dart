import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/widgets/hit_burst.dart';

void main() {
  HitBurst burst({double start = 1.0, double strength = 1.0}) =>
      HitBurst(startSec: start, color: Colors.orange, strength: strength);

  test('emits its full particle count while active', () {
    final b = burst();
    expect(b.particlesAt(1.0).length, b.count); // t=0
    expect(b.particlesAt(1.2).length, b.count); // mid-life
  });

  test('is empty before it starts and after it ends', () {
    final b = burst(start: 1.0); // lifeSec 0.45 → ends ~1.45
    expect(b.particlesAt(0.9), isEmpty); // before
    expect(b.particlesAt(1.5), isEmpty); // past the end
    expect(b.particlesAt(2.0), isEmpty); // well after
  });

  test('isDone flips at the end of life (and agrees with particlesAt)', () {
    final b = burst(start: 1.0);
    expect(b.isDone(1.2), isFalse);
    expect(b.particlesAt(1.2), isNotEmpty);
    expect(b.isDone(1.5), isTrue);
    expect(b.particlesAt(1.5), isEmpty);
  });

  test('a burst whose start is in the future is inert but NOT done', () {
    // The invariant behind LearnScreen._restart() clearing _bursts: after a
    // replay resets the clock to 0, a leftover burst (startSec far ahead) draws
    // nothing (dt<0 → empty) yet isDone stays false, so it is never pruned and
    // would re-fire a phantom spark once the clock climbs back to its start.
    final b = burst(start: 30.0);
    expect(b.particlesAt(0.0), isEmpty);
    expect(b.isDone(0.0), isFalse); // → the screen must clear it explicitly
  });

  test('particles spread outward and fade over time', () {
    final b = burst();
    double maxDist(double now) => b
        .particlesAt(now)
        .map((p) => p.offset.distance)
        .fold(0.0, (a, d) => d > a ? d : a);
    double maxAlpha(double now) => b
        .particlesAt(now)
        .map((p) => p.alpha)
        .fold(0.0, (a, x) => x > a ? x : a);

    expect(maxDist(1.0), lessThan(1.0)); // t=0: all at the centre
    expect(maxDist(1.2), greaterThan(maxDist(1.0))); // spread out
    expect(maxAlpha(1.4), lessThan(maxAlpha(1.05))); // fading
  });

  test('a stronger (PERFECT) burst reaches farther than a weak one', () {
    double reach(double s) => burst(strength: s)
        .particlesAt(1.2)
        .map((p) => p.offset.distance)
        .fold(0.0, (a, d) => d > a ? d : a);
    expect(reach(1.0), greaterThan(reach(0.4)));
  });

  test('directionSign flips the cone: up by default, down for +1', () {
    double meanDy(double sign) {
      final ps = HitBurst(
        startSec: 1.0,
        color: Colors.orange,
        strength: 1.0,
        directionSign: sign,
      ).particlesAt(1.1);
      return ps.map((p) => p.offset.dy).fold(0.0, (a, b) => a + b) / ps.length;
    }

    expect(meanDy(-1), lessThan(0)); // sparks rise (screen y grows downward)
    expect(meanDy(1), greaterThan(0)); // sparks fall with a down-stroke
  });

  test('the pick sweep travels through the centre in the stroke direction', () {
    HitBurst make(double sign) => HitBurst(
      startSec: 1.0,
      color: Colors.orange,
      strength: 1.0,
      directionSign: sign,
    );
    final down = make(1);
    final up = make(-1);
    // Invisible before the start and once its (short) life is over. (A hair
    // past the end, not exactly on it: 1.0 + 0.22 rounds BELOW 1.22 in
    // binary floating point, so the exact boundary is not a clean cell.)
    expect(down.sweepAt(0.9), isNull);
    expect(down.sweepAt(1.0 + HitBurstSweep.lifeSec + 1e-6), isNull);
    // A down-stroke starts ABOVE the centre and ends BELOW it (screen y grows
    // downward); an up-stroke mirrors it exactly.
    final d0 = down.sweepAt(1.0)!;
    final d1 = down.sweepAt(1.0 + HitBurstSweep.lifeSec * 0.95)!;
    expect(d0.dy, lessThan(0));
    expect(d1.dy, greaterThan(0));
    expect(d1.dy, greaterThan(d0.dy)); // monotone travel
    final u0 = up.sweepAt(1.0)!;
    final u1 = up.sweepAt(1.0 + HitBurstSweep.lifeSec * 0.95)!;
    expect(u0.dy, -d0.dy);
    expect(u1.dy, -d1.dy);
    // It fades as it travels, and progress runs 0 → 1.
    expect(d1.alpha, lessThan(d0.alpha));
    expect(d0.progress, 0);
    expect(d1.progress, closeTo(0.95, 1e-9));
  });

  test('painter repaints only when the clock, bursts or centre change', () {
    final list = [burst()];
    final a = HitBurstPainter(bursts: list, nowSec: 1.1, center: Offset.zero);
    expect(
      a.shouldRepaint(
        HitBurstPainter(bursts: list, nowSec: 1.1, center: Offset.zero),
      ),
      isFalse,
    );
    expect(
      a.shouldRepaint(
        HitBurstPainter(bursts: list, nowSec: 1.2, center: Offset.zero),
      ),
      isTrue,
    );
  });
  test('the impact ring expands, fades and ends on its own clock', () {
    const ring = ImpactRing(startSec: 1.0, strength: 1.0);
    expect(ring.ringAt(0.9), isNull);
    final early = ring.ringAt(1.0)!;
    final mid = ring.ringAt(1.14)!;
    final late = ring.ringAt(1.27)!;
    expect(mid.radius, greaterThan(early.radius));
    expect(late.radius, greaterThan(mid.radius));
    expect(mid.alpha, lessThan(early.alpha));
    expect(late.alpha, lessThan(mid.alpha));
    expect(ring.isDone(1.28), isTrue);
    expect(ring.ringAt(1.28), isNull);
    // Strength scales the reach.
    const weak = ImpactRing(startSec: 1.0, strength: 0.35);
    expect(weak.ringAt(1.27)!.radius, lessThan(late.radius));
  });
}
