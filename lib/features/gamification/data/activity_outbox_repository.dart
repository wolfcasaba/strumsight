import '../domain/activity/learning_activity_event.dart';
import '../domain/rewards/reward_ledger_entry.dart';

/// Reason a record left the pending queue and joined the quarantine list.
enum ActivityOutboxOutcome {
  /// The record was already represented by an earlier ledger append; the
  /// pending entry no longer needs to be drained.
  supersededByLedger,

  /// The record exceeded the per-record retry limit and was quarantined to
  /// stop an unbounded retry loop.
  attemptLimitReached,

  /// The record was evicted from a saturated queue into the quarantine list
  /// to make room for a newer event.
  evictedForCapacity,

  /// The record could not be decoded (malformed JSON, unknown shape).
  malformedRecord,
}

/// A pending (event, ledger-entry) pair awaiting successful append to the
/// [RewardLedgerRepository].
final class ActivityOutboxRecord {
  ActivityOutboxRecord({required this.event, required this.entry})
    : assert(
        entry.sourceEventId == event.eventId,
        'entry.sourceEventId must equal event.eventId',
      );

  final LearningActivityEvent event;

  final RewardLedgerEntry entry;
}

/// A record that left the pending queue. The raw pieces are kept verbatim so
/// diagnostics can inspect and, later, resubmit or discard the entry.
///
/// Two shapes are supported:
///
/// * **Decoded** — the canonical [event] + [entry] survived their parsers.
/// * **Raw** — the persisted bytes could not be decoded (malformed shape,
///   unknown event type, blank required field). Only [rawEvent] / [rawEntry]
///   are present; [event] and [entry] are `null`. The reason always names the
///   decode failure so the diagnostic surface has enough to triage.
final class ActivityOutboxQuarantine {
  ActivityOutboxQuarantine({
    required this.outcome,
    required this.event,
    required this.entry,
    required this.attempts,
    required this.reason,
  }) : rawEvent = null,
       rawEntry = null;

  /// Constructs a quarantine from a record whose persisted bytes could not
  /// be decoded.
  factory ActivityOutboxQuarantine.malformedRaw({
    required Object? rawEvent,
    required Object? rawEntry,
    required String reason,
  }) = ActivityOutboxQuarantine._raw; // ignore: prefer_initializing_formals

  ActivityOutboxQuarantine._raw({
    required this.rawEvent,
    required this.rawEntry,
    required String reason,
  }) : outcome = ActivityOutboxOutcome.malformedRecord,
       event = null,
       entry = null,
       attempts = 0,
       reason = reason; // ignore: prefer_initializing_formals

  final ActivityOutboxOutcome outcome;

  /// The decoded event — `null` for raw/malformed records.
  final LearningActivityEvent? event;

  /// The decoded ledger entry — `null` for raw/malformed records.
  final RewardLedgerEntry? entry;

  /// Verbatim persisted event bytes — only present when the event failed to
  /// decode (A5); `null` for any successfully decoded quarantine.
  final Object? rawEvent;

  /// Verbatim persisted ledger-entry bytes — only present when the entry
  /// failed to decode (A5).
  final Object? rawEntry;

  /// How many drain passes attempted this record before it was quarantined.
  /// Zero for raw/malformed quarantines because they were never drained.
  final int attempts;

  /// Free-form, single-line note for diagnostics (never a payload).
  final String reason;
}

/// Bounded local outbox between a feature session save and the append-only
/// [RewardLedgerRepository].
///
/// Contract:
/// * [enqueue] is invoked **after** the feature session itself is persisted.
/// * The outbox persists raw event+entry data so malformed/unknown records
///   can be quarantined instead of silently lost.
/// * Capacity and max attempts are positive, explicit constructor inputs.
/// * No background retry loop — the drain lives in [drain].
/// * A ledger exception must not escape [drain]; the outbox reports the
///   failure via quarantine so the feature session stays successful.
abstract interface class ActivityOutboxRepository {
  /// Append [record] to the pending queue. If the queue is full, the oldest
  /// pending record is quarantined (never deleted) and the new record joins
  /// the queue. Returns the record's position change so a test can verify the
  /// eviction policy.
  ///
  /// Throws [ArgumentError] when:
  /// * [record.entry.sourceEventId] does not equal [record.event.eventId];
  /// * the event/entry are otherwise invalid as defined in their own contracts.
  Future<ActivityOutboxEnqueueResult> enqueue(ActivityOutboxRecord record);

  /// Process every pending record at most once. Each record is forwarded to
  /// the [RewardLedgerRepository] exactly once; successful acknowledgements
  /// remove the record from the pending queue. A failure (ledger exception,
  /// decoding, capacity) quarantines the record and the next record is
  /// attempted — the drain NEVER stops because one record is bad and NEVER
  /// lets an exception escape.
  Future<ActivityOutboxDrainReport> drain();

  /// Snapshot of the current pending queue (FIFO order, oldest first).
  List<ActivityOutboxRecord> pendingRecords();

  /// Snapshot of every record that left the pending queue since boot.
  List<ActivityOutboxQuarantine> quarantineRecords();
}

/// Outcome details from a single [ActivityOutboxRepository.enqueue] call.
final class ActivityOutboxEnqueueResult {
  ActivityOutboxEnqueueResult({required this.accepted, required this.evicted});

  /// True when the new record joined the pending queue (or already matched a
  /// previously drained entry).
  final bool accepted;

  /// Record the queue pushed into quarantine to make room, or null when the
  /// queue had room and no eviction was needed.
  final ActivityOutboxQuarantine? evicted;
}

/// Aggregate outcome of one [ActivityOutboxRepository.drain] pass.
final class ActivityOutboxDrainReport {
  ActivityOutboxDrainReport({
    required List<String> acknowledged,
    required List<ActivityOutboxQuarantine> quarantined,
    required List<String> dropped,
  }) : acknowledged = List<String>.unmodifiable(acknowledged),
       quarantined = List<ActivityOutboxQuarantine>.unmodifiable(quarantined),
       dropped = List<String>.unmodifiable(dropped);

  /// Source-event IDs whose [RewardLedgerEntry] was successfully appended.
  final List<String> acknowledged;

  /// Records the drain moved into quarantine during this pass.
  final List<ActivityOutboxQuarantine> quarantined;

  /// Records the drain retried (attempt counter incremented) but did NOT yet
  /// quarantine. These stay in the pending queue and the next drain retries.
  final List<String> dropped;
}
