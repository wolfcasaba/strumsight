/// Deterministic day-level time allocation (SDD Ch8 Kör 14, ADR 0298).
///
/// The allocator splits one [DailyAvailability] into a [TimeBudget] whose
/// five typed amounts (`activePlaying`, `rest`, `setup`, `reflection`, and
/// the derived `elapsedSession`) sum exactly, while the planned
/// `segments` list accounts for the entire `activePlaying` portion. The
/// allocator:
///
/// 1. Clamps the requested total to the hard daily maximum (inclusive,
///    ADR 0298 §2). The clamp surfaces as `TimeBudgetScaling.shortened`.
/// 2. When the planned single-day ceiling (`policy.ceilingMinutes`) is
///    smaller than the requested total but still within the hard maximum,
///    the day is shortened to the ceiling — the same [shortened]
///    scaling, a distinct evidence code, and the same `systemAdaptation`
///    reason (ADR 0298 decision 4).
/// 3. When the caller opts into `extendToday` and the requested total is
///    below the effective upper bound (`min(hardMaximum, ceilingCap)`),
///    the day is extended to that bound. The extension is surfaced as
///    [TimeBudgetScaling.extended] with the matching evidence code.
/// 4. Chooses a [PlanTemplate] from the policy based on the resolved
///    total.
/// 5. Reserves fixed minutes for setup, reflection, and the rest between
///    adjacent blocks.
/// 6. Fills the remaining active-playing minutes into the template's
///    slots. Every slot starts from its template minimum; the leftover
///    pool is split evenly across the slots, and the per-slot minutes are
///    floor-rounded to `policy.roundingIncrement`. The rounding loss is
///    refunded to the slots in priority order (primary focus first, then
///    by template order) so the sum stays exact and the hard maximum is
///    never crossed.
/// 7. If the template's minimums cannot fit the available active minutes,
///    the allocator falls back to a single primary focus block carrying
///    the full active time — the safe overload that prevents
///    below-minimum fragments (brief §5.2).
/// 8. Surfaces every shortened or extended decision as a [PlanChange]
///    with `PlanChangeReason.systemAdaptation` provenance (ADR 0263 §4,
///    brief §5.6).
///
/// The allocator is domain-pure: no clock, no `Random`, no Flutter, no
/// global mutable state (ADR 0298 §5). Every input the allocator reads is
/// caller-supplied; the `extendToday` flag in particular lets the caller
/// distinguish a learner request from a system extension.
library;

import '../id/planner_ids.dart';
import '../model/plan_change_set.dart';
import '../model/plan_enums.dart';
import '../model/time_budget.dart';
import '../model/weekly_availability.dart';
import '../policy/time_allocation_policy.dart';

/// Why the allocator emitted (or did not emit) a [PlanChange].
///
/// A [PlanChange] is generated when the allocator's decision differs from
/// the user's intent — i.e. the allocator shortened the day to fit a hard
/// maximum (or the planned ceiling) or extended the day because the
/// caller opted into the system adaptation. An exactly-matching allocation
/// reports [TimeBudgetScaling.none].
enum TimeBudgetScaling {
  /// The allocation matched the requested total exactly.
  none('none'),

  /// The allocation is shorter than the user requested — either the hard
  /// daily maximum or the planned single-day ceiling trimmed the day.
  shortened('shortened'),

  /// The allocation is longer than the user requested — the caller opted
  /// into extending the day (ADR 0298 decision 4, brief §5.6).
  extended('extended');

  const TimeBudgetScaling(this.code);

  final String code;
}

/// The evidence codes attached to a [PlanChange] surfaced by the allocator.
///
/// Every evidence code is a stable, alphanumeric identifier so the
/// downstream layer can match it against the policy / availability
/// artefacts without parsing free-text fields.
class TimeBudgetAllocationEvidence {
  TimeBudgetAllocationEvidence._();

  /// The hard daily maximum was lower than the requested total.
  static const String hardMaximumClamped = 'timeBudget.hardMaximumClamped';

  /// The learner opted into extending the day, and the allocator grew the
  /// day to the effective upper bound (`min(hardMaximum,
  /// policy.ceilingMinutes)`).
  static const String extendedToAvailable = 'timeBudget.extendedToAvailable';

  /// The planned single-day ceiling (`policy.ceilingMinutes`) was lower
  /// than the requested total but still inside the hard daily maximum.
  static const String ceilingCapped = 'timeBudget.ceilingCapped';
}

/// The complete allocation outcome of one [TimeBudgetAllocator.allocate] call.
final class TimeBudgetAllocation {
  TimeBudgetAllocation({
    required this.budget,
    required this.requestedTotal,
    required this.hardMaximum,
    required this.ceilingCap,
    required this.scaling,
    required this.policy,
    required this.changeSet,
  });

  /// The resulting [TimeBudget] — always satisfies the sum invariant and
  /// never exceeds [hardMaximum] or [ceilingCap].
  final TimeBudget budget;

  /// The total the caller asked for, in elapsed minutes.
  final Duration requestedTotal;

  /// The hard daily maximum the allocator clamped to.
  final Duration hardMaximum;

  /// The planned single-day ceiling (`policy.ceilingMinutes`) the
  /// allocator had to honour.
  final Duration ceilingCap;

  /// Whether the allocation matches [requestedTotal] exactly, was
  /// shortened, or was extended.
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
  /// `requestedTotal` defaults to the availability's `targetMinutes`.
  /// `extendToday`, when `true`, asks the allocator to lengthen the day
  /// up to the effective upper bound (`min(hardMaximum,
  /// policy.ceilingMinutes)`); the resulting scaling is
  /// [TimeBudgetScaling.extended] with a typed [PlanChange] (ADR 0298
  /// decision 4).
  TimeBudgetAllocation allocate({
    required DailyAvailability availability,
    required RevisionId fromRevisionId,
    required RevisionId toRevisionId,
    Duration? requestedTotal,
    bool extendToday = false,
  }) {
    if (availability.status == AvailabilityStatus.unavailable) {
      throw ArgumentError.value(
        availability.status,
        'availability.status',
        'cannot allocate practice time for an unavailable day',
      );
    }
    final hardMaximum = Duration(minutes: availability.maximumMinutes);
    final ceilingCap = policy.ceilingMinutes;
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
    if (ceilingCap <= Duration.zero) {
      throw ArgumentError.value(
        ceilingCap,
        'policy.ceilingMinutes',
        'must be positive for the time-allocation policy',
      );
    }
    if (extendToday && asked > hardMaximum) {
      // Extending above the hard maximum is impossible — refuse loudly so
      // the caller never silently falls back to a clamp.
      throw ArgumentError.value(
        asked,
        'requestedTotal',
        'extendToday cannot be combined with a request above the hard maximum',
      );
    }

    // 1. Resolve the scaling path: shorten by hard-max, shorten by
    //    planned ceiling, extend by opt-in, or honour the request.
    final scalingDecision = _decideScaling(
      asked: asked,
      hardMaximum: hardMaximum,
      ceilingCap: ceilingCap,
      extendToday: extendToday,
    );
    final clamped = scalingDecision.effectiveTotal;

    // 2. Pick the template, then split with the policy's rounding step.
    final template = policy.templateFor(clamped);
    final budget = _splitForTemplate(clamped, template);

    // 3. Surface the scaling decision as a typed change.
    final changeSet = _buildChangeSet(
      asked: asked,
      effectiveTotal: clamped,
      hardMaximum: hardMaximum,
      ceilingCap: ceilingCap,
      scaling: scalingDecision.scaling,
      evidenceCode: scalingDecision.evidenceCode,
      fromRevisionId: fromRevisionId,
      toRevisionId: toRevisionId,
    );

    return TimeBudgetAllocation(
      budget: budget,
      requestedTotal: asked,
      hardMaximum: hardMaximum,
      ceilingCap: ceilingCap,
      scaling: scalingDecision.scaling,
      policy: policy,
      changeSet: changeSet,
    );
  }

  /// The allocator's scaling decision for a single day. The four branches
  /// map onto the four code paths in [_detectScaling].
  _ScalingDecision _decideScaling({
    required Duration asked,
    required Duration hardMaximum,
    required Duration ceilingCap,
    required bool extendToday,
  }) {
    if (asked > hardMaximum) {
      return _ScalingDecision(
        scaling: TimeBudgetScaling.shortened,
        effectiveTotal: hardMaximum,
        evidenceCode: TimeBudgetAllocationEvidence.hardMaximumClamped,
      );
    }
    if (asked > ceilingCap) {
      // Asked exceeds the planned ceiling but is still within the hard
      // maximum — shrink to the planned ceiling, not the hard maximum.
      return _ScalingDecision(
        scaling: TimeBudgetScaling.shortened,
        effectiveTotal: ceilingCap,
        evidenceCode: TimeBudgetAllocationEvidence.ceilingCapped,
      );
    }
    if (extendToday) {
      // The extension target is the SMALLER of the hard maximum and the
      // planned ceiling — both constraints must hold (ADR 0298 §2).
      final extensionTarget = hardMaximum < ceilingCap
          ? hardMaximum
          : ceilingCap;
      if (extensionTarget > asked) {
        return _ScalingDecision(
          scaling: TimeBudgetScaling.extended,
          effectiveTotal: extensionTarget,
          evidenceCode: TimeBudgetAllocationEvidence.extendedToAvailable,
        );
      }
      // No room to extend — honour the request unchanged.
      return _ScalingDecision(
        scaling: TimeBudgetScaling.none,
        effectiveTotal: asked,
        evidenceCode: null,
      );
    }
    return _ScalingDecision(
      scaling: TimeBudgetScaling.none,
      effectiveTotal: asked,
      evidenceCode: null,
    );
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
    // the rounding remainder is refunded to the primary focus first then
    // by template order, and every block is floor-rounded to the policy
    // step.
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

    // Raw per-slot durations (before rounding/refund). Every slot
    // starts from its template minimum, the leftover pool is split
    // evenly, and the rounding remainder flows to the primary focus
    // first then by template order.
    final raw = <int>[];
    for (var i = 0; i < slots; i++) {
      final extraFromRemainder = _countFor(remainderTargets, i);
      raw.add(template.minimums[i] + perSlot + extraFromRemainder);
    }

    // Floor-rounding per the policy's increment (ADR 0298 §2). Every
    // non-primary slot is snapped DOWN to a multiple of `step`; the
    // rounding residue (and any sub-minimum slots the floor produced)
    // is absorbed by the primary focus so the segments-sum-to-active
    // invariant and the no-sub-minute-fragment rule (brief §5.2) both
    // hold. The primary slot therefore carries the tail — its duration
    // may not be a multiple of `step`, but every other slot always is.
    final step = policy.roundingIncrement.inMinutes;
    final primaryIndex = order.first;
    final rounded = List<int>.filled(slots, 0);
    var nonPrimarySum = 0;
    for (var i = 0; i < slots; i++) {
      if (i == primaryIndex) continue;
      rounded[i] = (raw[i] ~/ step) * step;
      nonPrimarySum += rounded[i];
    }
    rounded[primaryIndex] = activeMinutes - nonPrimarySum;

    // Drop empty slots — their minutes already went to the primary focus.
    final result = <PlannedActiveSegment>[];
    for (var i = 0; i < slots; i++) {
      final duration = Duration(minutes: rounded[i]);
      if (duration <= Duration.zero) continue;
      result.add(
        PlannedActiveSegment(
          kind: template.orderedKinds[i],
          duration: duration,
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
    required Duration effectiveTotal,
    required Duration hardMaximum,
    required Duration ceilingCap,
    required TimeBudgetScaling scaling,
    required String? evidenceCode,
    required RevisionId fromRevisionId,
    required RevisionId toRevisionId,
  }) {
    if (scaling == TimeBudgetScaling.none) return null;

    // The before/after maps keep the data audit-only: every entry is a
    // primitive (microseconds, a code), never a free-text reason.
    final before = <String, Object?>{
      'requestedElapsedMicros': asked.inMicroseconds,
      'scalingCode': scaling.code,
    };
    final after = <String, Object?>{
      'allocatedElapsedMicros': effectiveTotal.inMicroseconds,
    };
    switch (scaling) {
      case TimeBudgetScaling.shortened:
        before['hardMaximumMicros'] = hardMaximum.inMicroseconds;
        before['ceilingCapMicros'] = ceilingCap.inMicroseconds;
      case TimeBudgetScaling.extended:
        before['hardMaximumMicros'] = hardMaximum.inMicroseconds;
        before['ceilingCapMicros'] = ceilingCap.inMicroseconds;
      case TimeBudgetScaling.none:
        // Unreachable — guarded above.
        break;
    }

    final change = PlanChange(
      type: PlanChangeType.updated,
      target: 'timeBudget',
      before: before,
      after: after,
      reason: PlanChangeReason.systemAdaptation,
      evidenceRefs: <String>[evidenceCode!],
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

/// The internal result of [_decideScaling] — the effective total plus the
/// provenance needed to surface it as a typed [PlanChange].
class _ScalingDecision {
  const _ScalingDecision({
    required this.scaling,
    required this.effectiveTotal,
    required this.evidenceCode,
  });

  final TimeBudgetScaling scaling;
  final Duration effectiveTotal;

  /// `null` when [scaling] is [TimeBudgetScaling.none] — the change-set
  /// builder uses it as a typed-null sentinel.
  final String? evidenceCode;
}
