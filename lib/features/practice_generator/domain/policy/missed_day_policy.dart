/// Non-punitive, caller-fed policy for missed days and rescheduling
/// (ADR 0269, SDD Ch8 Kör 27).
///
/// The policy never reads a clock and never generates randomness. Every
/// input is supplied by the caller:
///
///   * the local calendar `today` (R22, ADR 0258 §4),
///   * the schedule's rest days, identified by their
///     [ScheduleDecisionReason.restDay] reason code (ADR 0299 §4),
///   * the per-day classification — `PracticeItemStatus`, reason codes,
///     and whether the day carried a planned primary-focus block.
///
/// The policy classifies each day in the input window into one of three
/// buckets, counts the missed days, and returns a [MissedDayDecision]
/// that names the reschedule mode the application layer should use. The
/// decision is deliberately conservative:
///
///   * Missed days never carry their quota forward — A1, ADR 0258 §3.
///   * Rest days are not missed days — A2.
///   * The simple reschedule moves only the primary-focus block(s); the
///     optional/secondary focus does not transfer — A6.
///   * At and above [MissedDayPolicy.longBreakThreshold] (default 21),
///     the policy returns a readiness proposal instead of a simple
///     reschedule. The boundary belongs to the cautious side
///     (ADR 0269 §5.4) so a 21-day gap is the first call that flips
///     the mode.
///   * Strictly above the threshold, the readiness proposal also asks
///     for a reduced difficulty — the previous estimate is no longer
///     trustworthy — A5, ADR 0261 §2 (time-equivalent).
///
/// The policy is timezone-safe by construction: every date is a local
/// [LocalDate], no UTC conversion happens, and `today` is whatever
/// local calendar the caller injected. The same local date therefore
/// produces the same classification regardless of the device's UTC
/// offset — A7.
library;

import '../model/practice_block.dart';
import '../model/weekly_availability.dart';
import 'scheduling_policy.dart';

/// What a single day means for the missed-day classifier.
enum MissedDayKind {
  /// The day is before `today` and the plan did not carry a planned
  /// primary-focus block — either a rest day, a day outside the plan's
  /// coverage, or a day whose status was already `completed`.
  /// Not a missed day (A2).
  completed,

  /// The day is before `today` and the plan carried a planned
  /// primary-focus block, but the day's status is not `completed`.
  /// Counts toward the missed-day threshold.
  missed,

  /// The day is `today` or after — the policy does not classify it.
  future,
}

/// The reschedule mode the application layer should use.
enum RescheduleMode {
  /// Below the long-break threshold: move only the primary-focus
  /// block(s) into the next scheduled day. The day's frame
  /// (`timeBudget`) is preserved unchanged (A1). No backlog is created.
  simpleReschedule,

  /// At the long-break threshold: emit a readiness block instead of
  /// continuing at the old difficulty. The day's frame may shrink to
  /// the readiness block's minimum, but never grows to absorb the
  /// missed time (A5).
  readinessProposal,

  /// Strictly above the long-break threshold: same as
  /// [readinessProposal], plus a request for a reduced-difficulty day
  /// — the old estimate is no longer trustworthy (ADR 0261 §2 time-
  /// equivalent).
  readinessProposalReducedDifficulty,
}

/// A single day's snapshot as the policy sees it.
final class MissedDayObservation {
  MissedDayObservation({
    required this.localDate,
    required this.status,
    required this.reasonCodes,
    required this.hasPrimaryFocus,
  });

  /// The local calendar day.
  final LocalDate localDate;

  /// The day's [PracticeItemStatus] in the current plan.
  final PracticeItemStatus status;

  /// The reason codes attached to the day. Used to detect rest days
  /// (matches [ScheduleDecisionReason.restDay.code]).
  final List<String> reasonCodes;

  /// Whether the day carried at least one planned primary-focus block
  /// (drives A6 — only primary-focus blocks move into the rescheduled
  /// day; secondary/optional blocks stay behind).
  final bool hasPrimaryFocus;
}

/// The full caller-supplied input the policy needs.
final class MissedDayInput {
  const MissedDayInput({required this.today, required this.observations});

  /// The local calendar `today` (ADR 0258 §4).
  final LocalDate today;

  /// The day's snapshots. Order is not significant — the policy sorts
  /// them by [LocalDate.compareTo].
  final List<MissedDayObservation> observations;
}

/// One row in the policy's per-day classification. Value-class — two
/// rows with the same fields are equal so callers can compare policy
/// outputs without walking the list manually (A7).
final class MissedDayClassification {
  const MissedDayClassification({
    required this.localDate,
    required this.kind,
    required this.contributesToCount,
  });

  final LocalDate localDate;
  final MissedDayKind kind;

  /// True when this row should be added to the missed-day count that
  /// drives the reschedule mode.
  final bool contributesToCount;

  @override
  bool operator ==(Object other) =>
      other is MissedDayClassification &&
      other.localDate == localDate &&
      other.kind == kind &&
      other.contributesToCount == contributesToCount;

  @override
  int get hashCode => Object.hash(localDate, kind, contributesToCount);
}

/// The policy's verdict.
final class MissedDayDecision {
  const MissedDayDecision({
    required this.classifications,
    required this.missedDayCount,
    required this.mode,
  });

  /// One classification per input observation, in the same order.
  final List<MissedDayClassification> classifications;

  /// The number of [MissedDayKind.missed] rows.
  final int missedDayCount;

  /// The reschedule mode the application layer should apply.
  final RescheduleMode mode;
}

/// Pure, caller-fed policy. Every numeric knob is validated at
/// construction; the policy itself never mutates.
final class MissedDayPolicy {
  MissedDayPolicy({
    int longBreakThreshold = 21,
    String? restDayReasonCode,
    String? unavailableReasonCode,
  }) : longBreakThreshold = _positive(longBreakThreshold, 'longBreakThreshold'),
       restDayReasonCode =
           restDayReasonCode ?? ScheduleDecisionReason.restDay.code,
       unavailableReasonCode =
           unavailableReasonCode ?? ScheduleDecisionReason.dayUnavailable.code;

  /// Inclusive lower bound for the "long break" mode flip. 21 missed
  /// days returns [RescheduleMode.readinessProposal] (the boundary
  /// belongs to the cautious side, ADR 0269 §5.4); 22+ returns
  /// [RescheduleMode.readinessProposalReducedDifficulty].
  final int longBreakThreshold;

  /// The reason code that marks a rest day (ADR 0299 §4).
  final String restDayReasonCode;

  /// The reason code that marks an unavailable day. Unavailable days
  /// are not missed days either — they belong to the same "completed"
  /// bucket as rest days because the learner's plan never carried a
  /// scheduled block for them.
  final String unavailableReasonCode;

  /// Classify every input observation and pick a reschedule mode.
  MissedDayDecision evaluate(MissedDayInput input) {
    final observations = input.observations;
    final classifications = <MissedDayClassification>[];
    var missedCount = 0;
    for (final observation in observations) {
      final kind = _classify(observation, input.today);
      final contributes = kind == MissedDayKind.missed;
      if (contributes) missedCount += 1;
      classifications.add(
        MissedDayClassification(
          localDate: observation.localDate,
          kind: kind,
          contributesToCount: contributes,
        ),
      );
    }
    return MissedDayDecision(
      classifications: List<MissedDayClassification>.unmodifiable(
        classifications,
      ),
      missedDayCount: missedCount,
      mode: _modeFor(missedCount),
    );
  }

  MissedDayKind _classify(MissedDayObservation observation, LocalDate today) {
    if (observation.localDate.compareTo(today) >= 0) {
      return MissedDayKind.future;
    }
    // A completed day is not missed regardless of its reason codes.
    if (observation.status == PracticeItemStatus.completed) {
      return MissedDayKind.completed;
    }
    // A rest day or an unavailable day carries no planned block.
    if (observation.reasonCodes.contains(restDayReasonCode)) {
      return MissedDayKind.completed;
    }
    if (observation.reasonCodes.contains(unavailableReasonCode)) {
      return MissedDayKind.completed;
    }
    // A day without a primary-focus block is not a missed practice day.
    if (!observation.hasPrimaryFocus) {
      return MissedDayKind.completed;
    }
    return MissedDayKind.missed;
  }

  RescheduleMode _modeFor(int missedCount) {
    if (missedCount > longBreakThreshold) {
      return RescheduleMode.readinessProposalReducedDifficulty;
    }
    if (missedCount >= longBreakThreshold) {
      return RescheduleMode.readinessProposal;
    }
    return RescheduleMode.simpleReschedule;
  }
}

int _positive(int value, String name) {
  if (value < 1) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
  return value;
}
