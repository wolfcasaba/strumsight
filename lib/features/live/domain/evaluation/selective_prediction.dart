/// Selective prediction: abstain instead of guessing (E14-R21, ADR 0536).
///
/// A selective predictor answers only when its CALIBRATED confidence clears
/// a threshold, and reports the price of that silence — coverage. This file
/// is pure and deterministic: the same observations always produce the same
/// curve and the same selected policy, in the same order.
///
/// Two honesty rules are structural here, not conventions:
///
/// 1. An uncalibrated confidence is NOT a risk statement. When
///    [SelectivePredictionPolicy.requiresCalibration] holds (every policy
///    except [SelectivePredictionPolicy.acceptAll]) a `null` calibrated
///    confidence abstains — it never falls back to the raw score.
/// 2. The shipped default is [SelectivePredictionPolicy.acceptAll]: with no
///    measured calibration the policy is the IDENTITY on today's behaviour
///    (nothing new is suppressed), so this round can ship a mechanism
///    without silently changing what the user sees.
library;

/// What a selective predictor did with one prediction.
enum SelectiveDecision { accept, abstain }

/// Why it abstained. `null` for [SelectiveDecision.accept].
enum SelectiveAbstainReason {
  /// The policy needs a calibrated confidence and none was available.
  noCalibratedConfidence,

  /// The calibrated confidence was below the policy's threshold.
  belowThreshold,
}

/// One selective verdict: a decision plus, when abstaining, the reason.
final class SelectiveOutcome {
  const SelectiveOutcome._(this.decision, this.abstainReason);

  const SelectiveOutcome.accept() : this._(SelectiveDecision.accept, null);

  const SelectiveOutcome.abstain(SelectiveAbstainReason reason)
    : this._(SelectiveDecision.abstain, reason);

  final SelectiveDecision decision;
  final SelectiveAbstainReason? abstainReason;

  bool get isAccepted => decision == SelectiveDecision.accept;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectiveOutcome &&
          other.decision == decision &&
          other.abstainReason == abstainReason;

  @override
  int get hashCode => Object.hash(decision, abstainReason);
}

/// An abstention policy over CALIBRATED confidence.
final class SelectivePredictionPolicy {
  const SelectivePredictionPolicy._({
    required this.acceptAtOrAbove,
    required this.requiresCalibration,
  });

  /// Accept everything — the shipped default (see the library doc). Accepts
  /// even an uncalibrated prediction, because it makes no risk claim at all.
  const SelectivePredictionPolicy.acceptAll()
    : this._(acceptAtOrAbove: 0, requiresCalibration: false);

  /// Accept only at or above [threshold] on the calibrated confidence.
  /// [threshold] must be inside `0..1`; the boundary belongs to the
  /// ACCEPTING side (`>=`), matching the release gate's convention
  /// (ADR 0511 D3).
  factory SelectivePredictionPolicy.abstainBelow(double threshold) {
    if (threshold.isNaN || threshold < 0 || threshold > 1) {
      throw ArgumentError.value(
        threshold,
        'threshold',
        'must be a number inside 0..1',
      );
    }
    return SelectivePredictionPolicy._(
      acceptAtOrAbove: threshold,
      requiresCalibration: true,
    );
  }

  final double acceptAtOrAbove;
  final bool requiresCalibration;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectivePredictionPolicy &&
          other.acceptAtOrAbove == acceptAtOrAbove &&
          other.requiresCalibration == requiresCalibration;

  @override
  int get hashCode => Object.hash(acceptAtOrAbove, requiresCalibration);

  @override
  String toString() =>
      'SelectivePredictionPolicy(acceptAtOrAbove: $acceptAtOrAbove, '
      'requiresCalibration: $requiresCalibration)';
}

/// Applies [policy] to one prediction's [calibratedConfidence] (`null` when
/// no measured calibration is available — the shipped state, ADR 0536 D1).
SelectiveOutcome applySelectivePolicy({
  required double? calibratedConfidence,
  required SelectivePredictionPolicy policy,
}) {
  if (calibratedConfidence == null) {
    return policy.requiresCalibration
        ? const SelectiveOutcome.abstain(
            SelectiveAbstainReason.noCalibratedConfidence,
          )
        : const SelectiveOutcome.accept();
  }
  return calibratedConfidence >= policy.acceptAtOrAbove
      ? const SelectiveOutcome.accept()
      : const SelectiveOutcome.abstain(SelectiveAbstainReason.belowThreshold);
}

/// One labelled observation for the risk–coverage curve: what the model was
/// calibrated to say, and whether it was right.
final class SelectiveObservation {
  const SelectiveObservation({
    required this.calibratedConfidence,
    required this.correct,
  });

  /// `null` when the prediction had no calibrated confidence.
  final double? calibratedConfidence;
  final bool correct;
}

/// One point of the risk–coverage curve.
final class RiskCoveragePoint {
  const RiskCoveragePoint({
    required this.threshold,
    required this.acceptedCount,
    required this.correctAcceptedCount,
    required this.totalCount,
  });

  final double threshold;
  final int acceptedCount;
  final int correctAcceptedCount;
  final int totalCount;

  /// Accepted / total. `null` when [totalCount] is `0` — never coerced to
  /// `0` (ADR 0509 D6).
  double? get coverage => totalCount == 0 ? null : acceptedCount / totalCount;

  /// Correct / accepted. `null` when nothing was accepted — "no accepted
  /// prediction" is not "100% accurate".
  double? get acceptedAccuracy =>
      acceptedCount == 0 ? null : correctAcceptedCount / acceptedCount;

  /// `1 − acceptedAccuracy`, `null` under the same condition.
  double? get risk {
    final accuracy = acceptedAccuracy;
    return accuracy == null ? null : 1 - accuracy;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'threshold': threshold,
    'acceptedCount': acceptedCount,
    'correctAcceptedCount': correctAcceptedCount,
    'totalCount': totalCount,
    'coverage': coverage,
    'acceptedAccuracy': acceptedAccuracy,
    'risk': risk,
  };
}

/// The risk–coverage curve over [observations], evaluated at every DISTINCT
/// calibrated confidence present plus `0.0` (accept-everything-calibrated).
/// Thresholds come out ascending, so coverage is non-increasing along the
/// list — the shape a reader expects.
///
/// Observations with a `null` calibrated confidence are never accepted at
/// any threshold, but they DO count toward the coverage denominator: hiding
/// them would report a coverage the user never gets.
List<RiskCoveragePoint> riskCoverageCurve(
  List<SelectiveObservation> observations,
) {
  final thresholds = <double>{0.0};
  for (final observation in observations) {
    final confidence = observation.calibratedConfidence;
    if (confidence != null) thresholds.add(confidence);
  }
  final sorted = thresholds.toList()..sort();
  return <RiskCoveragePoint>[
    for (final threshold in sorted) _pointAt(observations, threshold),
  ];
}

RiskCoveragePoint _pointAt(
  List<SelectiveObservation> observations,
  double threshold,
) {
  final policy = threshold == 0
      ? const SelectivePredictionPolicy.acceptAll()
      : SelectivePredictionPolicy.abstainBelow(threshold);
  var accepted = 0;
  var correct = 0;
  for (final observation in observations) {
    // At threshold 0 an uncalibrated observation would be accepted by
    // `acceptAll`; on the CURVE it must not be, or the curve would credit
    // coverage the calibrated policy cannot deliver.
    if (observation.calibratedConfidence == null) continue;
    final outcome = applySelectivePolicy(
      calibratedConfidence: observation.calibratedConfidence,
      policy: policy,
    );
    if (!outcome.isAccepted) continue;
    accepted++;
    if (observation.correct) correct++;
  }
  return RiskCoveragePoint(
    threshold: threshold,
    acceptedCount: accepted,
    correctAcceptedCount: correct,
    totalCount: observations.length,
  );
}

/// The coverage-maximising policy whose accepted accuracy is at least
/// [targetAcceptedAccuracy] (SDD Ch14 §7.2's "accepted accuracy alongside
/// coverage" read as a selector: among the thresholds that hold the accuracy
/// promise, take the one that answers most often).
///
/// Returns `null` when NO threshold reaches the target — the honest answer
/// is "this model cannot promise that accuracy", never "here is the least
/// bad threshold" (ADR 0536 D5). Ties break toward the LOWER threshold, so
/// the selection is deterministic.
SelectivePredictionPolicy? selectCoverageMaximisingPolicy(
  List<SelectiveObservation> observations, {
  required double targetAcceptedAccuracy,
}) {
  if (targetAcceptedAccuracy.isNaN ||
      targetAcceptedAccuracy < 0 ||
      targetAcceptedAccuracy > 1) {
    throw ArgumentError.value(
      targetAcceptedAccuracy,
      'targetAcceptedAccuracy',
      'must be a number inside 0..1',
    );
  }
  RiskCoveragePoint? best;
  for (final point in riskCoverageCurve(observations)) {
    final accuracy = point.acceptedAccuracy;
    if (accuracy == null || accuracy < targetAcceptedAccuracy) continue;
    if (best == null || point.acceptedCount > best.acceptedCount) {
      best = point;
    }
  }
  if (best == null) return null;
  return best.threshold == 0
      ? const SelectivePredictionPolicy.acceptAll()
      : SelectivePredictionPolicy.abstainBelow(best.threshold);
}

/// The coverage report a round/CI run prints alongside the gate: the policy
/// that was applied and what it cost.
final class SelectiveCoverageReport {
  const SelectiveCoverageReport({
    required this.policy,
    required this.point,
    required this.uncalibratedCount,
  });

  factory SelectiveCoverageReport.of(
    List<SelectiveObservation> observations, {
    required SelectivePredictionPolicy policy,
  }) {
    var accepted = 0;
    var correct = 0;
    var uncalibrated = 0;
    for (final observation in observations) {
      if (observation.calibratedConfidence == null) uncalibrated++;
      final outcome = applySelectivePolicy(
        calibratedConfidence: observation.calibratedConfidence,
        policy: policy,
      );
      if (!outcome.isAccepted) continue;
      accepted++;
      if (observation.correct) correct++;
    }
    return SelectiveCoverageReport(
      policy: policy,
      point: RiskCoveragePoint(
        threshold: policy.acceptAtOrAbove,
        acceptedCount: accepted,
        correctAcceptedCount: correct,
        totalCount: observations.length,
      ),
      uncalibratedCount: uncalibrated,
    );
  }

  final SelectivePredictionPolicy policy;
  final RiskCoveragePoint point;

  /// How many observations carried no calibrated confidence. Reported
  /// separately so a coverage number can never hide a missing calibration.
  ///
  /// Note the deliberate asymmetry with [riskCoverageCurve]: this report
  /// says what the GIVEN policy actually does, so under
  /// [SelectivePredictionPolicy.acceptAll] the uncalibrated observations are
  /// accepted (today's behaviour) and counted here; the curve, which exists
  /// to choose a calibrated threshold, never accepts them.
  final int uncalibratedCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'policy': <String, Object?>{
      'acceptAtOrAbove': policy.acceptAtOrAbove,
      'requiresCalibration': policy.requiresCalibration,
    },
    'point': point.toJson(),
    'uncalibratedCount': uncalibratedCount,
  };
}
