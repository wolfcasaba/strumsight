/// Immutable input/output contract for the [WeeklyScheduler]
/// (ADR 0299, SDD Ch8 Kör 15).
///
/// The scheduler is domain-pure: it does not read a clock, it does not
/// generate randomness, and every input is caller-supplied. The
/// scheduler's input is the [WeeklyScheduleRequest] — a [WeeklyAvailability],
/// the per-day [TimeBudget] already allocated by the R14 allocator, the
/// set of [ScheduleCandidate]s to place, an explicit `today`, optional
/// rest days, and an optional song target date. The output is a
/// [WeeklyScheduleDecision] that records, for every day in the request,
/// which candidates landed there and which were deferred — with a typed
/// reason and the policy provenance the scheduler used.
///
/// All lists inside the result are sorted by a stable key so the same
/// inputs always produce the same decision bytes (A6/A8).
library;

import '../policy/scheduling_policy.dart';
import 'exercise_candidate.dart';
import 'time_budget.dart';
import 'weekly_availability.dart';

/// A normalized, executable candidate for the week-level scheduler.
///
/// The scheduler reads the [focus], [materialKind] and [loadLevel] to
/// decide where to place the candidate. The [identity] is the stable
/// sort key — it is unique per candidate so the scheduler can sort a
/// large candidate pool deterministically without inspecting the rest
/// of the type.
final class ScheduleCandidate {
  ScheduleCandidate({
    required String identity,
    required this.focus,
    required this.materialKind,
    required this.loadLevel,
    required Duration duration,
    Iterable<String>? skillTargets,
  }) : identity = _requireText(identity, 'identity'),
       duration = _requireNonNegativeDuration(duration, 'duration'),
       skillTargets = List<String>.unmodifiable([
         for (final value in (skillTargets ?? const <String>[]))
           _requireText(value, 'skillTargets'),
       ]) {
    if (duration <= Duration.zero) {
      throw ArgumentError.value(
        duration,
        'duration',
        'must be positive (no zero-minute candidate)',
      );
    }
  }

  /// Stable, unique identifier (e.g. `'source:exerciseId:contentRevision'`).
  /// Two candidates must not share an identity in the same request — the
  /// scheduler would silently drop one and the audit log would lose
  /// provenance.
  final String identity;

  /// The relative pedagogical weight this candidate carries.
  final CandidateFocus focus;

  /// Whether the candidate introduces new material or only reviews
  /// previously learned content.
  final CandidateMaterialKind materialKind;

  /// The load the candidate adds to the day. Drives the high-load-run
  /// protection (A2, §6.1).
  final LoadLevel loadLevel;

  /// The planned active minutes for the candidate. Must fit inside
  /// the day's `TimeBudget.activePlaying` (ADR 0299 §2).
  final Duration duration;

  /// Optional, sorted skill targets — useful for diagnostics and
  /// stable tie-breaks when two candidates share the same
  /// [identity]-prefixed key.
  final List<String> skillTargets;

  /// Stable lexical sort key used by the scheduler to traverse the
  /// candidate pool in a deterministic order.
  String get sortKey => identity;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduleCandidate &&
          other.identity == identity &&
          other.focus == focus &&
          other.materialKind == materialKind &&
          other.loadLevel == loadLevel &&
          other.duration == duration &&
          _sameList(other.skillTargets, skillTargets);

  @override
  int get hashCode => Object.hash(
    identity,
    focus,
    materialKind,
    loadLevel,
    duration,
    Object.hashAll(skillTargets),
  );
}

/// The input contract for the [WeeklyScheduler].
///
/// The request bundles every piece of state the scheduler reads. The
/// scheduler does not query any repository, provider, clock, or
/// generator — it works only with what is passed in. The construction
/// validates the request fail-closed (ADR 0299 §2): every budget day
/// must be present in the availability, every budget must fit its
/// day's hard maximum, rest days must not carry a budget, and there
/// must be at least one available day.
final class WeeklyScheduleRequest {
  WeeklyScheduleRequest({
    required this.availability,
    required Map<LocalDate, TimeBudget> dayBudgets,
    required Iterable<ScheduleCandidate> candidates,
    required this.today,
    Iterable<LocalDate>? restDays,
    this.songTargetDate,
  }) : dayBudgets = _validateBudgets(
         availability: availability,
         dayBudgets: dayBudgets,
         restDays: restDays,
       ),
       candidates = List<ScheduleCandidate>.unmodifiable(
         _dedupeAndSort(candidates, 'candidates'),
       ),
       restDays = _normaliseRestDays(
         availability,
         restDays ?? const <LocalDate>[],
       ) {
    final dates = <LocalDate>[];
    for (final day in availability.days) {
      dates.add(day.date);
    }
    // Canonicalise the walking order to chronological via
    // [LocalDate.compareTo] so non-sorted `availability.days` input
    // still produces a deterministic, chronological walk (F3, A6/A8).
    dates.sort((left, right) => left.compareTo(right));
    _weekDates = List<LocalDate>.unmodifiable(dates);
    _validateSongTarget();
  }

  /// The week's availability (R03). The scheduler respects its
  /// per-day status and maximum minutes (A1, A8).
  final WeeklyAvailability availability;

  /// The per-day time budgets, pre-allocated by the R14 allocator.
  /// The scheduler never re-allocates these and never reads the
  /// allocator's [TimeAllocationPolicy].
  final Map<LocalDate, TimeBudget> dayBudgets;

  /// The candidate pool the scheduler may place on the week. Sorted
  /// by [ScheduleCandidate.sortKey] so the order is stable (A6).
  final List<ScheduleCandidate> candidates;

  /// The local date the scheduler treats as "today". Explicit, so
  /// the scheduler never reads a clock (ADR 0299 §1).
  final LocalDate today;

  /// Local dates explicitly marked as rest. These days are emitted
  /// as empty decisions — no candidate is placed (A3, ADR 0299 §4).
  final Set<LocalDate> restDays;

  /// The optional song target date. When set, the scheduler derives
  /// each day's [SchedulingPhase] from the `today`-to-`target` distance
  /// (ADR 0299 §5). The target date itself falls inside the
  /// [SchedulingPhase.performance] window — only review candidates may
  /// land on it.
  final LocalDate? songTargetDate;

  /// The ordered, sorted list of dates the scheduler will emit
  /// decisions for. Computed once at construction time, canonicalised
  /// by [LocalDate.compareTo] so non-sorted `availability.days`
  /// input still produces a deterministic, chronological walk (A8).
  late final List<LocalDate> _weekDates;

  /// The days the scheduler will emit decisions for, in chronological
  /// order (A8).
  List<LocalDate> get weekDates => _weekDates;

  /// The sign-preserving number of calendar days between `today` and
  /// `date`. Positive when `date` is after `today`, zero on `today`,
  /// negative before. The value is the true Gregorian day count, so
  /// it survives month/year rollovers and the leap-year rule (F2).
  int dayDistanceFromToday(LocalDate date) =>
      _dayOrdinal(date) - _dayOrdinal(today);

  /// The sign-preserving number of calendar days between the song
  /// [songTargetDate] and `date`. Positive when `date` is after the
  /// target, zero on the target, negative before. Falls back to
  /// [dayDistanceFromToday] when no song target is set so the helper
  /// is always callable; the scheduler uses it to derive each day's
  /// [SchedulingPhase] from the actual `target → date` gap, not from
  /// `today → date` (F1).
  int dayDistanceFromTarget(LocalDate date) {
    final target = songTargetDate;
    if (target == null) return dayDistanceFromToday(date);
    return _dayOrdinal(date) - _dayOrdinal(target);
  }

  /// The days-since-proleptic-Gregorian-epoch ordinal. The exact epoch
  /// is irrelevant — only the difference between two ordinals matters.
  /// The computation uses the proleptic Gregorian rule:
  /// leap if divisible by 4, except when divisible by 100, unless
  /// also divisible by 400. So `2026-01-31 → 2026-02-01` is `+1`,
  /// `2026-12-31 → 2027-01-01` is `+1`, and `2024-02-28 → 2024-03-01`
  /// is `+2` (2024 is a leap year).
  static int _dayOrdinal(LocalDate date) {
    final year = date.year;
    final month = date.month;
    final day = date.day;

    // Days in the years strictly before `year`.
    final previousYears = year - 1;
    final leapYearsBefore =
        (previousYears ~/ 4) - (previousYears ~/ 100) + (previousYears ~/ 400);
    final daysBeforeYear = 365 * previousYears + leapYearsBefore;

    // Days in the months strictly before `month` of `year`.
    const monthLengths = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    var daysBeforeMonth = 0;
    for (var m = 1; m < month; m++) {
      daysBeforeMonth += monthLengths[m - 1];
    }
    final isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    if (month > 2 && isLeap) {
      daysBeforeMonth += 1;
    }

    // Days within the month, zero-indexed.
    return daysBeforeYear + daysBeforeMonth + (day - 1);
  }

  void _validateSongTarget() {
    // The song target may sit outside the weekly availability — it is
    // the calendar anchor for the taper window, not a day in this
    // week. The only hard invariant is that a target, when supplied,
    // must be a valid [LocalDate] (the constructor already enforces
    // this). The distance computation handles out-of-week targets
    // natively (F1).
  }

  static Map<LocalDate, TimeBudget> _validateBudgets({
    required WeeklyAvailability availability,
    required Map<LocalDate, TimeBudget> dayBudgets,
    required Iterable<LocalDate>? restDays,
  }) {
    final restSet = restDays == null ? const <LocalDate>{} : restDays.toSet();
    final result = <LocalDate, TimeBudget>{};
    for (final day in availability.days) {
      final date = day.date;
      // A1 zero-availability rule: an unavailable day carries no budget
      // — the scheduler still emits a dayUnavailable decision but does
      // not require the caller to pre-allocate minutes for it.
      if (!day.isAvailable) continue;
      final budget = dayBudgets[date];
      if (restSet.contains(date)) {
        if (budget != null) {
          throw ArgumentError.value(
            date,
            'dayBudgets',
            'rest day $date must not carry a budget',
          );
        }
        continue;
      }
      if (budget == null) {
        throw ArgumentError.value(
          date,
          'dayBudgets',
          'available day $date is missing its pre-allocated TimeBudget',
        );
      }
      final maxMicros = day.maximumMinutes * Duration.microsecondsPerMinute;
      if (budget.elapsedSession.inMicroseconds > maxMicros) {
        throw ArgumentError.value(
          budget.elapsedSession,
          'dayBudgets[$date]',
          'exceeds availability maximumMinutes (${day.maximumMinutes})',
        );
      }
      result[date] = budget;
    }
    return Map<LocalDate, TimeBudget>.unmodifiable(result);
  }

  static List<ScheduleCandidate> _dedupeAndSort(
    Iterable<ScheduleCandidate> input,
    String name,
  ) {
    final seen = <String>{};
    final list = <ScheduleCandidate>[];
    for (final candidate in input) {
      if (!seen.add(candidate.identity)) {
        throw ArgumentError.value(
          candidate.identity,
          name,
          'contains duplicate candidate identity',
        );
      }
      list.add(candidate);
    }
    list.sort((left, right) => left.sortKey.compareTo(right.sortKey));
    return list;
  }

  static Set<LocalDate> _normaliseRestDays(
    WeeklyAvailability availability,
    Iterable<LocalDate> restDays,
  ) {
    final availabilityDates = {for (final day in availability.days) day.date};
    final result = <LocalDate>{};
    for (final date in restDays) {
      if (!availabilityDates.contains(date)) {
        throw ArgumentError.value(
          date,
          'restDays',
          'must reference a date in the availability',
        );
      }
      result.add(date);
    }
    return Set<LocalDate>.unmodifiable(result);
  }
}

/// One per-day scheduling decision.
///
/// The decision lists the candidates the scheduler placed on the day
/// (in stable insertion order — by [ScheduleCandidate.sortKey] and
/// then by insertion), every typed reason the scheduler surfaced for
/// the day, the total active minutes the placed candidates consume,
/// and the song-target [SchedulingPhase] the day falls into.
final class DaySchedulingDecision {
  DaySchedulingDecision({
    required this.date,
    required this.phase,
    required Iterable<ScheduleCandidate> selectedCandidates,
    required Iterable<String> reasonCodes,
  }) : selectedCandidates = List<ScheduleCandidate>.unmodifiable(
         selectedCandidates,
       ),
       reasonCodes = List<String>.unmodifiable(reasonCodes),
       totalActiveMinutes = _requireValidDecision(
         reasonCodes,
         selectedCandidates,
       );

  /// The local date the decision is for.
  final LocalDate date;

  /// The song-target phase the day falls into (ADR 0299 §5). Always
  /// [SchedulingPhase.none] when no song target was supplied.
  final SchedulingPhase phase;

  /// The candidates the scheduler placed on the day, in stable
  /// insertion order.
  final List<ScheduleCandidate> selectedCandidates;

  /// The typed reason codes the scheduler surfaced for the day
  /// (selected/deferred/day-empty). Sorted lexically so the decision
  /// bytes are deterministic (A6).
  final List<String> reasonCodes;

  /// The total active minutes the placed candidates occupy.
  final Duration totalActiveMinutes;

  /// `true` when no candidate landed on the day (rest day,
  /// unavailable day, or no eligible candidate fit).
  bool get isEmpty => selectedCandidates.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DaySchedulingDecision &&
          other.date == date &&
          other.phase == phase &&
          _sameList(other.selectedCandidates, selectedCandidates) &&
          _sameList(other.reasonCodes, reasonCodes);

  @override
  int get hashCode => Object.hash(
    date,
    phase,
    Object.hashAll(selectedCandidates),
    Object.hashAll(reasonCodes),
  );
}

/// One deferred candidate — a candidate the request supplied but the
/// scheduler did not place. The decision is the audit trail the
/// scheduler returns so the caller can show the learner why a known
/// candidate was held back.
final class DeferredCandidate {
  DeferredCandidate({
    required this.date,
    required this.candidate,
    required String reasonCode,
  }) : reasonCode = _requireCode(reasonCode, 'reasonCode');

  /// The day the candidate was considered for. When the candidate was
  /// never eligible at all (e.g. new material inside the light-review
  /// window), the date is the first day of the request — the scheduler
  /// reports the global deferral once.
  final LocalDate date;

  /// The candidate that was deferred.
  final ScheduleCandidate candidate;

  /// The typed reason code from [ScheduleDecisionReason].
  final String reasonCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeferredCandidate &&
          other.date == date &&
          other.candidate == candidate &&
          other.reasonCode == reasonCode;

  @override
  int get hashCode => Object.hash(date, candidate, reasonCode);
}

/// The full immutable outcome of one `WeeklyScheduler.schedule` call.
///
/// `dayDecisions` covers every day in the request's availability,
/// including rest and unavailable days (their decisions carry the
/// matching `restDay` / `dayUnavailable` reason code and an empty
/// `selectedCandidates` list). `deferredCandidates` lists every
/// candidate the scheduler considered but did not place. The
/// `policyVersion` field carries the [SchedulingPolicy.version] the
/// scheduler used so reviewers can audit tuning changes.
final class WeeklyScheduleDecision {
  WeeklyScheduleDecision({
    required Iterable<DaySchedulingDecision> dayDecisions,
    required Iterable<DeferredCandidate> deferredCandidates,
    required String policyVersion,
    required this.policy,
  }) : dayDecisions = List<DaySchedulingDecision>.unmodifiable(
         _sortDayDecisions(dayDecisions),
       ),
       deferredCandidates = List<DeferredCandidate>.unmodifiable(
         _sortDeferred(deferredCandidates),
       ),
       policyVersion = _requireText(policyVersion, 'policyVersion') {
    if (policyVersion != policy.version) {
      throw ArgumentError.value(
        policyVersion,
        'policyVersion',
        'must match policy.version (${policy.version})',
      );
    }
  }

  /// The day decisions, in chronological order. Every day in the
  /// request's availability is present.
  final List<DaySchedulingDecision> dayDecisions;

  /// The deferred candidates, sorted by date then by candidate
  /// identity then by reason code (A6).
  final List<DeferredCandidate> deferredCandidates;

  /// The policy version the scheduler used.
  final String policyVersion;

  /// The policy the scheduler used, retained for provenance.
  final SchedulingPolicy policy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeeklyScheduleDecision &&
          _sameList(other.dayDecisions, dayDecisions) &&
          _sameList(other.deferredCandidates, deferredCandidates) &&
          other.policyVersion == policyVersion &&
          other.policy == policy;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(dayDecisions),
    Object.hashAll(deferredCandidates),
    policyVersion,
    policy,
  );
}

List<DaySchedulingDecision> _sortDayDecisions(
  Iterable<DaySchedulingDecision> input,
) {
  final list = input.toList()
    ..sort((left, right) => left.date.compareTo(right.date));
  return list;
}

List<DeferredCandidate> _sortDeferred(Iterable<DeferredCandidate> input) {
  final list = input.toList()
    ..sort((left, right) {
      final dateCompare = left.date.compareTo(right.date);
      if (dateCompare != 0) return dateCompare;
      final identityCompare = left.candidate.identity.compareTo(
        right.candidate.identity,
      );
      if (identityCompare != 0) return identityCompare;
      return left.reasonCode.compareTo(right.reasonCode);
    });
  return list;
}

bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Duration _requireValidDecision(
  Iterable<String> reasonCodes,
  Iterable<ScheduleCandidate> selectedCandidates,
) {
  if (reasonCodes.isEmpty) {
    throw ArgumentError.value(
      reasonCodes,
      'reasonCodes',
      'must include at least one entry (use schedule.decision.restDay or '
          'schedule.decision.dayUnavailable for empty days)',
    );
  }
  final seen = <String>{};
  var totalMicros = 0;
  for (final candidate in selectedCandidates) {
    if (!seen.add(candidate.identity)) {
      throw ArgumentError.value(
        candidate.identity,
        'selectedCandidates',
        'must not contain duplicates',
      );
    }
    totalMicros += candidate.duration.inMicroseconds;
  }
  return Duration(microseconds: totalMicros);
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}

String _requireCode(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}

Duration _requireNonNegativeDuration(Duration value, String name) {
  if (value.isNegative) {
    throw ArgumentError.value(value, name, 'must not be negative');
  }
  return value;
}
