/// Availability of the Chapter 8 (Practice Generator) daily plan, as seen
/// from the Today Hub.
///
/// R19 (audit M4) wired the real source: `todayPlanRepositoryProvider` now
/// projects the Practice Generator's ACTIVE plan
/// (`activePracticePlanProvider`) onto this snapshot, so a learner who
/// generates and activates a plan sees it on the app's landing tab instead
/// of the permanent "no plan" hero. [offlineCached] / [syncPending] stay
/// reachable only through a fake [TodayPlanRepository]: the plan store is
/// 100% on-device (`LocalPracticePlanRepository`), so there is no cloud
/// round-trip that could be pending — inventing one would be a lie about
/// state the app cannot observe.
enum TodayPlanAvailability {
  /// No plan source is wired yet, or the user has none — the honest default.
  unavailable,

  /// The plan source answered with a FAILURE (a present-but-corrupt record,
  /// an unreadable store). Deliberately NOT [unavailable]: "we could not
  /// read your plan" is not "you have no plan", and collapsing the two
  /// would silently reclassify a real error as a fresh start — the exact
  /// anti-pattern `LocalPracticePlanRepository.readActivePlan`'s own
  /// contract forbids.
  unreadable,

  /// A plan exists locally but the device is offline; it stays fully usable
  /// (ADR 0277 §2 — offline is not an error state).
  offlineCached,

  /// A plan exists and a cloud sync is in flight.
  syncPending,

  /// A plan is available and current.
  ready,
}

/// A read-only projection of today's plan, sized to exactly what the Today
/// Hub renders — never the full [AdaptiveGuitarPlan] domain shape.
final class TodayPlanSnapshot {
  const TodayPlanSnapshot({
    required this.availability,
    this.recommendedTaskLabel,
    this.recommendedMissionId,
    this.completedTaskCount = 0,
    this.totalTaskCount = 0,
  });

  final TodayPlanAvailability availability;

  /// The hero's message line: the single next recommended task when the
  /// plan names one, otherwise the localized reason today has none (rest
  /// day, no session scheduled, nothing remaining). `null` leaves the
  /// caller's own default copy in place.
  final String? recommendedTaskLabel;

  /// The curriculum rung this recommendation is, when it comes from the course.
  ///
  /// An ID rather than a label, because the NAME a learner reads must be
  /// localised and this projection has no localisations — a plan source that
  /// filled in English prose here would put English in front of a Hungarian
  /// learner, and the l10n parity gate would never notice because nothing would
  /// be missing from the arb files. The surface resolves it
  /// (`curriculumMissionName`).
  ///
  /// Also what lets the hub's primary button continue THAT rung rather than a
  /// default: a button labelled "continue" that goes somewhere else is the hub
  /// lying about what it just offered.
  final String? recommendedMissionId;

  final int completedTaskCount;
  final int totalTaskCount;

  /// Whether a plan is actually readable for today. [unreadable] is false
  /// here on purpose: a caller must never render plan content — counts, a
  /// recommendation, a "continue" affordance — off a snapshot whose source
  /// failed.
  bool get hasPlan =>
      availability == TodayPlanAvailability.ready ||
      availability == TodayPlanAvailability.offlineCached ||
      availability == TodayPlanAvailability.syncPending;

  bool get isDayCompleted =>
      hasPlan && totalTaskCount > 0 && completedTaskCount >= totalTaskCount;
}
