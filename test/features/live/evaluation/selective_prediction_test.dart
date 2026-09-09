// E14-R21 (ADR 0536): selective prediction — abstain instead of guessing.
//
// What these cells prove:
//   * the SHIPPED default (acceptAll) changes nothing: no calibration, no
//     new suppression;
//   * any real policy treats a missing calibrated confidence as ABSTAIN,
//     never as "use the raw score";
//   * the risk–coverage curve is deterministic and its coverage is
//     non-increasing in the threshold;
//   * the coverage-maximising selector returns `null` when no threshold can
//     keep the accuracy promise — it never returns "the least bad" one.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/evaluation/selective_prediction.dart';

void main() {
  group('policy application', () {
    test('the shipped default accepts everything, including an '
        'uncalibrated prediction', () {
      const policy = SelectivePredictionPolicy.acceptAll();

      expect(
        applySelectivePolicy(calibratedConfidence: null, policy: policy),
        const SelectiveOutcome.accept(),
      );
      expect(
        applySelectivePolicy(calibratedConfidence: 0.01, policy: policy),
        const SelectiveOutcome.accept(),
      );
    });

    test('a threshold policy ABSTAINS on a missing calibrated confidence, '
        'with that exact reason — it never falls back to the raw score', () {
      final policy = SelectivePredictionPolicy.abstainBelow(0.8);

      final outcome = applySelectivePolicy(
        calibratedConfidence: null,
        policy: policy,
      );

      expect(outcome.decision, SelectiveDecision.abstain);
      expect(
        outcome.abstainReason,
        SelectiveAbstainReason.noCalibratedConfidence,
      );
    });

    test('the boundary belongs to the accepting side', () {
      final policy = SelectivePredictionPolicy.abstainBelow(0.8);

      expect(
        applySelectivePolicy(
          calibratedConfidence: 0.799,
          policy: policy,
        ).isAccepted,
        isFalse,
      );
      expect(
        applySelectivePolicy(
          calibratedConfidence: 0.8,
          policy: policy,
        ).isAccepted,
        isTrue,
      );
    });

    test('a threshold outside 0..1 is rejected', () {
      expect(
        () => SelectivePredictionPolicy.abstainBelow(1.2),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => SelectivePredictionPolicy.abstainBelow(double.nan),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('risk–coverage curve', () {
    const observations = <SelectiveObservation>[
      SelectiveObservation(calibratedConfidence: 0.95, correct: true),
      SelectiveObservation(calibratedConfidence: 0.85, correct: true),
      SelectiveObservation(calibratedConfidence: 0.75, correct: false),
      SelectiveObservation(calibratedConfidence: 0.65, correct: true),
    ];

    test('coverage is non-increasing as the threshold rises, and both '
        'runs over the same input agree exactly', () {
      final first = riskCoverageCurve(observations);
      final second = riskCoverageCurve(observations);

      expect(first.length, second.length);
      for (var i = 0; i < first.length; i++) {
        expect(first[i].threshold, second[i].threshold);
        expect(first[i].acceptedCount, second[i].acceptedCount);
      }
      for (var i = 1; i < first.length; i++) {
        expect(first[i].threshold, greaterThan(first[i - 1].threshold));
        expect(
          first[i].acceptedCount,
          lessThanOrEqualTo(first[i - 1].acceptedCount),
        );
      }
    });

    test('accepted accuracy is null when nothing is accepted — never 1.0', () {
      final curve = riskCoverageCurve(const [
        SelectiveObservation(calibratedConfidence: null, correct: true),
      ]);

      expect(curve.single.acceptedCount, 0);
      expect(curve.single.acceptedAccuracy, isNull);
      expect(curve.single.risk, isNull);
      // The uncalibrated observation still counts in the denominator: the
      // curve may not hide coverage the calibrated policy cannot deliver.
      expect(curve.single.totalCount, 1);
      expect(curve.single.coverage, 0);
    });

    test('an empty observation list has a null coverage, not zero', () {
      final curve = riskCoverageCurve(const []);

      expect(curve.single.totalCount, 0);
      expect(curve.single.coverage, isNull);
    });
  });

  group('coverage-maximising selector', () {
    test('picks the lowest threshold that still keeps the accuracy '
        'promise (maximum coverage)', () {
      final policy = selectCoverageMaximisingPolicy(
        const [
          SelectiveObservation(calibratedConfidence: 0.95, correct: true),
          SelectiveObservation(calibratedConfidence: 0.85, correct: true),
          SelectiveObservation(calibratedConfidence: 0.75, correct: false),
        ],
        targetAcceptedAccuracy: 1,
      );

      expect(policy, isNotNull);
      expect(policy!.acceptAtOrAbove, 0.85);
      expect(policy.requiresCalibration, isTrue);
    });

    test('returns null when NO threshold reaches the target — the honest '
        'answer is "this model cannot promise that"', () {
      final policy = selectCoverageMaximisingPolicy(
        const [
          SelectiveObservation(calibratedConfidence: 0.95, correct: false),
          SelectiveObservation(calibratedConfidence: 0.85, correct: false),
        ],
        targetAcceptedAccuracy: 0.92,
      );

      expect(policy, isNull);
    });

    test('an all-uncalibrated population yields null, not accept-all', () {
      final policy = selectCoverageMaximisingPolicy(
        const [
          SelectiveObservation(calibratedConfidence: null, correct: true),
          SelectiveObservation(calibratedConfidence: null, correct: true),
        ],
        targetAcceptedAccuracy: 0.9,
      );

      expect(policy, isNull);
    });
  });

  group('coverage report', () {
    test('reports the uncalibrated count separately, so a coverage number '
        'can never hide a missing calibration', () {
      final report = SelectiveCoverageReport.of(
        const [
          SelectiveObservation(calibratedConfidence: 0.9, correct: true),
          SelectiveObservation(calibratedConfidence: null, correct: false),
        ],
        policy: const SelectivePredictionPolicy.acceptAll(),
      );

      expect(report.uncalibratedCount, 1);
      expect(report.point.acceptedCount, 2);
      expect(report.point.coverage, 1);
      expect(report.point.acceptedAccuracy, 0.5);
    });

    test('a degraded population raises ABSTENTION, never confidence: with '
        'the same policy, lower calibrated scores reduce coverage and the '
        'accepted predictions keep their own accuracy', () {
      final policy = SelectivePredictionPolicy.abstainBelow(0.8);
      final healthy = SelectiveCoverageReport.of(
        const [
          SelectiveObservation(calibratedConfidence: 0.95, correct: true),
          SelectiveObservation(calibratedConfidence: 0.9, correct: true),
        ],
        policy: policy,
      );
      final degraded = SelectiveCoverageReport.of(
        const [
          SelectiveObservation(calibratedConfidence: 0.5, correct: true),
          SelectiveObservation(calibratedConfidence: 0.4, correct: true),
        ],
        policy: policy,
      );

      expect(healthy.point.coverage, 1);
      expect(degraded.point.coverage, 0);
      expect(degraded.point.acceptedAccuracy, isNull);
    });
  });
}
