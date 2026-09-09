import 'package:flutter/foundation.dart';

/// The three named links of the "10 useful minutes" chain (Ch14 Kör 36):
/// tune up, then play a rhythm/chord exercise, then look at what happened.
///
/// The order is the chain itself, so it lives in one place
/// ([TenMinutePlan.steps]) rather than being re-encoded at every call site.
enum TenMinuteStep {
  /// Get the instrument in tune before spending session minutes on it.
  tune,

  /// The scored practice exercise — the only step that produces a result.
  play,

  /// A short recap of the minutes that were just played.
  review,
}

/// How the 10 minutes are split between the three steps.
///
/// The composition is a RULE, not a table: [tuneBudget] and [reviewBudget]
/// are fixed lead-in/lead-out costs and the play budget is whatever is left,
/// so `tune + play + review == total` holds by construction for every total
/// the rule accepts. A total that cannot fund at least [minimumPlayBudget]
/// of actual playing is REJECTED instead of being silently squeezed — a
/// "10-minute session" that contains 30 seconds of guitar is not the thing
/// this flow promises (Ch14 §9 — no confidently wrong claim).
@immutable
final class TenMinutePlan {
  const TenMinutePlan._({
    required this.total,
    required this.tune,
    required this.play,
    required this.review,
  });

  /// The nominal session length the Today hub advertises.
  static const Duration defaultTotal = Duration(minutes: 10);

  /// Fixed lead-in: long enough to tune six strings, short enough that it
  /// never eats the playing time.
  static const Duration tuneBudget = Duration(minutes: 2);

  /// Fixed lead-out: a glance at the recap, not a second session.
  static const Duration reviewBudget = Duration(minutes: 1);

  /// Below this the chain is not a practice session any more.
  static const Duration minimumPlayBudget = Duration(minutes: 1);

  /// Whether [total] can fund the chain at all — the guard callers use
  /// before [TenMinutePlan.of], so a rejected total is a checked state and
  /// never a thrown surprise on a button tap.
  static bool fits(Duration total) =>
      total - tuneBudget - reviewBudget >= minimumPlayBudget;

  /// The composition rule. Throws when [fits] is false, which is why every
  /// production caller goes through [standard] or checks [fits] first.
  factory TenMinutePlan.of(Duration total) {
    final play = total - tuneBudget - reviewBudget;
    if (play < minimumPlayBudget) {
      throw ArgumentError.value(
        total,
        'total',
        'a $total session cannot fund the $minimumPlayBudget minimum play '
            'budget after the $tuneBudget tune and $reviewBudget review '
            'lead-in/lead-out',
      );
    }
    return TenMinutePlan._(
      total: total,
      tune: tuneBudget,
      play: play,
      review: reviewBudget,
    );
  }

  /// The shipped 10-minute composition (2 + 7 + 1).
  static TenMinutePlan get standard => TenMinutePlan.of(defaultTotal);

  final Duration total;
  final Duration tune;
  final Duration play;
  final Duration review;

  /// The chain, in order. Single source of the step sequence.
  static const List<TenMinuteStep> steps = <TenMinuteStep>[
    TenMinuteStep.tune,
    TenMinuteStep.play,
    TenMinuteStep.review,
  ];

  Duration budgetOf(TenMinuteStep step) => switch (step) {
    TenMinuteStep.tune => tune,
    TenMinuteStep.play => play,
    TenMinuteStep.review => review,
  };

  /// The invariant the composition rule guarantees; asserted by the tests
  /// against arbitrary totals, not only against [defaultTotal].
  Duration get allocated => tune + play + review;

  @override
  bool operator ==(Object other) =>
      other is TenMinutePlan &&
      other.total == total &&
      other.tune == tune &&
      other.play == play &&
      other.review == review;

  @override
  int get hashCode => Object.hash(total, tune, play, review);
}

/// A flow that has been started and not yet finished or abandoned.
///
/// [baselineActiveSeconds] is the daily-goal active-time reading taken when
/// the flow started. The play step's completion is measured against it — the
/// practice log has day granularity only (`PracticeEntry.day`), so "did the
/// user actually play?" is answered by the seconds counter that DID move,
/// never by an invented session record.
@immutable
final class TenMinuteFlowState {
  const TenMinuteFlowState({
    required this.plan,
    required this.step,
    required this.startedAt,
    required this.baselineActiveSeconds,
  });

  final TenMinutePlan plan;
  final TenMinuteStep step;

  /// Wall clock at the moment the user started the chain — the anchor for
  /// the staleness rule below.
  final DateTime startedAt;

  final int baselineActiveSeconds;

  /// How long an interrupted flow may sit before resuming it would be a lie
  /// about what the user was doing. Past this the flow is dropped and the
  /// Today hub goes back to its ordinary single CTA.
  static const Duration resumeWindow = Duration(hours: 2);

  /// 1-based position of [step] in the chain, for "Step 2 of 3" copy.
  int get stepNumber => TenMinutePlan.steps.indexOf(step) + 1;

  int get stepCount => TenMinutePlan.steps.length;

  bool get isLastStep => step == TenMinutePlan.steps.last;

  /// Whether the flow may still be resumed at [now]. False once the resume
  /// window has elapsed OR the wall clock has moved backwards (a device
  /// clock change is not evidence of a live session).
  bool isResumableAt(DateTime now) {
    final elapsed = now.difference(startedAt);
    return !elapsed.isNegative && elapsed <= resumeWindow;
  }

  /// The next state after finishing [step], or `null` once the chain ends.
  TenMinuteFlowState? advanced() {
    final index = TenMinutePlan.steps.indexOf(step);
    if (index < 0 || index + 1 >= TenMinutePlan.steps.length) return null;
    return copyWith(step: TenMinutePlan.steps[index + 1]);
  }

  /// Whether the play step's own evidence has landed: the daily active-time
  /// counter moved past [baselineActiveSeconds] since the flow started.
  /// A counter that went DOWN (a cleared log) is not progress.
  bool hasPlayEvidence(int activeSecondsToday) =>
      activeSecondsToday > baselineActiveSeconds;

  /// Minutes of practice measured since the flow started, floored. Used by
  /// the recap — it reports what was measured, never the planned budget.
  int measuredMinutes(int activeSecondsToday) {
    final delta = activeSecondsToday - baselineActiveSeconds;
    return delta <= 0 ? 0 : delta ~/ 60;
  }

  TenMinuteFlowState copyWith({
    TenMinutePlan? plan,
    TenMinuteStep? step,
    DateTime? startedAt,
    int? baselineActiveSeconds,
  }) => TenMinuteFlowState(
    plan: plan ?? this.plan,
    step: step ?? this.step,
    startedAt: startedAt ?? this.startedAt,
    baselineActiveSeconds: baselineActiveSeconds ?? this.baselineActiveSeconds,
  );

  @override
  bool operator ==(Object other) =>
      other is TenMinuteFlowState &&
      other.plan == plan &&
      other.step == step &&
      other.startedAt == startedAt &&
      other.baselineActiveSeconds == baselineActiveSeconds;

  @override
  int get hashCode => Object.hash(plan, step, startedAt, baselineActiveSeconds);
}

/// The flow as the UI must see it, derived PURELY from the stored state.
///
/// Two rules, both applied without mutating anything (so this can run inside
/// a widget `build`):
///
/// 1. **Interruption.** A flow that is no longer resumable at [now]
///    ([TenMinuteFlowState.resumeWindow]) resolves to `null` — the hub falls
///    back to its ordinary single CTA rather than inviting the user back
///    into a session they abandoned hours ago.
/// 2. **Play evidence.** A flow sitting on [TenMinuteStep.play] whose
///    measured active time has moved past its baseline resolves to
///    [TenMinuteStep.review]: the user came back from a session that really
///    happened. Without that evidence the step stays `play`, because "you
///    practised" is a claim, not a default.
///
/// The stored state is only committed by an explicit user action
/// (`TenMinuteFlowController.start` / `.advance` / `.abandon`); this
/// function never writes.
TenMinuteFlowState? resolveTenMinuteFlow(
  TenMinuteFlowState? stored, {
  required DateTime now,
  required int activeSecondsToday,
}) {
  if (stored == null) return null;
  if (!stored.isResumableAt(now)) return null;
  if (stored.step == TenMinuteStep.play &&
      stored.hasPlayEvidence(activeSecondsToday)) {
    return stored.advanced() ?? stored;
  }
  return stored;
}
