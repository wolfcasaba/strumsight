import '../domain/profile/reward_inbox_item.dart';

/// Pure, immutable state of the [CelebrationCoordinator] state machine.
///
/// The state captures three independent concerns:
///
///  * [inbox] — items that the user has not yet seen. They arrive here
///    whenever the practice session is active (§5.1 — never a popup) or
///    whenever a reward is delivered from a background / closed-app path
///    (§6 A5).
///  * [pendingBatch] — events accumulated for the next consolidated summary
///    while no session is active and the events still fit in the batch
///    window.
///  * [pendingSummaries] — summaries that have already closed (the batch
///    window was exceeded for the events that produced them) but have not
///    yet been consumed by the UI.
///
/// The state is fully immutable; transitions are produced by the static
/// [CelebrationCoordinator.apply] and
/// [CelebrationCoordinator.drain] functions.
final class CelebrationState {
  const CelebrationState({
    this.inbox = const <RewardInboxItem>[],
    this.pendingBatch = const <RewardEvent>[],
    this.pendingSummaries = const <CelebrationSummary>[],
    this.batchStartedAt,
  });

  /// Deflected items (active session or post-window direct delivery).
  final List<RewardInboxItem> inbox;

  /// Events that are still waiting to be consolidated into the next
  /// [CelebrationSummary].
  final List<RewardEvent> pendingBatch;

  /// Summaries that have already closed but have not yet been shown.
  final List<CelebrationSummary> pendingSummaries;

  /// When the current [pendingBatch] was opened. `null` when no batch is
  /// open. Used to evaluate the batch window.
  final DateTime? batchStartedAt;

  /// True when there is at least one pending summary or an open batch.
  bool get hasPendingPresentation =>
      pendingSummaries.isNotEmpty || pendingBatch.isNotEmpty;

  /// Total number of items the user has not seen yet.
  int get unseenCount => inbox.length;

  /// Returns a new state with the supplied fields replaced.
  CelebrationState copyWith({
    List<RewardInboxItem>? inbox,
    List<RewardEvent>? pendingBatch,
    List<CelebrationSummary>? pendingSummaries,
    DateTime? batchStartedAt,
  }) => CelebrationState(
    inbox: inbox ?? this.inbox,
    pendingBatch: pendingBatch ?? this.pendingBatch,
    pendingSummaries: pendingSummaries ?? this.pendingSummaries,
    batchStartedAt: batchStartedAt ?? this.batchStartedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CelebrationState &&
          _sameItems(inbox, other.inbox) &&
          _sameEvents(pendingBatch, other.pendingBatch) &&
          _sameSummaries(pendingSummaries, other.pendingSummaries) &&
          batchStartedAt == other.batchStartedAt;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(inbox),
    Object.hashAll(pendingBatch),
    Object.hashAll(pendingSummaries),
    batchStartedAt,
  );
}

/// Immutable output of a drained celebration batch.
///
/// The summary is the single value the celebration widget renders. The
/// [events] list is sorted by deterministic priority (highest first), and
/// contains the full [RewardEvent] payload so the widget can render the
/// celebration statically under reduced motion (§5.4 / §6 A7) — no field is
/// stripped or hidden behind an animation.
final class CelebrationSummary {
  CelebrationSummary({
    required List<RewardEvent> events,
    required this.totalXp,
    required this.startedAt,
    required this.endedAt,
  }) : assert(events.isNotEmpty, 'a summary must contain at least one event'),
       events = List<RewardEvent>.unmodifiable(events);

  /// Sorted events — highest priority first, ties broken by [RewardEvent.earnedAt].
  final List<RewardEvent> events;

  /// Sum of every event's [RewardEvent.earnedXp].
  final int totalXp;

  /// When the batch was opened.
  final DateTime startedAt;

  /// When the batch was closed (window exceeded, drain called, or session
  /// ended).
  final DateTime endedAt;

  /// The highest-priority event's kind — surfaced as the headline of the
  /// summary by the widget.
  RewardKind get highestPriority => events.first.kind;

  /// How many events were consolidated into this summary.
  int get count => events.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CelebrationSummary &&
          _sameEvents(events, other.events) &&
          totalXp == other.totalXp &&
          startedAt == other.startedAt &&
          endedAt == other.endedAt;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(events), totalXp, startedAt, endedAt);
}

/// Why the coordinator produced the inbox entry. Surfaced for the
/// presentation layer (e.g. for analytics or for differentiating
/// session-interrupted batches from background deliveries).
enum CelebrationRouting {
  /// The reward was deflected because the caller reported an active session
  /// (§5.1 / §6 A1).
  activeSessionDeflected,

  /// The reward was deflected because the previous batch's window was
  /// already closed (§6.1 fölött cella, when the caller reports that a
  /// session became active in between).
  postWindowDeflected,
}

/// Public inbox entry record returned alongside the state — a value type so
/// the side-channel can be declared public without leaking private types.
final class RoutedInboxEntry {
  const RoutedInboxEntry(this.item, this.routing);
  final RewardInboxItem item;
  final CelebrationRouting routing;
}

/// Side-channel carried by [CelebrationCoordinator.apply] alongside the
/// returned state — records which inbox entries were just appended and
/// which summaries (if any) were just closed by the call.
final class CelebrationSideEffects {
  const CelebrationSideEffects({
    this.routedToInbox = const <RoutedInboxEntry>[],
    this.closedSummaries = const <CelebrationSummary>[],
  });

  /// Every inbox entry the call just produced, with the routing reason.
  final List<RoutedInboxEntry> routedToInbox;

  /// Every [CelebrationSummary] the call closed during the transition.
  final List<CelebrationSummary> closedSummaries;

  bool get hasAnyEffect =>
      routedToInbox.isNotEmpty || closedSummaries.isNotEmpty;
}

/// Deterministic, side-effect-free reward celebration coordinator
/// (ADR 0389 §2-3, brief §5.1 / §5.3 / §6 A1-A2).
///
/// The coordinator:
///  * routes every reward to the inbox while a practice session is active
///    (§5.1 — no popup, ever);
///  * accumulates rewards into a single [CelebrationSummary] while no
///    session is active and the rewards arrive within [batchWindow]
///    (inclusive — §6.1 "rajta" cell);
///  * closes the previous batch and starts a new one once [batchWindow] is
///    exceeded, deferring the closed summary to the next [drain] call;
///  * sorts events inside each summary by [rewardPriorityIndex], breaking
///    ties by [RewardEvent.earnedAt] — never by `Map` iteration order
///    (brief §6.1 prioritás-mátrix sor).
///
/// The coordinator NEVER writes to the reward ledger and NEVER decides
/// eligibility (ADR 0389 §1) — it consumes already-jóváírt [RewardEvent]s.
final class CelebrationCoordinator {
  /// Creates a coordinator with the supplied batch window.
  ///
  /// [batchWindow] is the inclusive duration during which arriving events
  /// are consolidated into a single summary (brief §6.1). A negative or
  /// zero window is rejected — the threshold triplet requires a positive
  /// window to be meaningful.
  const CelebrationCoordinator({required this.batchWindow});

  /// The inclusive consolidation window (brief §6.1).
  final Duration batchWindow;

  /// Applies one [RewardEvent] to the [state] and returns the next state
  /// plus a side-channel describing which inbox entries were appended and
  /// which summaries (if any) were closed.
  ///
  /// [isActiveSession] is the caller-fed equivalent of
  /// `PracticeSessionState.isActive` (ADR 0389 §2). The coordinator does
  /// not read it from a provider.
  (CelebrationState, CelebrationSideEffects) apply({
    required CelebrationState state,
    required RewardEvent event,
    required bool isActiveSession,
    required DateTime now,
  }) {
    // §5.1 — active session defers every event to the inbox, no popup.
    if (isActiveSession) {
      final item = RewardInboxItem(id: event.id, event: event, addedAt: now);
      // If a pending batch is open from a prior inactive moment (brief §6.1
      // fölött — "a második a postaládába kerül, ha közben gyakorlás indult"),
      // close it as a summary first; the user will see it at session end.
      final closedSummaries = <CelebrationSummary>[];
      final carriedBatch = state.pendingBatch;
      final carriedStart = state.batchStartedAt;
      var workingState = state;
      if (carriedBatch.isNotEmpty) {
        closedSummaries.add(_closeSummary(carriedBatch, carriedStart!, now));
        workingState = workingState.copyWith(
          pendingBatch: const <RewardEvent>[],
          batchStartedAt: null,
          pendingSummaries: <CelebrationSummary>[
            ...workingState.pendingSummaries,
            ...closedSummaries,
          ],
        );
      }
      final next = workingState.copyWith(
        inbox: <RewardInboxItem>[...workingState.inbox, item],
      );
      return (
        next,
        CelebrationSideEffects(
          routedToInbox: <RoutedInboxEntry>[
            RoutedInboxEntry(item, CelebrationRouting.activeSessionDeflected),
          ],
          closedSummaries: closedSummaries,
        ),
      );
    }

    // No pending batch — start a new one with this event.
    if (state.pendingBatch.isEmpty) {
      final next = state.copyWith(
        pendingBatch: <RewardEvent>[event],
        batchStartedAt: now,
      );
      return (next, const CelebrationSideEffects());
    }

    final elapsed = now.difference(state.batchStartedAt!);
    // §6.1 — `elapsed <= batchWindow` is INCLUSIVE (the "rajta" cell
    // belongs to the ÖSSZEVONÓ side per ADR 0389 §3).
    if (elapsed <= batchWindow) {
      final next = state.copyWith(
        pendingBatch: <RewardEvent>[...state.pendingBatch, event],
      );
      return (next, const CelebrationSideEffects());
    }

    // Beyond window — close the previous batch as a summary, then recurse
    // with the new event handled in the fresh state. This naturally
    // produces the §6.1 "fölött" behaviour: if the caller reports
    // `isActiveSession = true` for the new event, the recursion routes it
    // to the inbox (the brief's "a második a postaládába kerül, ha közben
    // gyakorlás indult").
    final closed = _closeSummary(
      state.pendingBatch,
      state.batchStartedAt!,
      now,
    );
    final intermediate = state.copyWith(
      pendingBatch: const <RewardEvent>[],
      batchStartedAt: null,
      pendingSummaries: <CelebrationSummary>[...state.pendingSummaries, closed],
    );
    final (recursedState, recursedEffects) = apply(
      state: intermediate,
      event: event,
      isActiveSession: isActiveSession,
      now: now,
    );
    return (
      recursedState,
      CelebrationSideEffects(
        routedToInbox: recursedEffects.routedToInbox,
        closedSummaries: <CelebrationSummary>[
          closed,
          ...recursedEffects.closedSummaries,
        ],
      ),
    );
  }

  /// Closes every pending summary (including the open batch, if any) and
  /// returns them in arrival order. The returned state has the inbox
  /// preserved and the presentation queues empty.
  (CelebrationState, List<CelebrationSummary>) drain({
    required CelebrationState state,
    required DateTime now,
  }) {
    final pending = state.pendingBatch;
    final summaries = <CelebrationSummary>[...state.pendingSummaries];
    if (pending.isNotEmpty) {
      summaries.add(_closeSummary(pending, state.batchStartedAt!, now));
    }
    return (
      CelebrationState(inbox: state.inbox),
      List<CelebrationSummary>.unmodifiable(summaries),
    );
  }

  CelebrationSummary _closeSummary(
    List<RewardEvent> events,
    DateTime startedAt,
    DateTime endedAt,
  ) {
    final sorted = <RewardEvent>[...events]..sort(_priorityCompare);
    final totalXp = sorted.fold<int>(0, (sum, e) => sum + e.earnedXp);
    return CelebrationSummary(
      events: sorted,
      totalXp: totalXp,
      startedAt: startedAt,
      endedAt: endedAt,
    );
  }
}

/// Comparator used to sort [RewardEvent]s inside a [CelebrationSummary].
///
/// Higher [rewardPriorityIndex] sorts FIRST (mastery > level > quest >
/// daily). Ties are broken by [RewardEvent.earnedAt] (earlier first), then
/// by [RewardEvent.id] for absolute determinism.
int _priorityCompare(RewardEvent a, RewardEvent b) {
  final pa = rewardPriorityIndex(a.kind);
  final pb = rewardPriorityIndex(b.kind);
  if (pa != pb) return pb.compareTo(pa);
  final byEarned = a.earnedAt.compareTo(b.earnedAt);
  if (byEarned != 0) return byEarned;
  return a.id.compareTo(b.id);
}

bool _sameItems(List<RewardInboxItem> a, List<RewardInboxItem> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameEvents(List<RewardEvent> a, List<RewardEvent> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameSummaries(List<CelebrationSummary> a, List<CelebrationSummary> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
