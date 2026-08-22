// E08-R26 — AI Tutor → gamification reward adapter.
//
// Maps a caller-supplied tutor signal onto the canonical gamification
// chain. The adapter exists as a contract point so a future tutor
// consumer can wire itself into gamification through a single public
// surface — but the §5.1 rule (a tutor conversation yields ZERO XP)
// means every entry point on this adapter is a no-op today.
//
// Why an empty adapter at all:
//
// 1. ADR 0289 establishes that an "engagement XP" path is not a
//    meaningful signal of either participation or learning. Adding
//    one would invite chat-farming (the §9 risk the brief calls out
//    and the §6.1 A1 cell tests).
//
// 2. The brief's reward for tutor-derived activity is paid by the
//    source the activity takes — a tutor-suggested practice block
//    is rewarded as a `PracticeActivityEvent` (it carries its own
//    score, duration, evidence trust), not as a `TutorActivityEvent`.
//    The adapter therefore deliberately exposes NO `recordConversation`
//    reward path; if a caller wires a tutor chat through here, the
//    ledger stays untouched.
//
// 3. The `ai_tutor` public barrel is *pinned empty* (E04-R01 / L139,
//    `test/features/ai_tutor/ai_tutor_boundary_test.dart`). This
//    adapter does not import anything from the `ai_tutor` feature —
//    the entire input shape is defined locally, mirroring the
//    `TutorPlanOutline` precedent
//    (`lib/features/practice_generator/data/adapter/
//    tutor_plan_proposal_adapter.dart`, ADR 0392 §0.0/1).
//
// All other fields follow the same contract as the song / practice /
// lesson adapters: imports the gamification feature ONLY through its
// `public.dart` barrel, never inspects the AI Tutor feature's
// internals, and never introduces a new AI / network / platform call
// (A8).

import 'package:meta/meta.dart';

import '../../gamification/public.dart';

/// Inputs the tutor adapter needs about one tutor session. Pure
/// values only — no Riverpod snapshots, no clocks, no repositories.
///
/// The adapter deliberately keeps this type minimal: the only signal
/// it acts on is the [kind] discriminator. Conversation-shaped
/// sessions are dropped at the boundary; the adapter does not
/// collect duration, score, quality, or evidence-trust fields,
/// because none of those reach the ledger.
@immutable
final class TutorGamificationSignal {
  const TutorGamificationSignal({
    required this.sessionId,
    required this.kind,
    required this.occurredAt,
    required this.epochDay,
  });

  /// Persisted, save-time identifier of the tutor session. The
  /// adapter derives no event id from it (the §5.1 no-XP rule means
  /// no event id exists) — the field is kept so the caller can
  /// reason about its own result-screen reopen path without a
  /// separate signature.
  final String sessionId;

  /// The kind of tutor activity the caller is reporting. Today only
  /// [TutorGamificationKind.conversation] is recognised; every kind
  /// is a no-op for the ledger.
  final TutorGamificationKind kind;

  /// Wall-clock instant the session ended. Not used by the ledger
  /// (no entry is produced) but kept on the signal for the caller's
  /// bookkeeping.
  final DateTime occurredAt;

  /// Epoch day the session belongs to. Same rationale as
  /// [occurredAt].
  final int epochDay;
}

/// The kinds of tutor activity the adapter recognises. Every entry
/// is a no-op for the reward chain; the enum exists only so a future
/// "tutor-driven practice" path can introduce a value without breaking
/// this adapter's signature.
enum TutorGamificationKind {
  /// A free-form chat with the tutor. The brief §5.1 makes this an
  /// explicit no-reward category (chat-farming defense).
  conversation,
}

/// Outcome of one adapter invocation. The adapter has exactly one
/// outcome — `noOp` — because §5.1 forbids rewarding conversations.
/// The type is kept for symmetry with the other adapters and to
/// leave the door open for a future tutor-derived activity path
/// without a signature change.
@immutable
final class TutorGamificationOutcome {
  /// The adapter produced nothing: no event, no ledger entry, no XP.
  /// This is the only outcome this adapter ever returns.
  const TutorGamificationOutcome.noOp() : eventId = null, accepted = false;

  /// Reserved for future tutor-derived reward paths. Today no signal
  /// produces this outcome.
  const TutorGamificationOutcome.rewarded({required this.eventId})
    : accepted = true;

  /// Always `null` for a `noOp` outcome.
  final String? eventId;

  /// Always `false` today — §5.1 forbids rewarding conversations.
  final bool accepted;
}

/// Pure adapter. Maps one tutor signal into the canonical gamification
/// chain. Today every call is a no-op (brief §5.1).
///
/// The constructor takes the [ActivityEventIngestor] and the
/// eligibility / policy engines to mirror the other adapters'
/// signatures, but none of those collaborators are invoked — the
/// adapter would still be a no-op if they were swapped out. Keeping
/// the constructor symmetric with the others lets a future
/// tutor-derived activity path be added without rewriting every
/// caller's DI graph.
class GamificationTutorAdapter {
  const GamificationTutorAdapter({
    required ActivityEventIngestor ingestor,
    required RewardEligibilityPolicy eligibility,
    required RewardPolicy rewardPolicy,
    required bool featureEnabled,
  }) : _ingestor = ingestor, // ignore: prefer_initializing_formals
       _eligibility = eligibility, // ignore: prefer_initializing_formals
       _rewardPolicy = rewardPolicy, // ignore: prefer_initializing_formals
       _featureEnabled = featureEnabled; // ignore: prefer_initializing_formals

  // The collaborators are intentionally unused — they are held only
  // to keep the constructor symmetric with the other adapters'
  // wiring, so the §A7 build-clean guarantee does not require a
  // separate DI graph just to swap this adapter out.
  // ignore: unused_field
  final ActivityEventIngestor _ingestor;
  // ignore: unused_field
  final RewardEligibilityPolicy _eligibility;
  // ignore: unused_field
  final RewardPolicy _rewardPolicy;
  final bool _featureEnabled;

  /// Adapter version stamped on the produced [RewardLedgerEntry].
  /// Today no entry is produced; the constant is kept so a future
  /// tutor-derived reward path can stamp a v1 receipt without a
  /// signature change.
  static const int adapterPolicyVersion = 1;

  /// Apply [signal] to the chain. Returns the resulting outcome —
  /// every signal is a no-op today (brief §5.1).
  Future<TutorGamificationOutcome> recordConversation(
    TutorGamificationSignal signal,
  ) async {
    // A7 — feature-switch fallback.
    if (!_featureEnabled) {
      return const TutorGamificationOutcome.noOp();
    }

    // §5.1 — a conversation yields zero XP. We deliberately do NOT
    // run the eligibility gate, do NOT build a TutorActivityEvent,
    // and do NOT enqueue any record. The `switch` keeps the
    // exhaustive-check on the enum so adding a new kind fails the
    // build at the only branch that would need to opt in.
    switch (signal.kind) {
      case TutorGamificationKind.conversation:
        return const TutorGamificationOutcome.noOp();
    }
  }
}
