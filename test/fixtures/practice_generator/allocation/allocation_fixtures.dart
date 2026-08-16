/// Shared, parameterizable builders for `TimeBudgetAllocator` /
/// `TimeAllocationPolicy` tests (E07-R14, §0.0).
///
/// Every builder is a thin wrapper over the already-validated
/// `public.dart` domain constructors — no domain decision lives here, only
/// fixture assembly.
library;

import 'package:strumsight/features/practice_generator/public.dart';

/// The revision identifiers used when the allocator threads a change set
/// through the change-set contract. They are intentionally distinct, as
/// `PlanChangeSet` rejects matching revisions.
final allocationFromRevisionId = RevisionId('allocation.revision.0');
final allocationToRevisionId = RevisionId('allocation.revision.1');

/// Builds a [DailyAvailability] with the supplied maximum minutes and
/// strength. The date is fixed so the produced availability is identity-
/// stable across runs.
DailyAvailability buildAvailability({
  int maximumMinutes = 20,
  ConstraintStrength maximumStrength = ConstraintStrength.hard,
  AvailabilityStatus status = AvailabilityStatus.available,
  int minimumMinutes = 0,
  int? targetMinutes,
  LocalDate? date,
  int softExcessMinuteCost = 0,
}) => DailyAvailability(
  date: date ?? LocalDate(2026, 8, 16),
  status: status,
  minimumMinutes: minimumMinutes,
  targetMinutes: targetMinutes ?? maximumMinutes,
  maximumMinutes: maximumMinutes,
  maximumStrength: maximumStrength,
  softExcessMinuteCost: maximumStrength == ConstraintStrength.soft
      ? (softExcessMinuteCost == 0 ? 1 : softExcessMinuteCost)
      : 0,
);

/// Runs the [TimeBudgetAllocator] with the supplied inputs and returns the
/// [TimeBudgetAllocation] — every test assembles inputs via the same
/// builder so the cell assertions stay focused on the contract.
TimeBudgetAllocation runAllocation({
  Duration? requestedTotal,
  int maximumMinutes = 20,
  ConstraintStrength maximumStrength = ConstraintStrength.hard,
  TimeAllocationPolicy? policy,
  RevisionId? fromRevisionId,
  RevisionId? toRevisionId,
}) {
  final allocator = TimeBudgetAllocator(
    policy: policy ?? TimeAllocationPolicy.defaultPolicy,
  );
  return allocator.allocate(
    availability: buildAvailability(
      maximumMinutes: maximumMinutes,
      maximumStrength: maximumStrength,
    ),
    requestedTotal: requestedTotal,
    fromRevisionId: fromRevisionId ?? allocationFromRevisionId,
    toRevisionId: toRevisionId ?? allocationToRevisionId,
  );
}
