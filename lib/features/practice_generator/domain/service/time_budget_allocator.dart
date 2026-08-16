/// Deterministic day-level time allocation (SDD Ch8 Kör 14, ADR 0298).
///
/// The allocator splits one [DailyAvailability] into a [TimeBudget] whose
/// five typed amounts (`activePlaying`, `rest`, `setup`, `reflection`, and
/// the derived `elapsedSession`) sum exactly, while the planned
/// `segments` list accounts for the entire `activePlaying` portion. The
/// allocator:
///
/// 1. Clamps the requested total to the hard daily maximum (inclusive,
///    ADR 0298 §2).
/// 2. Chooses a [PlanTemplate] from the policy based on the clamped total.
/// 3. Reserves fixed minutes for setup, reflection, and the rest between
///    adjacent blocks.
/// 4. Fills the remaining active-playing minutes into the template's
///    slots. Every slot starts from its template minimum; the leftover
///    pool is split evenly across the slots, and the rounding remainder
///    is refunded to the slots in priority order (primary focus first,
///    then by template order). This is the "exact-budget repair" the
///    ADR 0298 §2 contract specifies.
/// 5. If the template's minimums cannot fit the available active minutes,
///    the allocator falls back to a single primary focus block carrying
///    the full active time — the safe overload that prevents
///    below-minimum fragments (brief §5.2).
/// 6. Surfaces the difference between the requested and the allocated
///    total — including the hard-maximum clamp — as a [PlanChange] with
///    `PlanChangeReason.systemAdaptation` provenance (ADR 0263 §4,
///    brief §5.6).
///
/// The allocator is domain-pure: no clock, no `Random`, no Flutter, no
/// global mutable state (ADR 0298 §5).
library;

import '../id/planner_ids.dart';
import '../model/plan_change_set.dart';
import '../model/plan_enums.dart';
import '../model/time_budget.dart';
import '../model/weekly_availability.dart';
import '../policy/time_allocation_policy.dart';

/// Why the allocator emitted (or did not emit) a [PlanChange].
///
/// A [PlanChange] is only generated when the allocator's decision differs
/// from the user's intent — i.e. the allocator shortened the day to fit a
/// hard maximum. An exactly-matching allocation reports
/// [TimeBudgetScaling.none].
enum TimeBudgetScaling {
  /// The allocation matched the requested total exactly.
  none('none'),

  /// The allocation is shorter than the user requested — the hard maximum
  /// trimmed the day.
  shortened('shortened');

  const TimeBudgetScaling(this.code);

  final String code;
}

/// The evidence code attached to a [PlanChange] surfaced by the allocator.
class TimeBudgetAllocationEvidence {
  TimeBudgetAllocationEvidence._();

  /// The hard daily maximum was lower than the requested total.
  static const String hardMaximumClamped = 'timeBudget.hardMaximumClamped';
}

/// The complete allocation outcome of one [TimeBudgetAllocator.allocate] call.
final class TimeBudgetAllocation {
  TimeBudgetAllocation({
    required this.budget,
    required this.requestedTotal,
    required this.hardMaximum,
    required this.scaling,
    required this.policy,
    required this.changeSet,
  });

  /// The resulting [TimeBudget] — always satisfies the sum invariant and
  /// never exceeds [hardMaximum].
  final TimeBudget budget;

  /// The total the caller asked for, in elapsed minutes.
  final Duration requestedTotal;

  /// The hard daily maximum the allocator clamped to.
  final Duration hardMaximum;

  /// Whether the allocation matches [requestedTotal] exactly.
  final TimeBudgetScaling scaling;

  /// The policy that produced this allocation. Retained for provenance.
  final TimeAllocationPolicy policy;

  /// The structured change set describing any scaling decision. Null when
  /// no scaling happened (the allocation matched the requested total
  /// exactly).
  final PlanChangeSet? changeSet;
}

/// Deterministic day-level time allocation (SDD Ch8 Kör 14, ADR 0298).
final class TimeBudgetAllocator {
  const TimeBudgetAllocator({TimeAllocationPolicy? policy})
    // The parameter and the field differ in name on purpose: the
    // parameter is the user-facing policy, the field is the storage.
    // ignore: prefer_initializing_formals
    : _policy = policy;

  /// The policy used to produce every allocation. Mutable tuning is
  /// achieved by constructing a new allocator — the instance itself is
  /// immutable.
  final TimeAllocationPolicy? _policy;

  TimeAllocationPolicy get policy =>
      _policy ?? TimeAllocationPolicy.defaultPolicy;

  /// Allocate one [TimeBudget] for a single daily session.
  ///
  /// The `availability` is the only learner input — its `maximumMinutes`
  /// plus `maximumStrength` together bound the allocation (ADR 0298 §2).
  /// `fromRevisionId`/`toRevisionId` are the revision identifiers the
  /// emitted [PlanChangeSet] connects (anonymous when no change is needed).
  TimeBudgetAllocation allocate({
    required DailyAvailability availability,
    required RevisionId fromRevisionId,
    required RevisionId toRevisionId,
    Duration? requestedTotal,
  }) {
    if (availability.status == AvailabilityStatus.unavailable) {
      throw ArgumentError.value(
        availability.status,
        'availability.status',
        'cannot allocate practice time for an unavailable day',
      );
    }
    final hardMaximum = Duration(minutes: availability.maximumMinutes);
    final asked =
        requestedTotal ?? Duration(minutes: availability.targetMinutes);
    if (asked <= Duration.zero) {
      throw ArgumentError.value(asked, 'requestedTotal', 'must be positive');
    }
    if (hardMaximum <= Duration.zero) {
      throw ArgumentError.value(
        hardMaximum,
        'hardMaximum',
        'must be positive for an available day',
      );
    }

    // 1. Clamp to the hard maximum (inclusive top, ADR 0298 §2).
    final clamped = asked > hardMaximum ? hardMaximum : asked;
    final scaling = _detectScaling(asked, clamped);

    // 2. Pick the template, then split.
    final template = policy.templateFor(clamped);
    final budget = _splitForTemplate(clamped, template);

    // 3. Surface the scaling decision as a typed change.
    final changeSet = _buildChangeSet(
      asked: asked,
      clamped: clamped,
      hardMaximum: hardMaximum,
      scaling: scaling,
      fromRevisionId: fromRevisionId,
      toRevisionId: toRevisionId,
    );

    return TimeBudgetAllocation(
      budget: budget,
      requestedTotal: asked,
      hardMaximum: hardMaximum,
      scaling: scaling,
      policy: policy,
      changeSet: changeSet,
    );
  }

  TimeBudgetScaling _detectScaling(Duration asked, Duration clamped) {
    if (asked > clamped) return TimeBudgetScaling.shortened;
    return TimeBudgetScaling.none;
  }

  TimeBudget _splitForTemplate(Duration total, PlanTemplate template) {
    final setup = Duration(minutes: template.setupMinutes);
    final reflection = Duration(minutes: template.reflectionMinutes);
    final restTotal = Duration(
      minutes: template.restPerGapMinutes * template.restGapCount,
    );
    final reserved = setup + reflection + restTotal;
    final activeAvailable = total - reserved;

    // Reserve ate the whole day or the template cannot fit — fall back to
    // a single primary focus carrying the entire requested total. This is
    // the safe overload the brief §5.2 fragment rule relies on.
    final totalMinimum = template.minimums.fold<int>(0, (a, b) => a + b);
    final activeMinutes = activeAvailable.inMinutes;
    if (activeAvailable <= Duration.zero || activeMinutes < totalMinimum) {
      return TimeBudget(
        activePlaying: total,
        rest: Duration.zero,
        setup: Duration.zero,
        reflection: Duration.zero,
        segments: <PlannedActiveSegment>[
          PlannedActiveSegment(kind: BlockKind.primaryFocus, duration: total),
        ],
      );
    }

    // 4. Allocate the active minutes into the template slots. Each slot
    // starts at its minimum; the pool above the minimums is split evenly,
    // and the remainder is refunded to the primary focus first then by
    // template order.
    final blocks = _allocateBlocks(activeMinutes, template);

    return TimeBudget(
      activePlaying: blocks.fold<Duration>(
        Duration.zero,
        (acc, block) => acc + block.duration,
      ),
      rest: restTotal,
      setup: setup,
      reflection: reflection,
      segments: blocks,
    );
  }

  List<PlannedActiveSegment> _allocateBlocks(
    int activeMinutes,
    PlanTemplate template,
  ) {
    final slots = template.orderedKinds.length;
    final totalMinimum = template.minimums.fold<int>(0, (a, b) => a + b);
    final pool = activeMinutes - totalMinimum;
    final perSlot = pool ~/ slots;
    final remainder = pool - perSlot * slots;

    // Priority order: primary focus first, then by template order.
    final order = _priorityOrder(template);
    final remainderTargets = <int>[];
    for (var i = 0; i < remainder; i++) {
      remainderTargets.add(order[i % order.length]);
    }

    final result = <PlannedActiveSegment>[];
    for (var i = 0; i < slots; i++) {
      final extraFromRemainder = _countFor(remainderTargets, i);
      final duration = template.minimums[i] + perSlot + extraFromRemainder;
      result.add(
        PlannedActiveSegment(
          kind: template.orderedKinds[i],
          duration: Duration(minutes: duration),
        ),
      );
    }
    return result;
  }

  List<int> _priorityOrder(PlanTemplate template) {
    final order = <int>[];
    var foundPrimary = false;
    for (var i = 0; i < template.orderedKinds.length; i++) {
      if (template.orderedKinds[i] == BlockKind.primaryFocus) {
        order.insert(0, i);
        foundPrimary = true;
      }
    }
    for (var i = 0; i < template.orderedKinds.length; i++) {
      if (template.orderedKinds[i] == BlockKind.primaryFocus) continue;
      order.add(i);
    }
    if (!foundPrimary) {
      // No primary focus in the template — fall back to lexical order.
      return [for (var i = 0; i < template.orderedKinds.length; i++) i];
    }
    return order;
  }

  int _countFor(List<int> targets, int index) {
    var count = 0;
    for (final target in targets) {
      if (target == index) count++;
    }
    return count;
  }

  PlanChangeSet? _buildChangeSet({
    required Duration asked,
    required Duration clamped,
    required Duration hardMaximum,
    required TimeBudgetScaling scaling,
    required RevisionId fromRevisionId,
    required RevisionId toRevisionId,
  }) {
    if (scaling == TimeBudgetScaling.none) return null;
    final change = PlanChange(
      type: PlanChangeType.updated,
      target: 'timeBudget',
      before: <String, Object?>{'requestedElapsedMicros': asked.inMicroseconds},
      after: <String, Object?>{
        'allocatedElapsedMicros': clamped.inMicroseconds,
        'hardMaximumMicros': hardMaximum.inMicroseconds,
      },
      reason: PlanChangeReason.systemAdaptation,
      evidenceRefs: <String>[TimeBudgetAllocationEvidence.hardMaximumClamped],
      confidence: 1.0,
      requiresUserConfirmation: false,
      reversible: false,
    );
    return PlanChangeSet(
      fromRevisionId: fromRevisionId,
      toRevisionId: toRevisionId,
      changes: <PlanChange>[change],
    );
  }
}
