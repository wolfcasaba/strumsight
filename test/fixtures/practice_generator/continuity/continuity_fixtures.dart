// E07-R27: shared fixtures for the missed-day policy and the pause/resume
// use-case tests.
//
// The fixtures are intentionally minimal — every observation just has
// the four fields the policy needs to classify the day. The test files
// own the assertions and the shape of the call.
import 'package:strumsight/features/practice_generator/public.dart';

/// Produces [count] consecutive missed-day observations ending the day
/// before [today]. The dates walk backwards from `today - 1 day` so a
/// 21-observation input ends at `today - 21`.
List<MissedDayObservation> continuityMissedObservations({
  required LocalDate startDate,
  required int count,
  required LocalDate today,
}) {
  assert(count >= 1, 'count must be positive');
  assert(
    startDate.compareTo(today) < 0,
    'startDate must be strictly before today',
  );
  return <MissedDayObservation>[
    for (var i = 0; i < count; i++)
      MissedDayObservation(
        localDate: _addDays(startDate, i),
        status: PracticeItemStatus.planned,
        reasonCodes: const <String>['goal.primary'],
        hasPrimaryFocus: true,
      ),
  ];
}

/// Produces one ready-to-pause revision built from the existing plan
/// fixture. The composition layer (caller) supplies the revision id
/// and the pause date.
PlanRevision continuityActiveRevision({
  AdaptivePracticePlan? snapshot,
  int number = 1,
}) {
  final planSnapshot =
      snapshot ??
      AdaptivePracticePlan(
        id: PlanId('plan.continuity'),
        schemaVersion: 1,
        status: PlanStatus.active,
        title: 'Continuity fixture plan',
        createdAt: DateTime.utc(2026, 8, 1),
        startDate: LocalDate(2026, 8, 1),
        endDate: LocalDate(2026, 8, 14),
        goals: const <PracticeGoal>[],
        days: const <PracticeDay>[],
        activeRevisionId: RevisionId('revision.$number'),
        generationProvenance: GenerationRequestId('request.continuity'),
        policyVersions: const <String, String>{},
      );
  return PlanRevision(
    id: RevisionId('revision.$number'),
    planId: planSnapshot.id,
    number: number,
    createdAt: DateTime.utc(2026, 8, 1),
    reason: PlanRevisionReason.initialGeneration,
    snapshot: planSnapshot,
  );
}

LocalDate _addDays(LocalDate date, int days) {
  // Proleptic Gregorian arithmetic without depending on the private
  // ordinal helper used by the use case. Months with fewer days wrap
  // over to the next month; leap-year rules match LocalDate's own
  // validation.
  var year = date.year;
  var month = date.month;
  var day = date.day + days;
  while (true) {
    final maxDay = _daysInMonth(year, month);
    if (day >= 1 && day <= maxDay) break;
    if (day > maxDay) {
      day -= maxDay;
      month += 1;
      if (month > 12) {
        month = 1;
        year += 1;
      }
    } else {
      day += _daysInMonth(year, month - 1 < 1 ? 12 : month - 1);
      month -= 1;
      if (month < 1) {
        month = 12;
        year -= 1;
      }
    }
  }
  return LocalDate(year, month, day);
}

int _daysInMonth(int year, int month) {
  const lengths = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month == 2) {
    final isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    return isLeap ? 29 : 28;
  }
  return lengths[month - 1];
}
