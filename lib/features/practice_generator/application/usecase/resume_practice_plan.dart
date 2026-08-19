/// Caller-fed resume of a paused practice plan (ADR 0269 §5.3–§5.4,
/// SDD Ch8 Kör 27).
///
/// Resume is more than a status flip. The use case:
///
///   1. Verifies the previous revision is in [PlanStatus.paused].
///   2. Re-anchors the day list so its first day equals `resumeDate`.
///      Days whose shifted date would land before `resumeDate` are
///      dropped — there is no backlog, only future work (A3,
///      ADR 0269 §5.3).
///   3. Sets the new `startDate` to `resumeDate` and the new `endDate`
///      to the shifted last day.
///   4. Flips the plan's status back to [PlanStatus.active].
///   5. Picks the new [GenerationMode] — `returningAfterBreak` if the
///      pause-to-resume gap is at or above [ResumePracticePlan.longBreakThreshold]
///      (default 21), otherwise the caller-supplied original mode.
///      The boundary belongs to the cautious side (ADR 0269 §5.4), so
///      a 21-day gap is the first call that flips the mode.
///
/// No backlog is ever created — even after a long pause, the resumed
/// plan starts at the caller's `resumeDate`, not at `pauseDate + N`
/// days of accumulated debt. That is A5: the readiness proposal is the
/// right tool for catching up, not a longer day.
library;

import '../../domain/id/planner_ids.dart';
import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/plan_enums.dart';
import '../../domain/model/plan_revision.dart';
import '../../domain/model/practice_day.dart';
import '../../domain/model/weekly_availability.dart';

/// Inputs for [ResumePracticePlan].
final class ResumePracticePlanRequest {
  const ResumePracticePlanRequest({
    required this.previous,
    required this.nextRevisionId,
    required this.pauseDate,
    required this.resumeDate,
    required this.originalMode,
  });

  /// The current paused revision that is being resumed. Must have
  /// [PlanStatus.paused].
  final PlanRevision previous;

  /// The new revision's id (assigned by the composition layer).
  final RevisionId nextRevisionId;

  /// The local date the learner paused. The use case compares this to
  /// `resumeDate` to decide the [GenerationMode].
  final LocalDate pauseDate;

  /// The local date the learner comes back. Becomes the new `startDate`.
  final LocalDate resumeDate;

  /// The plan's pre-pause mode. Preserved as the resumed plan's mode
  /// when the gap is short.
  final GenerationMode originalMode;
}

/// Result of [ResumePracticePlan]: the new revision plus the
/// caller-supplied gap accounting.
final class ResumePracticePlanResult {
  const ResumePracticePlanResult({
    required this.revision,
    required this.resumeDate,
    required this.pauseDate,
    required this.gapDays,
    required this.crossedLongBreak,
    required this.pickedMode,
  });

  final PlanRevision revision;
  final LocalDate resumeDate;
  final LocalDate pauseDate;

  /// The number of calendar days between `pauseDate` and `resumeDate`
  /// (positive, exclusive of `pauseDate`, inclusive of `resumeDate`).
  final int gapDays;

  /// True when [gapDays] is at or above the policy's long-break
  /// threshold. The next revision therefore carries
  /// [GenerationMode.returningAfterBreak].
  final bool crossedLongBreak;

  /// The [GenerationMode] the resumed plan should carry. Equals
  /// [GenerationMode.returningAfterBreak] when [crossedLongBreak] is
  /// true, otherwise [ResumePracticePlanRequest.originalMode].
  final GenerationMode pickedMode;
}

/// Pure use case.
final class ResumePracticePlan {
  ResumePracticePlan({required this.clock, int longBreakThreshold = 21})
    : longBreakThreshold = _positive(longBreakThreshold, 'longBreakThreshold');

  /// Inclusive lower bound for the "long break" mode flip. The
  /// boundary belongs to the cautious side (ADR 0269 §5.4), so 21 days
  /// is the first gap that returns `returningAfterBreak`.
  final int longBreakThreshold;

  /// The wall-clock UTC time. Used only for the new revision's
  /// `createdAt`; all calendar arithmetic uses caller-supplied dates.
  final DateTime Function() clock;

  ResumePracticePlanResult call(ResumePracticePlanRequest request) {
    final previous = request.previous;
    _validateResumable(previous);
    _validateOrder(request);

    final oldDays = previous.snapshot.days;
    if (oldDays.isEmpty) {
      throw StateError('Cannot resume a plan that has no scheduled days');
    }

    final originalStart = oldDays.first.localDate;
    final resumeOrdinal = _dayOrdinal(request.resumeDate);
    final originalStartOrdinal = _dayOrdinal(originalStart);
    final shift = resumeOrdinal - originalStartOrdinal;

    final shiftedDays = <PracticeDay>[];
    for (final day in oldDays) {
      final newOrdinal = _dayOrdinal(day.localDate) + shift;
      if (newOrdinal < resumeOrdinal) {
        // Drop days that would fall before the resume date — no backlog
        // is ever created (ADR 0269 §5.3, A3).
        continue;
      }
      final newDate = _dateFromOrdinal(newOrdinal);
      shiftedDays.add(
        PracticeDay(
          id: day.id,
          localDate: newDate,
          status: day.status,
          timeBudget: day.timeBudget,
          blocks: day.blocks,
          primaryFocusSkillIds: day.primaryFocusSkillIds,
          reasonCodes: day.reasonCodes,
        ),
      );
    }

    if (shiftedDays.isEmpty) {
      throw StateError(
        'Resumed plan has no days on or after resumeDate '
        '${request.resumeDate}; cannot produce an empty schedule',
      );
    }

    final newStart = shiftedDays.first.localDate;
    final newEnd = shiftedDays.last.localDate;
    final gapDays = resumeOrdinal - _dayOrdinal(request.pauseDate);
    final crossedLongBreak = gapDays >= longBreakThreshold;
    final pickedMode = crossedLongBreak
        ? GenerationMode.returningAfterBreak
        : request.originalMode;

    final resumedSnapshot = AdaptivePracticePlan(
      id: previous.snapshot.id,
      schemaVersion: previous.snapshot.schemaVersion,
      status: PlanStatus.active,
      title: previous.snapshot.title,
      createdAt: previous.snapshot.createdAt,
      startDate: newStart,
      endDate: newEnd,
      goals: previous.snapshot.goals,
      days: shiftedDays,
      activeRevisionId: request.nextRevisionId,
      generationProvenance: previous.snapshot.generationProvenance,
      policyVersions: previous.snapshot.policyVersions,
    );

    final revision = PlanRevision(
      id: request.nextRevisionId,
      planId: previous.planId,
      number: previous.number + 1,
      createdAt: clock(),
      reason: PlanRevisionReason.learnerReschedule,
      snapshot: resumedSnapshot,
      previous: previous,
    );

    return ResumePracticePlanResult(
      revision: revision,
      resumeDate: request.resumeDate,
      pauseDate: request.pauseDate,
      gapDays: gapDays,
      crossedLongBreak: crossedLongBreak,
      pickedMode: pickedMode,
    );
  }

  void _validateResumable(PlanRevision previous) {
    if (previous.snapshot.status != PlanStatus.paused) {
      throw StateError(
        'Cannot resume a plan whose status is ${previous.snapshot.status.code}, '
        'expected paused',
      );
    }
  }

  void _validateOrder(ResumePracticePlanRequest request) {
    if (request.resumeDate.compareTo(request.pauseDate) <= 0) {
      throw ArgumentError.value(
        request.resumeDate,
        'resumeDate',
        'must be strictly after pauseDate ${request.pauseDate}',
      );
    }
  }
}

int _positive(int value, String name) {
  if (value < 1) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
  return value;
}

/// Proleptic Gregorian day ordinal. The exact epoch is irrelevant — only
/// the difference between two ordinals matters. The computation uses the
/// proleptic Gregorian rule (leap if divisible by 4, except when
/// divisible by 100, unless also divisible by 400). Mirrors the same
/// algorithm used in [WeeklyScheduleRequest] so two callers cannot
/// disagree on day counts.
int _dayOrdinal(LocalDate date) {
  final year = date.year;
  final month = date.month;
  final day = date.day;

  final previousYears = year - 1;
  final leapYearsBefore =
      (previousYears ~/ 4) - (previousYears ~/ 100) + (previousYears ~/ 400);
  final daysBeforeYear = 365 * previousYears + leapYearsBefore;

  const monthLengths = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  var daysBeforeMonth = 0;
  for (var m = 1; m < month; m++) {
    daysBeforeMonth += monthLengths[m - 1];
  }
  final isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
  if (month > 2 && isLeap) {
    daysBeforeMonth += 1;
  }

  return daysBeforeYear + daysBeforeMonth + (day - 1);
}

LocalDate _dateFromOrdinal(int ordinal) {
  // Inverse of [_dayOrdinal]. Standard proleptic Gregorian inverse:
  //   1. Estimate year from 365.2425-day average.
  //   2. Walk forward/backward to find the exact year whose day-of-year
  //      matches the remainder.
  //   3. Walk forward through months to find the exact month.
  //   4. Day = remainder + 1.
  var yearEstimate = (ordinal ~/ 365) + 1;
  // Adjust estimate so [_dayOrdinal](yearEstimate, 1, 1) <= ordinal.
  while (_dayOrdinal(LocalDate(yearEstimate, 1, 1)) > ordinal) {
    yearEstimate -= 1;
  }
  while (_dayOrdinal(LocalDate(yearEstimate + 1, 1, 1)) <= ordinal) {
    yearEstimate += 1;
  }
  final yearStartOrdinal = _dayOrdinal(LocalDate(yearEstimate, 1, 1));
  var dayOfYear = ordinal - yearStartOrdinal; // 0-indexed within the year.

  const monthLengths = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  final isLeap =
      (yearEstimate % 4 == 0 && yearEstimate % 100 != 0) ||
      yearEstimate % 400 == 0;
  final februaryLength = isLeap ? 29 : 28;

  var month = 1;
  while (month <= 12) {
    final length = month == 2 ? februaryLength : monthLengths[month - 1];
    if (dayOfYear < length) {
      break;
    }
    dayOfYear -= length;
    month += 1;
  }
  return LocalDate(yearEstimate, month, dayOfYear + 1);
}
