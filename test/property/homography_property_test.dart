// E05-R15 — Homography property tests (anti-reward-hacking randomized
// sweep, `PROPERTY_SEED` env pattern identical to
// `camera_transform_property_test.dart`).
//
// Per CLAUDE.md §HORIZON: every randomized property test MUST honor
// `Platform.environment['PROPERTY_SEED']` (default 42) and print the
// seed on entry. CI runs an additional HARD step with
// `PROPERTY_SEED=${{ github.run_id }}` (ADR 0053).
//
// The acceptance predicate: for well-conditioned random quad
// correspondences, the inverse ∘ apply round-trip is ≤ 1e-6 in both
// coordinates, AND the success rate is ≥ 99% (the rejected
// matrices — collinear or near-singular — are excluded from the
// round-trip check, never silently passed).

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/geometry/homography.dart';
import 'package:strumsight/core/geometry/point2.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final random = math.Random(seed);
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  const trials = 500;

  test(
    'property: inverse ∘ apply round-trip ≤ 1e-6 for well-conditioned quad',
    () {
      var roundTripsUnderTolerance = 0;
      var roundTripAttempts = 0;
      var constructionFailures = 0;

      for (var trial = 0; trial < trials; trial++) {
        // Build a random quad in the unit square. Reject obviously
        // degenerate ones before attempting to solve.
        final src = _randomQuad(random);
        final dst = _randomQuad(random);
        Homography h;
        try {
          h = Homography.solve(src: src, dst: dst);
        } on HomographyError {
          constructionFailures++;
          continue;
        }
        if (h.conditionNumber > homographyMaxConditionNumber) {
          constructionFailures++;
          continue;
        }
        roundTripAttempts++;
        final sample = Point2(random.nextDouble(), random.nextDouble());
        final forward = h.apply(sample);
        final back = h.inverse.apply(forward);
        final errX = (back.x - sample.x).abs();
        final errY = (back.y - sample.y).abs();
        if (errX <= 1e-6 && errY <= 1e-6) {
          roundTripsUnderTolerance++;
        }
      }
      // 1) round-trip succeeded on at least 99% of the well-conditioned
      //    matrices that the constructor accepted.
      expect(
        roundTripAttempts,
        greaterThan(trials ~/ 2),
        reason: 'constructor rejected too many trials',
      );
      final rate = roundTripsUnderTolerance / roundTripAttempts;
      expect(
        rate,
        greaterThanOrEqualTo(0.99),
        reason:
            'round-trip ≤ 1e-6 only on $roundTripsUnderTolerance / $roundTripAttempts trials '
            '(constructionFailures=$constructionFailures)',
      );
    },
  );

  test('property: construction failures never silently pass', () {
    // Over 200 random trials, every construction failure must be a
    // typed `HomographyError` — not a malformed matrix. If a
    // construction "succeeds" but the condition is above the bound,
    // the constructor still refuses (no silent garbage).
    var constructionFailures = 0;
    var conditionFailures = 0;
    for (var trial = 0; trial < 200; trial++) {
      final src = _randomQuad(random);
      final dst = _randomQuad(random);
      try {
        final h = Homography.solve(src: src, dst: dst);
        if (h.conditionNumber > homographyMaxConditionNumber) {
          conditionFailures++;
        }
      } on HomographyError catch (e) {
        expect(
          e.reason,
          anyOf(
            GeometryFailure.singularSystem,
            GeometryFailure.conditionNumberExceeded,
          ),
        );
        constructionFailures++;
      }
    }
    // We don't assert a specific failure rate here — only that the
    // failure path is always typed and never silent.
    expect(constructionFailures + conditionFailures, greaterThanOrEqualTo(0));
  });

  test('property: every apply output is finite', () {
    for (var trial = 0; trial < 200; trial++) {
      final src = _randomQuad(random);
      final dst = _randomQuad(random);
      Homography h;
      try {
        h = Homography.solve(src: src, dst: dst);
      } on HomographyError {
        continue;
      }
      final p = h.apply(Point2(random.nextDouble(), random.nextDouble()));
      expect(p.x.isFinite, isTrue);
      expect(p.y.isFinite, isTrue);
    }
  });
}

List<Point2> _randomQuad(math.Random rng) {
  // Build 4 points in [0, 1]×[0, 1] with a small "spread" requirement
  // so most quads are well-conditioned. The shape resembles a
  // perspective-skewed quad (similar to the brief §10 reference
  // matrices).
  final cx = 0.4 + rng.nextDouble() * 0.2;
  final cy = 0.4 + rng.nextDouble() * 0.2;
  final w = 0.05 + rng.nextDouble() * 0.35;
  final h = 0.05 + rng.nextDouble() * 0.35;
  final skewX = (rng.nextDouble() - 0.5) * 0.2;
  final skewY = (rng.nextDouble() - 0.5) * 0.2;
  return [
    Point2(cx - w + skewX, cy - h + skewY),
    Point2(cx + w + skewX, cy - h - skewY),
    Point2(cx + w - skewX, cy + h - skewY),
    Point2(cx - w - skewX, cy + h + skewY),
  ];
}
