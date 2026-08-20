import '../../../core/logging/app_logger.dart';
import '../data/activity_outbox_repository.dart';
import '../domain/activity/learning_activity_event.dart';
import '../domain/rewards/reward_ledger_entry.dart';

/// Bridges the feature "session save succeeded" signal to the bounded local
/// outbox that feeds the [RewardLedgerRepository].
///
/// The contract has two halves:
///
/// 1. [recordSavedActivity] is invoked *after* the feature has persisted its
///    own session artefact. It enqueues a paired
///    `(event, ledger-entry)` into the outbox. The entry's source-event id
///    MUST equal the canonical event's id (a precondition the caller is
///    expected to honour because the entry is built by the future R05
///    policy). Any ledger-side failure that surfaces from this call is
///    impossible — the outbox persists the pair independently and the
///    drain replays it later.
///
/// 2. [drain] is invoked from app start (post-R03) and from explicit user
///    triggers. It is the ONLY place the ledger is touched from the outbox.
///    Ledger exceptions that escape the underlying append are captured
///    inside the drain and result in a quarantine — they never cross the
///    boundary into the feature session, in keeping with the rule that a
///    reward failure must never make a practice session unsuccessful.
///
/// There is **no background loop** here. The drain is opt-in, and the same
/// drain call is safely re-runnable on app restart, on recovery from a
/// crash, and on a manual "retry now" button.
final class ActivityEventIngestor {
  ActivityEventIngestor({
    required ActivityOutboxRepository outbox,
    required AppLogger logger,
  }) : _outbox = outbox, // ignore: prefer_initializing_formals
       _logger = logger; // ignore: prefer_initializing_formals

  final ActivityOutboxRepository _outbox;
  final AppLogger _logger;

  /// Records that the feature has persisted a learning-activity [event] with
  /// its canonical, ready [entry].
  ///
  /// The [entry] must have been built against the SAME [event] (the entry's
  /// `sourceEventId` is the canonical event id); a mismatch is rejected with
  /// [ArgumentError] so the off-by-one caller-side bug is surfaced loudly
  /// during development rather than silently producing an orphan ledger row.
  ///
  /// The call is **synchronous-feeling for the feature**: it returns once
  /// the record is durably enqueued. A ledger write failure during the
  /// subsequent drain does NOT invalidate this return — the feature session
  /// has been saved, and the reward work will catch up via the drain.
  Future<ActivityOutboxEnqueueResult> recordSavedActivity({
    required LearningActivityEvent event,
    required RewardLedgerEntry entry,
  }) async {
    // Defensive pre-flight: the contract asks for caller-supplied paired
    // (event, entry) data. The outbox assertion is the runtime guard; this
    // check produces the same error with the same message shape either way,
    // but throws here *before* persistence so an off-by-one caller is caught
    // immediately instead of being quarantined as "supersededByLedger".
    if (entry.sourceEventId != event.eventId) {
      _logger.error(
        'gamification.ingestor.entry_id_mismatch',
        error: ArgumentError(
          'entry.sourceEventId (${entry.sourceEventId}) must equal '
          'event.eventId (${event.eventId})',
        ),
        stackTrace: StackTrace.current,
        fields: <String, Object?>{
          'entrySourceEventId': entry.sourceEventId,
          'eventId': event.eventId,
        },
      );
      throw ArgumentError(
        'entry.sourceEventId (${entry.sourceEventId}) must equal '
        'event.eventId (${event.eventId})',
      );
    }

    final record = ActivityOutboxRecord(event: event, entry: entry);
    return _outbox.enqueue(record);
  }

  /// Drains the queued records into the ledger.
  ///
  /// Idempotent. Re-runs are safe: the ledger's append-if-absent absorbs
  /// duplicates and the outbox only acknowledges records after the ledger
  /// commit has resolved. A ledger exception inside the drain is converted
  /// to a quarantine report and NEVER escapes — that is the mechanism by
  /// which a reward failure cannot break a feature session.
  Future<ActivityOutboxDrainReport> drain() => _outbox.drain();
}
