/// Versioned, deterministic configuration for the [WeeklyScheduler]
/// (ADR 0299, SDD Ch8 Kör 15).
///
/// The policy encodes every numeric knob the scheduler uses to place
/// candidates on the week: maximum counts of primary and secondary focus
/// candidates per day, the inclusive maximum length of a high-load run,
/// the upper bound on the share of the week that review candidates may
/// occupy, the song-target phase boundaries, and the light-review window
/// inside which only review candidates are eligible. The scheduler never
/// reads a clock and never generates randomness. Every value is validated
/// at construction and exposed as an immutable field so the
/// [ScheduleDecision] can carry the policy provenance the same way
/// [TimeBudgetAllocation] carries the [TimeAllocationPolicy].
library;

import '../model/exercise_candidate.dart';

/// The relative pedagogical weight of one candidate within a single day.
///
/// The classification is what the scheduler reads to enforce the napi
/// fókusz-limit (A7) — one primary focus candidate per day, at most one
/// secondary focus candidate, anything else is supporting material.
enum CandidateFocus { primaryFocus, secondaryFocus, supporting }

/// Whether a candidate introduces new material or only reviews previously
/// learned content.
///
/// The classification is what the scheduler reads to enforce the
/// bounded review ratio (A4) and the song-target light-review window
/// (A5) — inside the light-review window only review candidates are
/// eligible.
enum CandidateMaterialKind { newMaterial, review }

/// The song-target phase a day falls into, derived purely from the
/// `today`-to-`target` distance (ADR 0299 decision 5).
///
/// The phase determines whether new-material candidates are eligible on
/// the day. Inside the light-review window only review candidates are
/// placed — new material would defeat the purpose of the taper.
enum SchedulingPhase {
  /// Outside any song-target range — the scheduler behaves normally.
  none('scheduling.phase.none'),

  /// Target is further than [SchedulingPolicy.reviewLeadDays]. New
  /// material is welcome on the day.
  preparation('scheduling.phase.preparation'),

  /// Target is within the light-review window. Only review candidates
  /// are eligible — no new material is placed.
  lightReview('scheduling.phase.lightReview'),

  /// Target is today. Only review candidates are eligible, and the
  /// scheduler shortens the high-load budget on the day to support the
  /// performance (the focus-limit stays at one primary + one
  /// secondary — the load reduction is a per-day budget concern, not a
  /// scheduling one).
  performance('scheduling.phase.performance');

  const SchedulingPhase(this.code);

  final String code;

  static SchedulingPhase fromCode(String? code) {
    if (code == null || code.trim().isEmpty) {
      throw ArgumentError.value(
        code,
        'code',
        'SchedulingPhase code must not be empty',
      );
    }
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(
      code,
      'code',
      'Unknown SchedulingPhase code: $code',
    );
  }

  @override
  String toString() => code;
}

/// The stable, machine-readable reason a per-day decision was made.
///
/// Every reason carries an alphanumeric code so diagnostics can group
/// them without parsing free text. The codes are persisted in the
/// `ScheduleDecision` for review (§6.1, §5.6).
enum ScheduleDecisionReason {
  /// The day is unavailable — no decision is emitted.
  dayUnavailable('schedule.decision.dayUnavailable'),

  /// The day is marked as rest — no decision is emitted.
  restDay('schedule.decision.restDay'),

  /// The day is inside the song-target light-review window — only review
  /// candidates were eligible.
  lightReviewWindow('schedule.decision.lightReviewWindow'),

  /// The maximum-review-ratio policy was already saturated, so the
  /// scheduler refused to add another review candidate.
  reviewBudgetSaturated('schedule.decision.reviewBudgetSaturated'),

  /// The high-load-run limit was already saturated, so the scheduler
  /// refused to add another high-load candidate.
  highLoadRunSaturated('schedule.decision.highLoadRunSaturated'),

  /// The day already had its primary focus candidate, so the candidate
  /// was deferred.
  primaryFocusAlreadyAssigned('schedule.decision.primaryFocusAlreadyAssigned'),

  /// The day already had its secondary focus candidate, so the candidate
  /// was deferred.
  secondaryFocusAlreadyAssigned(
    'schedule.decision.secondaryFocusAlreadyAssigned',
  ),

  /// The candidate's duration exceeded the day budget, so it was
  /// rejected for the day.
  dayBudgetExceeded('schedule.decision.dayBudgetExceeded'),

  /// The candidate did not match the day phase (e.g. new-material
  /// candidate inside the light-review window).
  phaseMismatch('schedule.decision.phaseMismatch'),

  /// The candidate was selected for the day.
  selected('schedule.decision.selected');

  const ScheduleDecisionReason(this.code);

  final String code;

  static ScheduleDecisionReason fromCode(String? code) {
    if (code == null || code.trim().isEmpty) {
      throw ArgumentError.value(
        code,
        'code',
        'ScheduleDecisionReason code must not be empty',
      );
    }
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(
      code,
      'code',
      'Unknown ScheduleDecisionReason code: $code',
    );
  }

  @override
  String toString() => code;
}

/// Versioned, deterministic configuration for the [WeeklyScheduler]
/// (ADR 0299).
///
/// Every value is validated at construction. The scheduler exposes the
/// policy on every decision so reviewers can audit what produced the
/// week.
final class SchedulingPolicy {
  SchedulingPolicy({
    String version = 'scheduling-policy-v1',
    int maximumPrimaryFocusPerDay = 1,
    int maximumSecondaryFocusPerDay = 1,
    int maximumHighLoadRunDays = 2,
    double maximumReviewRatio = 0.4,
    int reviewLeadDays = 7,
    int lightReviewWindowDays = 3,
  }) : version = _requireText(version, 'version'),
       maximumPrimaryFocusPerDay = _requirePositiveInt(
         maximumPrimaryFocusPerDay,
         'maximumPrimaryFocusPerDay',
       ),
       maximumSecondaryFocusPerDay = _requirePositiveInt(
         maximumSecondaryFocusPerDay,
         'maximumSecondaryFocusPerDay',
       ),
       maximumHighLoadRunDays = _requirePositiveInt(
         maximumHighLoadRunDays,
         'maximumHighLoadRunDays',
       ),
       maximumReviewRatio = _requireUnitInterval(
         maximumReviewRatio,
         'maximumReviewRatio',
       ),
       reviewLeadDays = _requirePositiveInt(reviewLeadDays, 'reviewLeadDays'),
       lightReviewWindowDays = _requirePositiveInt(
         lightReviewWindowDays,
         'lightReviewWindowDays',
       ) {
    if (lightReviewWindowDays > reviewLeadDays) {
      throw ArgumentError.value(
        lightReviewWindowDays,
        'lightReviewWindowDays',
        'must not exceed reviewLeadDays ($reviewLeadDays)',
      );
    }
  }

  /// Stable identifier retained by the [WeeklyScheduler] as decision
  /// provenance (ADR 0299 §3).
  final String version;

  /// The maximum number of `primaryFocus` candidates the scheduler may
  /// place on a single day (A7). Default `1` keeps the day's focus
  /// singular.
  final int maximumPrimaryFocusPerDay;

  /// The maximum number of `secondaryFocus` candidates the scheduler may
  /// place on a single day (A7).
  final int maximumSecondaryFocusPerDay;

  /// The inclusive maximum length of an uninterrupted run of
  /// high-load days (A2, §6.1 cells). The scheduler will not place a
  /// high-load candidate on a day that would extend the run beyond
  /// this limit — the candidate is deferred to a later day.
  final int maximumHighLoadRunDays;

  /// The upper bound on the share of the week's total active minutes
  /// that review candidates may occupy (A4). When the share is at or
  /// above the limit, additional review candidates are deferred.
  final double maximumReviewRatio;

  /// The number of days before the song target when the
  /// [SchedulingPhase.preparation] window opens.
  final int reviewLeadDays;

  /// The number of days before the song target during which only
  /// review candidates are eligible (A5, ADR 0299 decision 5). The
  /// [SchedulingPhase.lightReview] window is the inner
  /// `lightReviewWindowDays` of the broader preparation window.
  final int lightReviewWindowDays;

  /// The default v1 scheduling policy.
  static final SchedulingPolicy defaultPolicy = SchedulingPolicy();

  /// The maximum `LoadLevel` that still counts toward a "high-load run".
  /// The default uses the shared [LoadLevel.high] so every other module
  /// agrees on the threshold.
  static const LoadLevel highLoadLevel = LoadLevel.high;

  /// Decide which phase a date falls into given its `today`-to-`target`
  /// distance in days.
  ///
  /// The distance is `(target - today).inDays`, signed by the
  /// [LocalDate] order. A non-positive distance returns
  /// [SchedulingPhase.performance] (today and earlier targets), a
  /// positive distance inside the light-review window returns
  /// [SchedulingPhase.lightReview], a positive distance inside the
  /// broader preparation window returns
  /// [SchedulingPhase.preparation], and anything else returns
  /// [SchedulingPhase.none] (no song target was configured, or the
  /// target is further than the review lead).
  SchedulingPhase phaseForDayDistance(int dayDistance) {
    if (dayDistance <= 0) return SchedulingPhase.performance;
    if (dayDistance <= lightReviewWindowDays) {
      return SchedulingPhase.lightReview;
    }
    if (dayDistance <= reviewLeadDays) return SchedulingPhase.preparation;
    return SchedulingPhase.none;
  }
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}

int _requirePositiveInt(int value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
  return value;
}

double _requireUnitInterval(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, name, 'must be finite and within [0, 1]');
  }
  return value;
}
