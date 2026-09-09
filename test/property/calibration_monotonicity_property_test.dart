// HORIZON randomized property gate for the E14-R21/R32 calibration and
// selective-prediction mechanism (ADR 0536/0540).
//
// Reads PROPERTY_SEED (absent -> 42, the deterministic dev loop); CI runs an
// extra HARD pass with the run id as the seed. Every assertion here is an
// exact invariant, not a tuned threshold, so the cells cannot flake:
//
//   * a calibrated confidence is always inside 0..1;
//   * the mapping is MONOTONE: a higher raw score never maps to a lower
//     calibrated confidence (this is what makes a threshold on the
//     calibrated value meaningful at all);
//   * the mapping is deterministic and clamps outside the knot range;
//   * risk–coverage coverage is non-increasing in the threshold;
//   * the selected policy always keeps its accuracy promise, or is null;
//   * degrading every confidence never RAISES coverage — the abstention
//     goes up, not the confidence.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/evaluation/confidence_calibration_profile.dart';
import 'package:strumsight/features/live/domain/evaluation/selective_prediction.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final random = math.Random(seed);

  test('randomized piecewise-linear mappings stay inside 0..1, monotone, '
      'deterministic and clamped (seed $seed)', () {
    for (var trial = 0; trial < 200; trial++) {
      final mapping = _randomMapping(random);

      var previousOut = -1.0;
      var previousIn = -1.0;
      for (var step = 0; step <= 40; step++) {
        final raw = step / 40;
        final out = mapping.apply(raw);

        expect(out, inInclusiveRange(0, 1), reason: 'raw=$raw trial=$trial');
        expect(
          mapping.apply(raw),
          out,
          reason: 'the mapping must be deterministic',
        );
        if (raw > previousIn) {
          expect(
            out,
            greaterThanOrEqualTo(previousOut),
            reason: 'monotonicity broken at raw=$raw (trial $trial)',
          );
        }
        previousIn = raw;
        previousOut = out;
      }

      // Clamped, never extrapolated.
      expect(mapping.apply(-1), mapping.apply(0));
      expect(mapping.apply(2), mapping.apply(1));
    }
  });

  test('randomized risk–coverage curves are non-increasing in the '
      'threshold, and every point is internally consistent (seed $seed)', () {
    for (var trial = 0; trial < 100; trial++) {
      final observations = _randomObservations(random);

      final curve = riskCoverageCurve(observations);

      expect(curve, isNotEmpty);
      for (var i = 1; i < curve.length; i++) {
        expect(
          curve[i].acceptedCount,
          lessThanOrEqualTo(curve[i - 1].acceptedCount),
          reason: 'coverage rose with the threshold (trial $trial)',
        );
      }
      for (final point in curve) {
        expect(
          point.correctAcceptedCount,
          lessThanOrEqualTo(point.acceptedCount),
        );
        expect(point.acceptedCount, lessThanOrEqualTo(point.totalCount));
        final accuracy = point.acceptedAccuracy;
        if (accuracy != null) {
          expect(accuracy, inInclusiveRange(0, 1));
          expect(point.risk, closeTo(1 - accuracy, 1e-12));
        } else {
          expect(point.acceptedCount, 0);
        }
      }
    }
  });

  test('the coverage-maximising selector never breaks its accuracy promise '
      '(seed $seed)', () {
    for (var trial = 0; trial < 100; trial++) {
      final observations = _randomObservations(random);
      const target = 0.9;

      final policy = selectCoverageMaximisingPolicy(
        observations,
        targetAcceptedAccuracy: target,
      );

      if (policy == null) continue;
      final report = SelectiveCoverageReport.of(
        observations.where((o) => o.calibratedConfidence != null).toList(),
        policy: policy,
      );
      final accuracy = report.point.acceptedAccuracy;
      expect(accuracy, isNotNull, reason: 'trial $trial');
      expect(
        accuracy,
        greaterThanOrEqualTo(target - 1e-12),
        reason: 'the selected policy must keep the promise (trial $trial)',
      );
    }
  });

  test('degrading every calibrated confidence never raises coverage — the '
      'abstention rises instead (seed $seed)', () {
    final policy = SelectivePredictionPolicy.abstainBelow(0.7);
    for (var trial = 0; trial < 100; trial++) {
      final healthy = _randomObservations(random);
      final degraded = <SelectiveObservation>[
        for (final observation in healthy)
          SelectiveObservation(
            calibratedConfidence: observation.calibratedConfidence == null
                ? null
                : observation.calibratedConfidence! * 0.5,
            correct: observation.correct,
          ),
      ];

      final healthyReport = SelectiveCoverageReport.of(
        healthy,
        policy: policy,
      );
      final degradedReport = SelectiveCoverageReport.of(
        degraded,
        policy: policy,
      );

      expect(
        degradedReport.point.acceptedCount,
        lessThanOrEqualTo(healthyReport.point.acceptedCount),
        reason: 'trial $trial',
      );
    }
  });
}

CalibrationMapping _randomMapping(math.Random random) {
  final knotCount = 2 + random.nextInt(6);
  final xs = <double>{};
  while (xs.length < knotCount) {
    xs.add((random.nextDouble() * 1000).roundToDouble() / 1000);
  }
  final sortedXs = xs.toList()..sort();
  var y = random.nextDouble() * 0.4;
  final knots = <CalibrationKnot>[];
  for (final x in sortedXs) {
    knots.add(CalibrationKnot(raw: x, calibrated: y));
    // Non-decreasing by construction, bounded at 1.
    y = math.min(1.0, y + random.nextDouble() * 0.3);
  }
  return CalibrationMapping.piecewiseLinear(knots);
}

List<SelectiveObservation> _randomObservations(math.Random random) {
  final count = 1 + random.nextInt(40);
  return <SelectiveObservation>[
    for (var i = 0; i < count; i++)
      SelectiveObservation(
        // One in eight observations has no calibrated confidence — the
        // shipped state must survive the curve too.
        calibratedConfidence: random.nextInt(8) == 0
            ? null
            : random.nextDouble(),
        correct: random.nextDouble() < 0.8,
      ),
  ];
}
