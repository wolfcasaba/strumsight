import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/storage/json_document_store.dart';
import 'package:strumsight/features/gamification/data/local_reward_ledger_repository.dart';
import 'package:strumsight/features/gamification/public.dart';

import '../../../support/preference_store.dart';

void main() {
  group('A1 — processing failure must not break the feature session save', () {
    test('a ledger-side failure during enqueue does NOT throw across the '
        'ingestor API surface', () async {
      final fixture = _Fixture(capacity: 4, maxAttempts: 3);
      // Ledger will explode on every append — the worst case for A1.
      fixture.ledger.alwaysThrow = true;

      final ingestor = fixture.ingestor;
      final event = fixture.event(eventId: 'activity-a1');
      final entry = fixture.entry(sourceEventId: 'activity-a1');

      // Must complete without an exception escaping; that is the contract
      // the feature session relies on.
      final enqueue = await ingestor.recordSavedActivity(
        event: event,
        entry: entry,
      );
      expect(enqueue.accepted, isTrue);

      // Drain too must not throw — even if every append fails.
      final report = await ingestor.drain();
      // The thrown append was captured into a dropped entry; the record is
      // still pending and the next drain will retry. Either way, no
      // exception leaked.
      expect(report.quarantined, isEmpty);
      expect(fixture.outbox.pendingRecords(), hasLength(1));
    });
  });

  group('A2 — valid event survives a simulated crash during drain', () {
    test('a drain that returns before ack leaves the record pending, and a '
        'second drain with the ledger healthy completes the append', () async {
      final fixture = _Fixture(capacity: 4, maxAttempts: 3);

      final ingestor = fixture.ingestor;
      final event = fixture.event(eventId: 'activity-crash');
      final entry = fixture.entry(sourceEventId: 'activity-crash');
      await ingestor.recordSavedActivity(event: event, entry: entry);

      // First drain: ledger is broken — simulates the crash. The record
      // is still pending; nothing must be acked.
      fixture.ledger.alwaysThrow = true;
      await ingestor.drain();

      // Record is still pending — that's the durability of A2.
      expect(fixture.outbox.pendingRecords(), hasLength(1));

      // Ledger recovers — but the outbox still holds the same data on disk
      // until the next drain runs.
      fixture.ledger.alwaysThrow = false;
      final secondReport = await ingestor.drain();
      expect(secondReport.acknowledged, <String>['activity-crash']);
      expect(fixture.outbox.pendingRecords(), isEmpty);
    });
  });

  group('A3 — drain twice produces one ledger entry', () {
    test('idempotent drain: a second pass with the same ledger turns the '
        'duplicate append into a no-op ack', () async {
      final fixture = _Fixture(capacity: 4, maxAttempts: 3);
      final ingestor = fixture.ingestor;
      final event = fixture.event(eventId: 'activity-once');
      final entry = fixture.entry(sourceEventId: 'activity-once');

      await ingestor.recordSavedActivity(event: event, entry: entry);
      final first = await ingestor.drain();
      expect(first.acknowledged, <String>['activity-once']);

      // A second drain runs against an empty pending queue — it must add no
      // second entry to the ledger.
      final second = await ingestor.drain();
      expect(second.acknowledged, isEmpty);
      expect(
        fixture.ledger.readPage(limit: 10).entries.single.sourceEventId,
        'activity-once',
      );
      expect(fixture.ledger.readPage(limit: 10).entries, hasLength(1));
    });
  });

  group(
    'A4 — event deleted from outbox only AFTER successful ledger write',
    () {
      test(
        'a throwing drain leaves the record in the pending queue, not removed',
        () async {
          final fixture = _Fixture(capacity: 4, maxAttempts: 3);
          fixture.ledger.alwaysThrow = true;
          final ingestor = fixture.ingestor;
          final event = fixture.event(eventId: 'activity-keeps');
          final entry = fixture.entry(sourceEventId: 'activity-keeps');

          await ingestor.recordSavedActivity(event: event, entry: entry);
          expect(fixture.outbox.pendingRecords(), hasLength(1));

          await ingestor.drain();

          // The ledger never got the entry — the record must STILL be in the
          // pending queue (crash safety).
          expect(fixture.outbox.pendingRecords(), hasLength(1));
          // And the ledger has nothing for this source-event ID.
          expect(fixture.ledger.hasProcessedEvent('activity-keeps'), isFalse);
        },
      );
    },
  );

  group('A5 — a malformed record never blocks the queue behind it', () {
    test(
      'the malformed record is quarantined and the one behind it is drained',
      () async {
        final fixture = _Fixture(capacity: 4, maxAttempts: 3);
        final ingestor = fixture.ingestor;

        await ingestor.recordSavedActivity(
          event: fixture.event(eventId: 'activity-good'),
          entry: fixture.entry(sourceEventId: 'activity-good'),
        );

        // Write a manually-broken on-disk payload (one well-formed record
        // + one whose inner event JSON fails to decode). Loading must
        // quarantine the broken one and leave the good one pending.
        _writeBrokenPayload(
          fixture.store,
          LocalActivityOutboxRepository.storageKey,
        );
        final rebuilt = LocalActivityOutboxRepository(
          ledger: fixture.ledger,
          store: fixture.store,
          logger: const NoopAppLogger(),
          capacity: 4,
          maxAttempts: 3,
        );
        final rebuiltIngestor = ActivityEventIngestor(
          outbox: rebuilt,
          logger: const NoopAppLogger(),
        );

        final report = await rebuiltIngestor.drain();
        expect(report.acknowledged, <String>['activity-good']);
        // The broken record was quarantined at load time, not during drain.
        expect(rebuilt.quarantineRecords(), hasLength(1));
        expect(
          rebuilt.quarantineRecords().single.outcome,
          ActivityOutboxOutcome.malformedRecord,
        );
        expect(rebuilt.pendingRecords(), isEmpty);
      },
    );
  });

  group('A6 — the quarantine list is queryable', () {
    test(
      'a ledger exception leaves a quarantine entry that can be inspected',
      () async {
        final fixture = _Fixture(capacity: 4, maxAttempts: 1);
        fixture.ledger.alwaysThrow = true;
        final ingestor = fixture.ingestor;

        await ingestor.recordSavedActivity(
          event: fixture.event(eventId: 'activity-qu'),
          entry: fixture.entry(sourceEventId: 'activity-qu'),
        );

        final report = await ingestor.drain();
        expect(report.quarantined, hasLength(1));
        expect(
          fixture.outbox.quarantineRecords().single.outcome,
          ActivityOutboxOutcome.attemptLimitReached,
        );
        expect(
          fixture.outbox.quarantineRecords().single.reason,
          contains('attempt_limit_reached'),
        );
      },
    );

    test('a retry-limit quarantine survives a fresh repository built over the '
        'same KeyValueStore (F1 restart regression)', () async {
      final fixture = _Fixture(capacity: 4, maxAttempts: 1);
      fixture.ledger.alwaysThrow = true;
      final ingestor = fixture.ingestor;

      await ingestor.recordSavedActivity(
        event: fixture.event(eventId: 'activity-restart'),
        entry: fixture.entry(sourceEventId: 'activity-restart'),
      );

      // First drain — the ledger throws; maxAttempts=1 means the record
      // reaches the retry limit on its very first attempt.
      final firstReport = await ingestor.drain();
      expect(firstReport.quarantined, hasLength(1));
      expect(
        firstReport.quarantined.single.outcome,
        ActivityOutboxOutcome.attemptLimitReached,
      );

      // Simulate an app/repository restart by building a fresh instance
      // over the SAME KeyValueStore — the only way the on-disk bytes
      // could be read back is if _ensureLoaded decodes the persisted
      // quarantine key.
      final rebuilt = LocalActivityOutboxRepository(
        ledger: fixture.ledger,
        store: fixture.store,
        logger: const NoopAppLogger(),
        capacity: 4,
        maxAttempts: 1,
      );

      final rebuiltQuarantine = rebuilt.quarantineRecords();
      expect(
        rebuiltQuarantine,
        hasLength(1),
        reason: 'persisted quarantine must survive repository restart',
      );
      expect(
        rebuiltQuarantine.single.outcome,
        ActivityOutboxOutcome.attemptLimitReached,
        reason: 'the retry-limit record must be restored with its outcome',
      );
      expect(
        rebuiltQuarantine.single.event?.eventId,
        'activity-restart',
        reason: 'the decoded event must survive restart',
      );
      expect(
        rebuiltQuarantine.single.entry?.sourceEventId,
        'activity-restart',
        reason: 'the decoded ledger entry must survive restart',
      );
      expect(rebuilt.pendingRecords(), isEmpty);
    });

    test(
      'a corrupt quarantine payload keeps its raw bytes (F1 restart safety)',
      () async {
        // Seed the store with an unparseable quarantine blob — the load
        // step must NOT throw, and must surface the raw bytes as a
        // malformedRaw quarantine entry.
        final store = InMemoryKeyValueStore();
        store.values[activityOutboxQuarantineKey] = '{not valid json';

        final rebuilt = LocalActivityOutboxRepository(
          ledger: _FakeRewardLedger(store),
          store: store,
          logger: const NoopAppLogger(),
          capacity: 4,
          maxAttempts: 3,
        );

        final quarantine = rebuilt.quarantineRecords();
        expect(quarantine, hasLength(1));
        expect(
          quarantine.single.outcome,
          ActivityOutboxOutcome.malformedRecord,
        );
        expect(quarantine.single.rawEvent, '{not valid json');
        expect(rebuilt.pendingRecords(), isEmpty);
      },
    );
  });

  group('A7 — capacity matrix (below / on / above)', () {
    test(
      'capacity = 4, enqueue 3 → pending = 3, quarantine is empty',
      () async {
        final fixture = _Fixture(capacity: 4, maxAttempts: 3);
        final ingestor = fixture.ingestor;

        for (var index = 0; index < 3; index++) {
          final id = 'activity-$index';
          await ingestor.recordSavedActivity(
            event: fixture.event(eventId: id),
            entry: fixture.entry(sourceEventId: id),
          );
        }

        expect(fixture.outbox.pendingRecords(), hasLength(3));
        expect(fixture.outbox.quarantineRecords(), isEmpty);
      },
    );

    test(
      'capacity = 4, enqueue exactly 4 → pending = 4, no eviction yet',
      () async {
        final fixture = _Fixture(capacity: 4, maxAttempts: 3);
        final ingestor = fixture.ingestor;

        for (var index = 0; index < 4; index++) {
          final id = 'activity-$index';
          await ingestor.recordSavedActivity(
            event: fixture.event(eventId: id),
            entry: fixture.entry(sourceEventId: id),
          );
        }

        expect(fixture.outbox.pendingRecords(), hasLength(4));
        expect(fixture.outbox.quarantineRecords(), isEmpty);
      },
    );

    test(
      'capacity = 4, enqueue 5 → oldest pending quarantined, new in queue',
      () async {
        final fixture = _Fixture(capacity: 4, maxAttempts: 3);
        final ingestor = fixture.ingestor;

        for (var index = 0; index < 5; index++) {
          final id = 'activity-$index';
          final result = await ingestor.recordSavedActivity(
            event: fixture.event(eventId: id),
            entry: fixture.entry(sourceEventId: id),
          );
          if (index == 4) {
            expect(result.evicted, isNotNull);
            expect(
              result.evicted!.outcome,
              ActivityOutboxOutcome.evictedForCapacity,
            );
            expect(
              result.evicted!.event?.eventId,
              'activity-0',
              reason: 'oldest pending record must move to quarantine',
            );
          }
        }

        final pending = fixture.outbox.pendingRecords();
        expect(pending, hasLength(4));
        expect(pending.first.event.eventId, 'activity-1');
        expect(pending.last.event.eventId, 'activity-4');
        expect(fixture.outbox.quarantineRecords(), hasLength(1));
        expect(
          fixture.outbox.quarantineRecords().single.event?.eventId,
          'activity-0',
        );
      },
    );
  });

  group('A8 — bounded retries — no infinite loop', () {
    test('a perpetually failing record is quarantined at the attempt limit, '
        'not retried forever', () async {
      final fixture = _Fixture(capacity: 4, maxAttempts: 3);
      fixture.ledger.alwaysThrow = true;
      final ingestor = fixture.ingestor;

      await ingestor.recordSavedActivity(
        event: fixture.event(eventId: 'activity-loop'),
        entry: fixture.entry(sourceEventId: 'activity-loop'),
      );

      // Three drains — the third must land the record in quarantine.
      await ingestor.drain();
      expect(fixture.outbox.pendingRecords(), hasLength(1));
      await ingestor.drain();
      expect(fixture.outbox.pendingRecords(), hasLength(1));
      final report = await ingestor.drain();

      expect(report.quarantined, hasLength(1));
      expect(
        report.quarantined.single.outcome,
        ActivityOutboxOutcome.attemptLimitReached,
      );
      expect(fixture.outbox.pendingRecords(), isEmpty);
    });
  });

  group('Validation', () {
    test('recordSavedActivity rejects an entry whose sourceEventId does not '
        'match the canonical event.eventId', () async {
      final fixture = _Fixture(capacity: 4, maxAttempts: 3);
      final ingestor = fixture.ingestor;

      expect(
        () => ingestor.recordSavedActivity(
          event: fixture.event(eventId: 'event-1'),
          entry: fixture.entry(sourceEventId: 'event-2'),
        ),
        throwsArgumentError,
      );
    });

    test(
      'the outbox constructor rejects non-positive capacity and max attempts',
      () {
        final fixture = _Fixture(capacity: 4, maxAttempts: 3);
        expect(
          () => LocalActivityOutboxRepository(
            ledger: fixture.ledger,
            store: fixture.store,
            logger: const NoopAppLogger(),
            capacity: 0,
            maxAttempts: 3,
          ),
          throwsA(isA<AssertionError>()),
        );
        expect(
          () => LocalActivityOutboxRepository(
            ledger: fixture.ledger,
            store: fixture.store,
            logger: const NoopAppLogger(),
            capacity: 4,
            maxAttempts: 0,
          ),
          throwsA(isA<AssertionError>()),
        );
      },
    );
  });
}

/// Writes a manually-broken on-disk payload: a valid good record + one
/// whose inner event JSON cannot be decoded by [LearningActivityEvent.fromJson].
/// The load step must quarantine the broken one and proceed to the good one.
void _writeBrokenPayload(InMemoryKeyValueStore store, String storageKey) {
  final goodEvent = PracticeActivityEvent(
    eventId: 'activity-good',
    occurredAt: DateTime.utc(2026, 8, 20, 12),
    epochDay: 20685,
    source: ActivitySource.practice,
    trust: EvidenceTrust.scored,
    schemaVersion: learningActivityEventSchemaVersion,
    duration: const Duration(seconds: 1),
    score: 0.9,
  );
  final goodEntry = RewardLedgerEntry(
    ledgerId: 'ledger-good',
    sourceEventId: 'activity-good',
    createdAt: DateTime.utc(2026, 8, 20, 12),
    schemaVersion: rewardLedgerEntrySchemaVersion,
    policyVersion: 1,
    baseXp: 10,
    bonusXp: 0,
    totalXp: 10,
    reasonCodes: const <RewardReason>[RewardReason.baseExperience],
  );
  final payload = <String, Object?>{
    'schemaVersion': documentSchemaVersion,
    'data': <String, Object?>{
      'pending': <Object?>[
        // The broken record: a null eventId that the decoder cannot parse.
        <String, Object?>{
          'event': <String, Object?>{'eventId': null},
          'entry': <String, Object?>{'sourceEventId': null},
          'attempts': 0,
        },
        // The good record: a fully-encoded valid pair.
        <String, Object?>{
          'event': goodEvent.toJson(),
          'entry': goodEntry.toJson(),
          'attempts': 0,
        },
      ],
      'attempts': <String, Object?>{},
    },
  };
  store.values[storageKey] = jsonEncode(payload);
}

class _Fixture {
  _Fixture({required int capacity, required int maxAttempts}) {
    store = InMemoryKeyValueStore();
    ledger = _FakeRewardLedger(store);
    outbox = LocalActivityOutboxRepository(
      ledger: ledger,
      store: store,
      logger: const NoopAppLogger(),
      capacity: capacity,
      maxAttempts: maxAttempts,
    );
    ingestor = ActivityEventIngestor(
      outbox: outbox,
      logger: const NoopAppLogger(),
    );
  }

  late final InMemoryKeyValueStore store;
  late final _FakeRewardLedger ledger;
  late final ActivityOutboxRepository outbox;
  late final ActivityEventIngestor ingestor;

  LearningActivityEvent event({String eventId = 'activity-1'}) =>
      PracticeActivityEvent(
        eventId: eventId,
        occurredAt: _occurredAt,
        epochDay: _epochDay,
        source: ActivitySource.practice,
        trust: EvidenceTrust.scored,
        schemaVersion: learningActivityEventSchemaVersion,
        duration: const Duration(seconds: 1),
        score: 0.9,
      );

  RewardLedgerEntry entry({
    String ledgerId = 'ledger-1',
    String sourceEventId = 'activity-1',
    int policyVersion = 1,
    int baseXp = 10,
    int bonusXp = 0,
    List<RewardReason> reasonCodes = const <RewardReason>[
      RewardReason.baseExperience,
    ],
  }) => RewardLedgerEntry(
    ledgerId: ledgerId,
    sourceEventId: sourceEventId,
    createdAt: _occurredAt,
    schemaVersion: rewardLedgerEntrySchemaVersion,
    policyVersion: policyVersion,
    baseXp: baseXp,
    bonusXp: bonusXp,
    totalXp: baseXp + bonusXp,
    reasonCodes: reasonCodes,
  );
}

/// A controllable reward ledger that sits in front of the real local one. The
/// tests flip [alwaysThrow] to simulate ledger-side failures (the failure
/// shape that A1 defends against).
class _FakeRewardLedger implements RewardLedgerRepository {
  _FakeRewardLedger(this.store);

  final InMemoryKeyValueStore store;
  bool alwaysThrow = false;

  LocalRewardLedgerRepository get _local =>
      LocalRewardLedgerRepository(store: store, logger: const NoopAppLogger());

  @override
  Future<bool> appendIfAbsent(RewardLedgerEntry entry) async {
    if (alwaysThrow) {
      throw StateError('ledger offline');
    }
    return _local.appendIfAbsent(entry);
  }

  @override
  bool hasProcessedEvent(String sourceEventId) =>
      _local.hasProcessedEvent(sourceEventId);

  @override
  RewardLedgerPage readPage({required int limit, String? cursor}) =>
      _local.readPage(limit: limit, cursor: cursor);
}

final DateTime _occurredAt = DateTime.utc(2026, 8, 20, 12);
const int _epochDay = 20685;
