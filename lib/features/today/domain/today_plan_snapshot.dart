/// Availability of the Chapter 8 (Practice Generator) daily plan, as seen
/// from the Today Hub. §0.0/R6.1 measured that no presentation-layer
/// provider exists yet for `TodayPlanController` — production always reads
/// [unavailable] until a future round wires the real source; tests exercise
/// the other three states through a fake [TodayPlanRepository] (brief §5.5).
enum TodayPlanAvailability {
  /// No plan source is wired yet, or the user has none — the honest default.
  unavailable,

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

  /// The single next recommended task, if the plan names one.
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

  bool get hasPlan => availability != TodayPlanAvailability.unavailable;

  bool get isDayCompleted =>
      hasPlan && totalTaskCount > 0 && completedTaskCount >= totalTaskCount;
}
