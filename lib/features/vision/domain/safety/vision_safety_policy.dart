// E05-R20 — Vision safety policy (ADR 0188, brief §5).
//
// The `VisionSafetyPolicy` is the code-catalogue counterpart of the
// tutor's `TutorSafetyPolicy` (ADR 0177). The vision layer emits
// CLAIM CODES from a closed set (the metric catalog), never free
// text — the guard works on the code, not on a sentence.
//
// Two design points from ADR 0188 are non-negotiable:
//
//   - The catalog is a fail-closed allowlist. Every allowed claim
//     must declare a class in the closed `VisionSafetyClaimClass`
//     enum. Classes not in the enum are forbidden. Codes that declare
//     a forbidden class are rejected by the guard, just as codes that
//     are not in the catalog at all are rejected.
//
//   - The vision layer does NOT import the tutor safety module. The
//     two guards are deliberately separate mechanisms, built on the
//     same fail-closed philosophy, working on different layers
//     (codes vs. free text). See ADR 0188 §"Elutasított alternatívák".
//
// The pain-response handoff is a sibling channel — it is not a
// posture claim code and not subject to the guard. The pain
// taxonomy is the tutor's `painResponse` (ADR 0177). The brief §5 /4
// pins this: the vision layer only signals that the coaching cue
// should be muted, never that the user's pain is explained.

library;

/// The closed set of vision safety claim classes.
///
/// The brief §5 /1 lists the forbidden classes by description; this
/// enum pins them by name. The set is deliberately complete: a
/// future class either maps to an existing value (and the claim is
/// code-checked) or is added with a new ADR-worthy decision.
enum VisionSafetyClaimClass {
  // -- Forbidden classes (brief §5 /1). A claim landing in any of
  // these is rejected by the guard.

  /// Diagnosis — a health-state assertion about the user.
  diagnosis,

  /// Injury prediction — a future-state harm claim.
  injuryPrediction,

  /// Pain explanation — attributing a cause to the user's pain.
  painExplanation,

  /// Recovery advice — telling the user to rest / heal / change
  /// routine to fix a medical issue.
  recoveryAdvice,

  /// "Harmful" judgment — a value-loaded label that a posture or
  /// habit is harmful.
  harmfulJudgment,

  // -- Allowed classes (brief §5 /1). All catalogues code lives here.

  /// Baseline-relative quantitative observation. The flagship class
  /// — every posture metric lands here when the deviation is
  /// measured against the user's own baseline.
  baselineRelative,

  /// Neutral observation — a categorical observation that does not
  /// compare to a baseline (e.g. "the elbow is visible in the
  /// frame").
  neutralObservation,

  /// Unobservable — explicit non-observation. Distinct from
  /// `notObservable` on a metric (which is a per-metric signal): this
  /// is the posture-side confirmation that the engine rejected
  /// every metric.
  unobservable,
}

/// The forbidden subset of [VisionSafetyClaimClass]. The guard
/// references this set, not the enum's name list, so the boundary is
/// enforced mechanically.
extension VisionSafetyClaimClassBoundary on VisionSafetyClaimClass {
  /// True when the class is in the forbidden short list (brief §5
  /// /1). A claim declared in any of these classes is rejected by
  /// the guard, even if the code is in the catalog.
  bool get isForbidden => VisionSafetyPolicy.forbidden.contains(this);
}

/// The static catalog of allowed vision claim codes, each mapped to
/// its declared class.
///
/// The catalog is the single source of truth — the guard checks
/// both that a code is in the map AND that the declared class is
/// not forbidden. A future posture metric (R23 / R27) extends this
/// map; the guard test (`safety_claim_guard_test.dart`) pinpoints
/// the invariant.
class VisionSafetyPolicy {
  const VisionSafetyPolicy._();

  /// The closed catalog. Keys are claim codes; values are the
  /// declared class. The catalog only contains ALLOWED classes.
  static const Map<String, VisionSafetyClaimClass>
  catalog = <String, VisionSafetyClaimClass>{
    // Shoulder asymmetry (SDD §21).
    'postureShoulderAsymmetryIncreasedVsBaseline':
        VisionSafetyClaimClass.baselineRelative,
    'postureShoulderAsymmetryReducedVsBaseline':
        VisionSafetyClaimClass.baselineRelative,

    // Torso lean (SDD §21).
    'postureTorsoLeanShiftedVsBaseline':
        VisionSafetyClaimClass.baselineRelative,
    'postureTorsoLeanReturnedToBaseline':
        VisionSafetyClaimClass.baselineRelative,

    // Elbow drift (SDD §21).
    'postureElbowDriftObserved': VisionSafetyClaimClass.neutralObservation,
    'postureElbowDriftReducedVsBaseline':
        VisionSafetyClaimClass.baselineRelative,

    // Neck proxy (SDD §21).
    'postureNeckProxyShiftedVsBaseline':
        VisionSafetyClaimClass.baselineRelative,
    'postureNeckProxyUnavailable': VisionSafetyClaimClass.unobservable,

    // Aggregate, narration-free signposts (R23 / R27 will flesh
    // out the rendering pipeline).
    'postureMetricsNotObservable': VisionSafetyClaimClass.unobservable,

    // E05-R23 feedback policy insight catalogue (ADR 0191). These are
    // stable, rendering-free codes; the localized text belongs in ARB.
    'visionInsightSetupNotObservable': VisionSafetyClaimClass.unobservable,
    'visionInsightFrettingStable': VisionSafetyClaimClass.neutralObservation,
    'visionInsightFrettingFocus': VisionSafetyClaimClass.baselineRelative,
    'visionInsightFrettingImproved': VisionSafetyClaimClass.baselineRelative,
    'visionInsightPickingStable': VisionSafetyClaimClass.neutralObservation,
    'visionInsightPickingFocus': VisionSafetyClaimClass.baselineRelative,
    'visionInsightPickingImproved': VisionSafetyClaimClass.baselineRelative,
    'visionInsightPostureStable': VisionSafetyClaimClass.neutralObservation,
    'visionInsightPostureFocus': VisionSafetyClaimClass.baselineRelative,
    'visionInsightPostureImproved': VisionSafetyClaimClass.baselineRelative,
    'visionInsightExperimentalObservation':
        VisionSafetyClaimClass.neutralObservation,
  };

  /// The forbidden-class set is exposed here so the guard and the
  /// catalog-validation tests share a single source of truth.
  static const Set<VisionSafetyClaimClass> forbidden = <VisionSafetyClaimClass>{
    VisionSafetyClaimClass.diagnosis,
    VisionSafetyClaimClass.injuryPrediction,
    VisionSafetyClaimClass.painExplanation,
    VisionSafetyClaimClass.recoveryAdvice,
    VisionSafetyClaimClass.harmfulJudgment,
  };
}
