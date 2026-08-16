/// Shared, parameterizable builders for `WeeklyScheduler` /
/// `SchedulingPolicy` tests (E07-R15, §0.0).
///
/// Every builder is a thin wrapper over the already-validated
/// `public.dart` domain constructors — no domain decision lives here,
/// only fixture assembly.
library;

import 'package:strumsight/features/practice_generator/public.dart';

/// Build a [DailyAvailability] for a given date with the supplied
/// maximum minutes. Default is `available` with a 45-minute day.
DailyAvailability buildDayAvailability({
  required LocalDate date,
  int maximumMinutes = 45,
  int? targetMinutes,
  int minimumMinutes = 0,
  AvailabilityStatus status = AvailabilityStatus.available,
  ConstraintStrength maximumStrength = ConstraintStrength.hard,
}) => DailyAvailability(
  date: date,
  status: status,
  minimumMinutes: minimumMinutes,
  targetMinutes: targetMinutes ?? maximumMinutes,
  maximumMinutes: maximumMinutes,
  maximumStrength: maximumStrength,
  softExcessMinuteCost: maximumStrength == ConstraintStrength.soft ? 1 : 0,
);

/// Build a [WeeklyAvailability] of `count` consecutive days starting
/// at [start].
WeeklyAvailability buildWeek({
  required LocalDate start,
  required int count,
  int maximumMinutes = 45,
  Set<LocalDate>? unavailableDates,
}) {
  final days = <DailyAvailability>[];
  for (var offset = 0; offset < count; offset++) {
    final date = _addDays(start, offset);
    final isUnavailable = unavailableDates?.contains(date) ?? false;
    days.add(
      buildDayAvailability(
        date: date,
        maximumMinutes: maximumMinutes,
        status: isUnavailable
            ? AvailabilityStatus.unavailable
            : AvailabilityStatus.available,
      ),
    );
  }
  return WeeklyAvailability(days);
}

WeeklyAvailability buildWeekWithRest({
  required LocalDate start,
  required int count,
  required Set<LocalDate> restDays,
  int maximumMinutes = 45,
}) {
  final days = <DailyAvailability>[];
  for (var offset = 0; offset < count; offset++) {
    final date = _addDays(start, offset);
    days.add(buildDayAvailability(date: date, maximumMinutes: maximumMinutes));
  }
  final availability = WeeklyAvailability(days);
  final budgets = <LocalDate, TimeBudget>{};
  for (final day in availability.days) {
    if (restDays.contains(day.date)) continue;
    budgets[day.date] = TimeBudget(
      activePlaying: const Duration(minutes: 30),
      rest: const Duration(minutes: 5),
      setup: const Duration(minutes: 5),
      reflection: const Duration(minutes: 5),
    );
  }
  // The constructor call below uses the budgets we already built; we
  // rebuild the request to thread the restDays in.
  return availability;
}

/// Build a 45-minute pre-allocated [TimeBudget] that the scheduler
/// can spend across candidates. The five typed fields match the R14
/// default.
TimeBudget buildBudget({int activeMinutes = 30}) => TimeBudget(
  activePlaying: Duration(minutes: activeMinutes),
  rest: const Duration(minutes: 5),
  setup: const Duration(minutes: 5),
  reflection: const Duration(minutes: 5),
);

/// Build a map of per-day [TimeBudget] matching the supplied
/// [WeeklyAvailability]. Rest days and unavailable days are skipped
/// (the request validator requires their absence).
Map<LocalDate, TimeBudget> buildBudgetsForWeek(
  WeeklyAvailability availability, {
  int activeMinutes = 30,
  int? unavailableActiveMinutes,
}) {
  final budgets = <LocalDate, TimeBudget>{};
  for (final day in availability.days) {
    if (!day.isAvailable) continue;
    budgets[day.date] = buildBudget(
      activeMinutes: unavailableActiveMinutes ?? activeMinutes,
    );
  }
  return budgets;
}

/// Build a [ScheduleCandidate] with the supplied parameters. The
/// `identity` defaults to `'practiceCatalog:<counter>:<revision>'` so
/// callers do not have to invent stable keys.
ScheduleCandidate buildCandidate({
  required String identity,
  CandidateFocus focus = CandidateFocus.primaryFocus,
  CandidateMaterialKind materialKind = CandidateMaterialKind.newMaterial,
  LoadLevel loadLevel = LoadLevel.medium,
  int durationMinutes = 10,
}) => ScheduleCandidate(
  identity: identity,
  focus: focus,
  materialKind: materialKind,
  loadLevel: loadLevel,
  duration: Duration(minutes: durationMinutes),
);

/// Build a [WeeklyScheduleRequest] from the supplied parts, with the
/// rest days supplied via `restDays` and the budgets already built.
WeeklyScheduleRequest buildRequest({
  required WeeklyAvailability availability,
  required Map<LocalDate, TimeBudget> budgets,
  required Iterable<ScheduleCandidate> candidates,
  required LocalDate today,
  Set<LocalDate>? restDays,
  LocalDate? songTargetDate,
}) => WeeklyScheduleRequest(
  availability: availability,
  dayBudgets: budgets,
  candidates: candidates,
  today: today,
  restDays: restDays,
  songTargetDate: songTargetDate,
);

/// Build a three-day week starting at [start] with a 45-minute
/// availability per day and a per-day budget that allows up to 30
/// active minutes.
({WeeklyAvailability availability, Map<LocalDate, TimeBudget> budgets})
buildThreeDayWeek(
  LocalDate start, {
  Set<LocalDate>? unavailableDates,
  int activeMinutes = 30,
}) {
  final availability = buildWeek(
    start: start,
    count: 3,
    maximumMinutes: 45,
    unavailableDates: unavailableDates,
  );
  final budgets = buildBudgetsForWeek(
    availability,
    activeMinutes: activeMinutes,
  );
  return (availability: availability, budgets: budgets);
}

/// Build a seven-day week starting at [start].
({WeeklyAvailability availability, Map<LocalDate, TimeBudget> budgets})
buildSevenDayWeek(
  LocalDate start, {
  Set<LocalDate>? unavailableDates,
  int activeMinutes = 30,
}) {
  final availability = buildWeek(
    start: start,
    count: 7,
    maximumMinutes: 45,
    unavailableDates: unavailableDates,
  );
  final budgets = buildBudgetsForWeek(
    availability,
    activeMinutes: activeMinutes,
  );
  return (availability: availability, budgets: budgets);
}

LocalDate _addDays(LocalDate start, int days) {
  // Conservative date math that survives month/year rollovers without
  // depending on DateTime. The scheduler tests only need a handful of
  // consecutive dates — anything more elaborate should use DateTime.
  final monthLengths = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  var year = start.year;
  var month = start.month;
  var day = start.day + days;
  while (true) {
    final isLeap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    final length = month == 2 && isLeap ? 29 : monthLengths[month - 1];
    if (day <= length) break;
    day -= length;
    month += 1;
    if (month > 12) {
      month = 1;
      year += 1;
    }
  }
  while (day <= 0) {
    month -= 1;
    if (month <= 0) {
      month = 12;
      year -= 1;
    }
    final isLeap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    final length = month == 2 && isLeap ? 29 : monthLengths[month - 1];
    day += length;
  }
  return LocalDate(year, month, day);
}
