import '../evidence/vision_evidence.dart';
import '../feedback/insight_code.dart';

/// The deterministic outcome of an evidence-sufficiency claim evaluation.
final class VisionClaimGuardResult {
  const VisionClaimGuardResult._({required this.code, required this.isAllowed});

  const VisionClaimGuardResult.allowed(InsightCode code)
    : this._(code: code, isAllowed: true);

  const VisionClaimGuardResult.notObservable()
    : this._(code: InsightCode.setupNotObservable, isAllowed: false);

  final InsightCode code;
  final bool isAllowed;
}

/// Fail-closed confidence gate for Tutor-facing Vision insight claims.
final class VisionClaimGuard {
  const VisionClaimGuard();

  static const double _minimumConfidence = 0.70;
  static const double _minimumNegativeConfidence = 0.85;

  static const Set<InsightCode> _catalog = <InsightCode>{
    InsightCode.frettingStable,
    InsightCode.frettingFocus,
    InsightCode.frettingImproved,
    InsightCode.pickingStable,
    InsightCode.pickingFocus,
    InsightCode.pickingImproved,
    InsightCode.postureStable,
    InsightCode.postureFocus,
    InsightCode.postureImproved,
    InsightCode.experimentalObservation,
  };

  static const Set<InsightCode> _negativeClaims = <InsightCode>{
    InsightCode.frettingFocus,
    InsightCode.pickingFocus,
    InsightCode.postureFocus,
  };

  /// Allows a claim only when its catalog entry has evidence at the threshold.
  VisionClaimGuardResult evaluate({
    required InsightCode claim,
    required VisionEvidence? evidence,
    required double confidence,
  }) {
    final minimumConfidence = _negativeClaims.contains(claim)
        ? _minimumNegativeConfidence
        : _minimumConfidence;

    if (!_catalog.contains(claim) ||
        evidence == null ||
        evidence.observationState == ObservationState.notObservable ||
        evidence.confidence < minimumConfidence ||
        !confidence.isFinite ||
        confidence < minimumConfidence) {
      return const VisionClaimGuardResult.notObservable();
    }
    return VisionClaimGuardResult.allowed(claim);
  }
}
