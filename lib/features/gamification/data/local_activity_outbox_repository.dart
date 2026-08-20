import 'dart:async';
import 'dart:convert';

import '../../../core/foundation/json_validation.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/storage/json_document_store.dart';
import '../../../core/storage/key_value_store.dart';
import '../domain/activity/learning_activity_event.dart';
import '../domain/rewards/reward_ledger_entry.dart';
import 'activity_outbox_repository.dart';
import 'reward_ledger_repository.dart';

/// Document schema version of the local outbox document.
///
/// Bumping this number triggers the envelope's "future version" handling in
/// [JsonDocumentStore]; the existing bytes are quarantined intact so the next
/// build can read them.
const int activityOutboxSchemaVersion = 1;

/// Default namespaced storage key for the outbox document.
const String activityOutboxStorageKey = 'ss.gamification.activity_outbox';

/// Default namespaced storage key for the per-record attempt counters.
///
/// Each pending record keeps an attempt counter so the drain can retire
/// records that have already failed too many times.
const String activityOutboxAttemptsKey =
    'ss.gamification.activity_outbox.attempts';

/// Default namespaced storage key for the quarantine list.
const String activityOutboxQuarantineKey =
    'ss.gamification.activity_outbox.quarantine';

/// Bounded local outbox that bridges a feature session save and the append-only
/// [RewardLedgerRepository].
///
/// The capacity bound is **inclusive**: the queue holds up to [capacity]
/// pending records. Enqueueing the (capacity+1)-th record pushes the oldest
/// pending record into the quarantine list — it is **never deleted** (A7).
///
/// The drain is idempotent: the ledger's append-if-absent is the only
/// deduplication (A3). Failures are recorded in an attempt counter and the
/// record is retried on the next drain until [maxAttempts] is exceeded (A8).
///
/// No background retry loop runs; the drain is opt-in (startup, app-launch,
/// manual call) so a failing record does not starve the rest of the queue.
final class LocalActivityOutboxRepository implements ActivityOutboxRepository {
  LocalActivityOutboxRepository({
    required RewardLedgerRepository ledger,
    required KeyValueStore store,
    required AppLogger logger,
    required this.capacity,
    required this.maxAttempts,
    JsonDocumentStore? document,
  }) : assert(capacity > 0, 'capacity must be positive'),
       assert(maxAttempts > 0, 'maxAttempts must be positive'),
       _ledger = ledger, // ignore: prefer_initializing_formals
       _logger = logger, // ignore: prefer_initializing_formals
       _document =
           document ??
           JsonDocumentStore(
             store: store,
             logger: logger,
             key: activityOutboxStorageKey,
             legacyKey: _legacyStorageKey,
             name: _documentName,
             bodyKey: _bodyKey,
           );

  static const String _legacyStorageKey = 'gamification.activity_outbox_v1';
  static const String _documentName = 'activity_outbox';
  static const String _bodyKey = 'data';

  /// The namespaced storage key under which the outbox document is persisted.
  static String get storageKey => activityOutboxStorageKey;

  /// The namespaced storage key under which the quarantine log is persisted.
  static String get quarantineKey => activityOutboxQuarantineKey;

  /// Documented maximum number of pending records.
  final int capacity;

  /// Maximum number of drain attempts before a record is quarantined as
  /// [ActivityOutboxOutcome.attemptLimitReached].
  final int maxAttempts;

  final RewardLedgerRepository _ledger;
  final AppLogger _logger;
  final JsonDocumentStore _document;

  final List<_PendingRecord> _pending = <_PendingRecord>[];
  final List<ActivityOutboxQuarantine> _quarantine =
      <ActivityOutboxQuarantine>[];
  final Map<String, int> _attempts = <String, int>{};
  Future<void> _tail = Future<void>.value();
  bool _loaded = false;

  @override
  Future<ActivityOutboxEnqueueResult> enqueue(ActivityOutboxRecord record) {
    final scheduled = _tail.then((_) => _enqueue(record));
    _tail = scheduled.then<void>((_) {}, onError: (_, _) {});
    return scheduled;
  }

  @override
  Future<ActivityOutboxDrainReport> drain() {
    final scheduled = _tail.then((_) => _drain());
    _tail = scheduled.then<void>((_) {}, onError: (_, _) {});
    return scheduled;
  }

  @override
  List<ActivityOutboxRecord> pendingRecords() {
    _ensureLoaded();
    return <ActivityOutboxRecord>[
      for (final record in _pending) record.toOutboxRecord(),
    ];
  }

  @override
  List<ActivityOutboxQuarantine> quarantineRecords() {
    _ensureLoaded();
    return List<ActivityOutboxQuarantine>.unmodifiable(_quarantine);
  }

  Future<ActivityOutboxEnqueueResult> _enqueue(
    ActivityOutboxRecord record,
  ) async {
    _ensureLoaded();

    // Pre-flight: the assignment contract (A4 first half) — the entry's
    // sourceEventId MUST equal the event's eventId; the in-package caller is
    // expected to honour this, but the assertion in the record constructor
    // is the runtime guard.
    if (record.entry.sourceEventId != record.event.eventId) {
      throw ArgumentError(
        'entry.sourceEventId (${record.entry.sourceEventId}) must equal '
        'event.eventId (${record.event.eventId})',
      );
    }

    // If the ledger already shows this source event, the entry is redundant —
    // we still surface it via quarantine so the user can see in diagnostics
    // that the second copy arrived, and so the round count matches what the
    // caller enqueued.
    if (_ledger.hasProcessedEvent(record.entry.sourceEventId)) {
      _logger.info(
        'gamification.outbox.superseded_by_ledger',
        fields: <String, Object?>{'sourceEventId': record.entry.sourceEventId},
      );
      final quarantine = ActivityOutboxQuarantine(
        outcome: ActivityOutboxOutcome.supersededByLedger,
        event: record.event,
        entry: record.entry,
        attempts: 0,
        reason: 'ledger already processed this source event',
      );
      _quarantine.add(quarantine);
      await _persistQuarantine();
      return ActivityOutboxEnqueueResult(accepted: false, evicted: quarantine);
    }

    ActivityOutboxQuarantine? evicted;
    while (_pending.length >= capacity) {
      final displaced = _pending.removeAt(0);
      _attempts.remove(displaced.entry.sourceEventId);
      final quarantineRecord = ActivityOutboxQuarantine(
        outcome: ActivityOutboxOutcome.evictedForCapacity,
        event: displaced.event,
        entry: displaced.entry,
        attempts: displaced.attempts,
        reason: 'evicted: queue saturated at capacity $capacity',
      );
      _quarantine.add(quarantineRecord);
      evicted = quarantineRecord;
      _logger.warning(
        'gamification.outbox.evicted_for_capacity',
        fields: <String, Object?>{
          'sourceEventId': displaced.entry.sourceEventId,
          'capacity': capacity,
        },
      );
    }

    _pending.add(
      _PendingRecord(event: record.event, entry: record.entry, attempts: 0),
    );
    await _persist();
    await _persistQuarantine();
    return ActivityOutboxEnqueueResult(
      accepted: true,
      evicted: _pending.length > capacity ? evicted : evicted,
    );
  }

  Future<ActivityOutboxDrainReport> _drain() async {
    _ensureLoaded();

    final acknowledged = <String>[];
    final quarantined = <ActivityOutboxQuarantine>[];
    final dropped = <String>[];

    // Iterate over a snapshot; we mutate _pending as we go.
    var index = 0;
    while (index < _pending.length) {
      final record = _pending[index];

      // Decode survives across crashes — verify the event JSON still parses.
      // The drain itself does not decode (it works in-domain); this is the
      // recovery path on restart where records were decoded earlier.
      try {
        final raw = record.event.toJson();
        LearningActivityEvent.fromJson(raw);
      } on ArgumentError catch (error, stackTrace) {
        final quarantineRecord = _quarantineRecord(
          record,
          ActivityOutboxOutcome.malformedRecord,
          'decode_failed: $error',
        );
        _quarantine.add(quarantineRecord);
        quarantined.add(quarantineRecord);
        _pending.removeAt(index);
        _attempts.remove(record.entry.sourceEventId);
        _logger.warning(
          'gamification.outbox.malformed_record',
          error: error,
          stackTrace: stackTrace,
          fields: <String, Object?>{
            'sourceEventId': record.entry.sourceEventId,
          },
        );
        await _persist();
        await _persistQuarantine();
        continue;
      }

      final attemptsBefore = record.attempts;
      record.attempts = attemptsBefore + 1;
      _attempts[record.entry.sourceEventId] = record.attempts;
      await _persist();

      bool appended;
      try {
        appended = await _ledger.appendIfAbsent(record.entry);
      } on Object catch (error, stackTrace) {
        // A ledger exception MUST NOT escape the drain — that's A1.
        appended = false;
        _logger.error(
          'gamification.outbox.ledger_exception',
          error: error,
          stackTrace: stackTrace,
          fields: <String, Object?>{
            'sourceEventId': record.entry.sourceEventId,
          },
        );
      }

      if (appended) {
        acknowledged.add(record.entry.sourceEventId);
        _pending.removeAt(index);
        _attempts.remove(record.entry.sourceEventId);
        await _persist();
        // index stays put — removal shifted everything down one
        continue;
      }

      // Either the ledger said "already there" (an idempotent dedupe hit on
      // this event's sourceEventId) OR the ledger threw. Either way the
      // record's work is done — the ledger now (or already) represents the
      // event, so we treat false as ack (no double-payout ever happens).
      if (!appended && _ledger.hasProcessedEvent(record.entry.sourceEventId)) {
        acknowledged.add(record.entry.sourceEventId);
        _pending.removeAt(index);
        _attempts.remove(record.entry.sourceEventId);
        await _persist();
        continue;
      }

      // App path: the append threw AND the ledger still doesn't carry the
      // event. Should we quarantine on attempt limit?
      if (record.attempts >= maxAttempts) {
        final quarantineRecord = _quarantineRecord(
          record,
          ActivityOutboxOutcome.attemptLimitReached,
          'attempt_limit_reached: ${record.attempts}/$maxAttempts',
        );
        _quarantine.add(quarantineRecord);
        quarantined.add(quarantineRecord);
        _pending.removeAt(index);
        _attempts.remove(record.entry.sourceEventId);
        _logger.warning(
          'gamification.outbox.attempt_limit_reached',
          fields: <String, Object?>{
            'sourceEventId': record.entry.sourceEventId,
            'attempts': record.attempts,
            'maxAttempts': maxAttempts,
          },
        );
        await _persist();
        await _persistQuarantine();
        continue;
      }

      // Transient failure: leave record in pending, increment persisted
      // attempt counter, and move to next record.
      dropped.add(record.entry.sourceEventId);
      await _persist();
      index++;
    }

    return ActivityOutboxDrainReport(
      acknowledged: acknowledged,
      quarantined: quarantined,
      dropped: dropped,
    );
  }

  ActivityOutboxQuarantine _quarantineRecord(
    _PendingRecord record,
    ActivityOutboxOutcome outcome,
    String reason,
  ) => ActivityOutboxQuarantine(
    outcome: outcome,
    event: record.event,
    entry: record.entry,
    attempts: record.attempts,
    reason: reason,
  );

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;

    final body = _document.readBody();
    if (body is Map<String, Object?>) {
      final rawPending = body[_bodyPendingKey];
      final rawAttempts = body[_bodyAttemptsKey];
      if (rawPending is List<Object?> && rawAttempts is Map<String, Object?>) {
        for (final MapEntry<String, Object?> entry in rawAttempts.entries) {
          final value = entry.value;
          if (value is int) {
            _attempts[entry.key] = value;
          }
        }

        for (final raw in rawPending) {
          if (raw is! Map) {
            // Raw payload is not a record envelope — quarantine so the user can
            // inspect the bytes (A5).
            _logger.warning(
              'gamification.outbox.pending_record_quarantined',
              fields: <String, Object?>{'reason': 'not_a_map'},
            );
            _quarantine.add(
              ActivityOutboxQuarantine.malformedRaw(
                rawEvent: raw,
                rawEntry: null,
                reason: 'pending record is not a map',
              ),
            );
            continue;
          }
          final rawMap = <String, Object?>{
            for (final entry in raw.entries)
              if (entry.key is String) entry.key as String: entry.value,
          };
          try {
            final pending = _decodePending(requireObject(rawMap));
            _pending.add(pending);
          } on JsonRecordException catch (e) {
            _logger.warning(
              'gamification.outbox.pending_record_quarantined',
              fields: <String, Object?>{
                'reason': e.reason,
                if (e.field != null) 'field': e.field,
              },
            );
            _quarantine.add(
              ActivityOutboxQuarantine.malformedRaw(
                rawEvent: rawMap['event'],
                rawEntry: rawMap['entry'],
                reason: 'decode_failed: ${e.reason}',
              ),
            );
          } on ArgumentError catch (e) {
            _logger.warning(
              'gamification.outbox.pending_record_quarantined',
              error: e,
              fields: <String, Object?>{'reason': 'invalid'},
            );
            _quarantine.add(
              ActivityOutboxQuarantine.malformedRaw(
                rawEvent: rawMap['event'],
                rawEntry: rawMap['entry'],
                reason: 'decode_failed: ${e.message ?? e.toString()}',
              ),
            );
          } catch (e, stackTrace) {
            _logger.warning(
              'gamification.outbox.pending_record_quarantined',
              error: e,
              stackTrace: stackTrace,
              fields: <String, Object?>{'reason': 'invalid'},
            );
            _quarantine.add(
              ActivityOutboxQuarantine.malformedRaw(
                rawEvent: rawMap['event'],
                rawEntry: rawMap['entry'],
                reason: 'decode_failed',
              ),
            );
          }
        }
      }
    }

    // The quarantine lives on its OWN storage key and must load even when
    // the pending document is absent — a fresh install or a corrupted
    // pending blob cannot lose the user's diagnostic history (A6 / F1).
    _loadQuarantine();
  }

  static const String _bodyPendingKey = 'pending';
  static const String _bodyAttemptsKey = 'attempts';
  static const String _quarantineRecordsKey = 'records';

  /// Reads the persisted quarantine list under [activityOutboxQuarantineKey]
  /// and populates [_quarantine]. Decode failures keep their raw bytes via
  /// [ActivityOutboxQuarantine.malformedRaw] — no record is silently dropped
  /// (A6 restart contract; F1 corrective).
  void _loadQuarantine() {
    String? raw;
    try {
      raw = _document.store.readString(activityOutboxQuarantineKey);
    } on Object catch (error, stackTrace) {
      _logger.error(
        'gamification.outbox.quarantine_read_failed',
        error: error,
        stackTrace: stackTrace,
        fields: <String, Object?>{'key': activityOutboxQuarantineKey},
      );
      return;
    }
    if (raw == null || raw.isEmpty) return;

    final Object? payload;
    try {
      payload = jsonDecode(raw);
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'gamification.outbox.quarantine_decode_failed',
        error: error,
        stackTrace: stackTrace,
        fields: <String, Object?>{'reason': 'unparsable'},
      );
      _quarantine.add(
        ActivityOutboxQuarantine.malformedRaw(
          rawEvent: raw,
          rawEntry: null,
          reason: 'decode_failed: unparsable',
        ),
      );
      return;
    }
    if (payload is! Map<String, Object?>) {
      _logger.warning(
        'gamification.outbox.quarantine_decode_failed',
        fields: <String, Object?>{'reason': 'not_a_map'},
      );
      _quarantine.add(
        ActivityOutboxQuarantine.malformedRaw(
          rawEvent: raw,
          rawEntry: null,
          reason: 'decode_failed: not_a_map',
        ),
      );
      return;
    }
    final records = payload[_quarantineRecordsKey];
    if (records is! List<Object?>) {
      _logger.warning(
        'gamification.outbox.quarantine_decode_failed',
        fields: <String, Object?>{'reason': 'records_not_a_list'},
      );
      _quarantine.add(
        ActivityOutboxQuarantine.malformedRaw(
          rawEvent: raw,
          rawEntry: null,
          reason: 'decode_failed: records_not_a_list',
        ),
      );
      return;
    }

    for (final rawRecord in records) {
      if (rawRecord is! Map) {
        _logger.warning(
          'gamification.outbox.quarantine_record_skipped',
          fields: <String, Object?>{'reason': 'not_a_map'},
        );
        _quarantine.add(
          ActivityOutboxQuarantine.malformedRaw(
            rawEvent: rawRecord,
            rawEntry: null,
            reason: 'decode_failed: record_not_a_map',
          ),
        );
        continue;
      }
      final rawMap = <String, Object?>{
        for (final entry in rawRecord.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
      _quarantine.add(_decodeQuarantineRecord(rawMap));
    }
  }

  /// Decodes one persisted quarantine record. If the inner event/entry pair
  /// parses, the full decoded shape is preserved (including
  /// [ActivityOutboxOutcome.attemptLimitReached]); otherwise the raw bytes
  /// are kept verbatim via [ActivityOutboxQuarantine.malformedRaw] so the
  /// user's bytes are never lost (A6).
  ActivityOutboxQuarantine _decodeQuarantineRecord(Map<String, Object?> raw) {
    final outcome = _decodeOutcome(raw['outcome']);
    final reason = raw['reason'] is String ? raw['reason'] as String : '';
    final attemptsRaw = raw['attempts'];
    final attempts = attemptsRaw is int ? attemptsRaw : 0;

    final eventField = raw['event'];
    final entryField = raw['entry'];
    if (eventField != null && entryField != null) {
      try {
        final event = LearningActivityEvent.fromJson(eventField);
        final entry = RewardLedgerEntry.fromJson(entryField);
        return ActivityOutboxQuarantine(
          outcome: outcome ?? ActivityOutboxOutcome.malformedRecord,
          event: event,
          entry: entry,
          attempts: attempts,
          reason: reason,
        );
      } on Object catch (error, stackTrace) {
        _logger.warning(
          'gamification.outbox.quarantine_record_decode_failed',
          error: error,
          stackTrace: stackTrace,
        );
        // Fall through — preserve raw bytes below.
      }
    }

    final rawEvent = raw.containsKey('event') ? eventField : raw['rawEvent'];
    final rawEntry = raw.containsKey('entry') ? entryField : raw['rawEntry'];
    return ActivityOutboxQuarantine.malformedRaw(
      rawEvent: rawEvent,
      rawEntry: rawEntry,
      reason: 'decode_failed: $reason',
    );
  }

  ActivityOutboxOutcome? _decodeOutcome(Object? value) {
    if (value is! String) return null;
    for (final outcome in ActivityOutboxOutcome.values) {
      if (outcome.name == value) return outcome;
    }
    return null;
  }

  Map<String, Object?> _pendingSnapshot() => <String, Object?>{
    _bodyPendingKey: <Object?>[
      for (final record in _pending) _encodePending(record),
    ],
    _bodyAttemptsKey: <String, Object?>{
      for (final entry in _attempts.entries) entry.key: entry.value,
    },
  };

  Future<void> _persist() => _document.write(_pendingSnapshot());

  Future<void> _persistQuarantine() async {
    final payload = <String, Object?>{
      'schemaVersion': activityOutboxSchemaVersion,
      'records': <Object?>[
        for (final record in _quarantine)
          <String, Object?>{
            'outcome': record.outcome.name,
            if (record.event != null) 'event': record.event!.toJson(),
            if (record.entry != null) 'entry': record.entry!.toJson(),
            if (record.rawEvent != null) 'rawEvent': record.rawEvent,
            if (record.rawEntry != null) 'rawEntry': record.rawEntry,
            'attempts': record.attempts,
            'reason': record.reason,
          },
      ],
    };
    try {
      await _document.store.writeString(
        activityOutboxQuarantineKey,
        jsonEncode(payload),
      );
    } on StorageException catch (error, stackTrace) {
      _logger.error(
        'gamification.outbox.quarantine_write_failed',
        error: error,
        stackTrace: stackTrace,
        fields: <String, Object?>{'key': activityOutboxQuarantineKey},
      );
    }
  }

  static Map<String, Object?> _encodePending(_PendingRecord record) =>
      <String, Object?>{
        'event': record.event.toJson(),
        'entry': record.entry.toJson(),
        'attempts': record.attempts,
      };

  static _PendingRecord _decodePending(Map<String, dynamic> raw) {
    final event = LearningActivityEvent.fromJson(requireObject(raw['event']));
    final entry = RewardLedgerEntry.fromJson(requireObject(raw['entry']));
    final attemptsRaw = raw['attempts'];
    final attempts = attemptsRaw is int ? attemptsRaw : 0;
    return _PendingRecord(event: event, entry: entry, attempts: attempts);
  }
}

class _PendingRecord {
  _PendingRecord({
    required this.event,
    required this.entry,
    required this.attempts,
  });

  final LearningActivityEvent event;
  final RewardLedgerEntry entry;
  int attempts;

  ActivityOutboxRecord toOutboxRecord() =>
      ActivityOutboxRecord(event: event, entry: entry);
}
