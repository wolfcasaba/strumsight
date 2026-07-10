import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/widgets/hit_burst.dart';

void main() {
  HitBurst burst({double start = 1.0, double strength = 1.0}) => HitBurst(
        startSec: start,
        color: Colors.orange,
        strength: strength,
      );

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
    double maxAlpha(double now) =>
        b.particlesAt(now).map((p) => p.alpha).fold(0.0, (a, x) => x > a ? x : a);

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

  test('painter repaints only when the clock, bursts or centre change', () {
    final list = [burst()];
    final a = HitBurstPainter(bursts: list, nowSec: 1.1, center: Offset.zero);
    expect(
        a.shouldRepaint(
            HitBurstPainter(bursts: list, nowSec: 1.1, center: Offset.zero)),
        isFalse);
    expect(
        a.shouldRepaint(
            HitBurstPainter(bursts: list, nowSec: 1.2, center: Offset.zero)),
        isTrue);
  });
}
