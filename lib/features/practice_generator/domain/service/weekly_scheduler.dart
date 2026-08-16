/// Deterministic week-level scheduling (SDD Ch8 Kör 15, ADR 0299).
///
/// The scheduler takes a [WeeklyScheduleRequest] — a [WeeklyAvailability],
/// the per-day [TimeBudget]s already allocated by the R14 allocator, the
/// candidate pool, an explicit `today`, optional rest days and an
/// optional song target date — and emits a [WeeklyScheduleDecision]
/// that records, for every day in the request, which candidates landed
/// there and which were deferred.
///
/// The scheduler is domain-pure (ADR 0299 §3):
///   * it never reads a clock — `today` is caller-supplied,
///   * it never generates randomness — every iteration uses the
///     stable sort key the [WeeklyScheduleRequest] constructor
///     produced,
///   * it never queries a repository, provider or generator,
///   * it never modifies the request or any of its inputs.
///
/// Algorithm (the §5 rules in implementation order):
///
///   1. Days are visited in chronological order (A8). Candidates are
///      visited in [ScheduleCandidate.sortKey] order (A6).
///   2. Rest days emit an empty decision carrying
///      [ScheduleDecisionReason.restDay]; unavailable days emit
///      [ScheduleDecisionReason.dayUnavailable]. Neither day carries
///      a candidate (A1, A3, ADR 0299 §4).
///   3. For each candidate the scheduler scans every available day in
///      chronological order. The first day that satisfies every rule
///      below wins; otherwise the candidate is deferred with the
///      first reason that ever blocked it.
///   4. Song-target phase gate (A5): a new-material candidate cannot
///      land on a day inside the [SchedulingPhase.lightReview] or
///      [SchedulingPhase.performance] window — only review candidates
///      qualify.
///   5. Per-day focus limit (A7): at most
///      [SchedulingPolicy.maximumPrimaryFocusPerDay] primary focus and
///      [SchedulingPolicy.maximumSecondaryFocusPerDay] secondary focus
///      candidates per day.
///   6. Day-budget gate: the candidate's duration must fit inside the
///      day's remaining [TimeBudget.activePlaying] minutes. The day
///      budget never has to be re-allocated — the R14 allocator already
///      owns that (ADR 0299 §2).
///   7. High-load run gate (A2, §6.1): a day may host at most one
///      high-load candidate, and the run of consecutive high-load days
///      may not exceed [SchedulingPolicy.maximumHighLoadRunDays]
///      (inclusive).
///   8. Bounded review ratio (A4): a review candidate may not push the
///      week's review-minute share above
///      [SchedulingPolicy.maximumReviewRatio].
///   9. When a candidate runs out of eligible days, a
///      [DeferredCandidate] is emitted with the first reason that
///      ever blocked it and the first day that did so.
library;

import '../model/schedule_decision.dart';
import '../model/weekly_availability.dart';
import '../policy/scheduling_policy.dart';

/// Deterministic week-level scheduling (SDD Ch8 Kör 15, ADR 0299).
final class WeeklyScheduler {
  const WeeklyScheduler({this.policy});

  /// The policy the scheduler uses for every decision. Tuning is done
  /// by constructing a new scheduler — the instance itself is
  /// immutable. When `null`, the scheduler falls back to
  /// [SchedulingPolicy.defaultPolicy].
  final SchedulingPolicy? policy;

  /// Build the deterministic weekly schedule for [request].
  WeeklyScheduleDecision schedule(WeeklyScheduleRequest request) {
    // The optional `policy` field is the public API for tuning; the
    // scheduler falls back to the default policy when the caller did
    // not supply one (ADR 0299 §3).
    final policy = this.policy ?? SchedulingPolicy.defaultPolicy;
    final weekDates = request.weekDates;
    if (weekDates.isEmpty) {
      throw ArgumentError.value(
        weekDates,
        'request.availability',
        'must contain at least one day',
      );
    }

    // Per-day mutable scratch state. The final DaySchedulingDecision
    // objects are built at the end from these snapshots.
    final hasSongTarget = request.songTargetDate != null;
    final dayStates = <LocalDate, _DayState>{};
    for (final date in weekDates) {
      final availability = request.availability.forDate(date)!;
      // When no song target was supplied, every day sits in the
      // [SchedulingPhase.none] band so the phase gate never rejects
      // candidates (ADR 0299 §1: the scheduler does not invent
      // song-target context). When a target is supplied, the phase
      // comes from the `target → date` distance so a future target
      // outside this week still drives a coherent taper window (F1).
      final phase = hasSongTarget
          ? policy.phaseForDayDistance(request.dayDistanceFromTarget(date))
          : SchedulingPhase.none;
      final isRest = request.restDays.contains(date);
      final isUnavailable = !availability.isAvailable;
      dayStates[date] = _DayState(
        phase: phase,
        isRest: isRest,
        isUnavailable: isUnavailable,
        activePlaying: (isRest || isUnavailable)
            ? Duration.zero
            : request.dayBudgets[date]!.activePlaying,
      );
    }

    // Track weekly aggregates the bounded-review-ratio gate needs.
    var weeklyReviewMicros = 0;
    var weeklyTotalMicros = 0;

    final deferred = <DeferredCandidate>[];

    for (final candidate in request.candidates) {
      _Trace? lastBlock;
      var placed = false;

      for (final date in weekDates) {
        final dayState = dayStates[date]!;

        // 2. Day-state gates (A1, A3).
        if (dayState.isRest) {
          lastBlock = _trace(ScheduleDecisionReason.restDay, date);
          continue;
        }
        if (dayState.isUnavailable) {
          lastBlock = _trace(ScheduleDecisionReason.dayUnavailable, date);
          continue;
        }

        // 4. Phase gate (A5).
        if ((dayState.phase == SchedulingPhase.lightReview ||
                dayState.phase == SchedulingPhase.performance) &&
            candidate.materialKind == CandidateMaterialKind.newMaterial) {
          lastBlock = _trace(ScheduleDecisionReason.phaseMismatch, date);
          continue;
        }

        // 5. Per-day focus limit (A7).
        if (candidate.focus == CandidateFocus.primaryFocus &&
            dayState.primaryFocusCount >= policy.maximumPrimaryFocusPerDay) {
          lastBlock = _trace(
            ScheduleDecisionReason.primaryFocusAlreadyAssigned,
            date,
          );
          continue;
        }
        if (candidate.focus == CandidateFocus.secondaryFocus &&
            dayState.secondaryFocusCount >=
                policy.maximumSecondaryFocusPerDay) {
          lastBlock = _trace(
            ScheduleDecisionReason.secondaryFocusAlreadyAssigned,
            date,
          );
          continue;
        }

        // 6. Day budget gate.
        if (dayState.usedMicros + candidate.duration.inMicroseconds >
            dayState.activePlaying.inMicroseconds) {
          lastBlock = _trace(ScheduleDecisionReason.dayBudgetExceeded, date);
          continue;
        }

        // 7. High-load run gate (A2, §6.1).
        if (candidate.loadLevel == SchedulingPolicy.highLoadLevel) {
          if (dayState.isHighLoad) {
            // The day already hosts a high-load candidate. Each day
            // counts as at most one high-load day in the run, so we
            // skip silently — the next candidate will try the next
            // day. The skip is not a rejection: only an explicit run
            // overflow becomes a [DeferredCandidate].
            continue;
          }
          final wouldBeRun = _wouldBeHighLoadRun(date, dayStates, weekDates);
          if (wouldBeRun > policy.maximumHighLoadRunDays) {
            lastBlock = _trace(
              ScheduleDecisionReason.highLoadRunSaturated,
              date,
            );
            continue;
          }
        }

        // 8. Bounded review ratio (A4).
        if (candidate.materialKind == CandidateMaterialKind.review) {
          final newReview =
              weeklyReviewMicros + candidate.duration.inMicroseconds;
          final newTotal =
              weeklyTotalMicros + candidate.duration.inMicroseconds;
          if (newTotal > 0 &&
              _ratio(newReview, newTotal) > policy.maximumReviewRatio) {
            lastBlock = _trace(
              ScheduleDecisionReason.reviewBudgetSaturated,
              date,
            );
            continue;
          }
        }

        // 9. Place the candidate.
        dayState.selected.add(candidate);
        dayState.usedMicros += candidate.duration.inMicroseconds;
        if (candidate.materialKind == CandidateMaterialKind.review) {
          weeklyReviewMicros += candidate.duration.inMicroseconds;
        }
        weeklyTotalMicros += candidate.duration.inMicroseconds;
        if (candidate.focus == CandidateFocus.primaryFocus) {
          dayState.primaryFocusCount += 1;
        }
        if (candidate.focus == CandidateFocus.secondaryFocus) {
          dayState.secondaryFocusCount += 1;
        }
        if (candidate.loadLevel == SchedulingPolicy.highLoadLevel) {
          dayState.isHighLoad = true;
        }
        placed = true;
        break;
      }

      if (!placed && lastBlock != null) {
        deferred.add(
          DeferredCandidate(
            date: lastBlock.date,
            candidate: candidate,
            reasonCode: lastBlock.reason.code,
          ),
        );
      }
    }

    // Build the per-day decisions in chronological order from the
    // scratch state snapshots.
    final decisions = <DaySchedulingDecision>[];
    for (final date in weekDates) {
      final state = dayStates[date]!;
      if (state.isRest) {
        decisions.add(
          DaySchedulingDecision(
            date: date,
            phase: state.phase,
            selectedCandidates: const <ScheduleCandidate>[],
            reasonCodes: <String>[ScheduleDecisionReason.restDay.code],
          ),
        );
        continue;
      }
      if (state.isUnavailable) {
        decisions.add(
          DaySchedulingDecision(
            date: date,
            phase: state.phase,
            selectedCandidates: const <ScheduleCandidate>[],
            reasonCodes: <String>[ScheduleDecisionReason.dayUnavailable.code],
          ),
        );
        continue;
      }
      if (state.selected.isEmpty) {
        decisions.add(
          DaySchedulingDecision(
            date: date,
            phase: state.phase,
            selectedCandidates: const <ScheduleCandidate>[],
            reasonCodes: <String>[ScheduleDecisionReason.dayUnavailable.code],
          ),
        );
        continue;
      }
      final reasons = <String>[
        ScheduleDecisionReason.selected.code,
        // Every day inside the song-target taper window (performance
        // or lightReview) is tagged with `lightReviewWindow` so the
        // audit log can group them without re-deriving the phase from
        // the today→target distance.
        if (state.phase == SchedulingPhase.lightReview ||
            state.phase == SchedulingPhase.performance)
          ScheduleDecisionReason.lightReviewWindow.code,
      ];
      decisions.add(
        DaySchedulingDecision(
          date: date,
          phase: state.phase,
          selectedCandidates: state.selected,
          reasonCodes: reasons,
        ),
      );
    }

    return WeeklyScheduleDecision(
      dayDecisions: decisions,
      deferredCandidates: deferred,
      policyVersion: policy.version,
      policy: policy,
    );
  }

  // -- helpers -----------------------------------------------------------

  static _Trace _trace(ScheduleDecisionReason reason, LocalDate date) =>
      _Trace(reason, date);

  /// The would-be run length for [date] *after* a high-load candidate
  /// is placed on it. Computed from the day-state snapshot — never
  /// mutates anything.
  ///
  /// When [date] is not yet a high-load day, the run is the length of
  /// the contiguous high-load prefix immediately preceding [date] plus
  /// one for the new day. When [date] is already a high-load day, the
  /// run at [date] is unchanged; this method is only called for the
  /// not-yet-high-load branch by the public algorithm.
  int _wouldBeHighLoadRun(
    LocalDate date,
    Map<LocalDate, _DayState> dayStates,
    List<LocalDate> weekDates,
  ) {
    final index = weekDates.indexOf(date);
    if (index == 0) return 1;
    final previous = dayStates[weekDates[index - 1]]!;
    if (!previous.isHighLoad) return 1;
    return _trailingHighLoadRun(weekDates[index - 1], dayStates, weekDates) + 1;
  }

  int _trailingHighLoadRun(
    LocalDate date,
    Map<LocalDate, _DayState> dayStates,
    List<LocalDate> weekDates,
  ) {
    var length = 0;
    var index = weekDates.indexOf(date);
    while (index >= 0) {
      final state = dayStates[weekDates[index]]!;
      if (!state.isHighLoad) break;
      length += 1;
      index -= 1;
    }
    return length;
  }

  double _ratio(int numerator, int denominator) {
    if (denominator == 0) return 0;
    return numerator / denominator;
  }
}

/// Mutable per-day scratch state owned by [WeeklyScheduler.schedule].
///
/// The class is intentionally package-private: callers only ever see
/// [DaySchedulingDecision], which the scheduler builds once per day
/// from the live state snapshot.
class _DayState {
  _DayState({
    required this.phase,
    required this.isRest,
    required this.isUnavailable,
    required this.activePlaying,
  });

  final SchedulingPhase phase;
  final bool isRest;
  final bool isUnavailable;
  final Duration activePlaying;
  final List<ScheduleCandidate> selected = <ScheduleCandidate>[];
  int usedMicros = 0;
  int primaryFocusCount = 0;
  int secondaryFocusCount = 0;
  bool isHighLoad = false;
}

/// A single (reason, date) record the scheduler observes while trying
/// to place a candidate.
class _Trace {
  _Trace(this.reason, this.date);
  final ScheduleDecisionReason reason;
  final LocalDate date;
}
