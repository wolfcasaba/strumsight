// E12-R10 — resume, out-of-order and fault-tolerance invariants for the
// activity outbox. Every cell measures the ledger balance summed over
// RewardLedgerRepository.readPage (ADR 0469 D1, revised R7 in the 1st fix
// round — ProfileProjector.rebuild() throws on a non-empty, single-page
// ledger, an L349 residual in a forbidden-zone file) and, for resume, a
// SECOND `LocalActivityOutboxRepository` built on the SAME
// `InMemoryKeyValueStore` (ADR 0469 D3) — an in-memory object continuing
// itself does not model a process kill.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/gamification/data/local_reward_ledger_repository.dart';
import 'package:strumsight/features/gamification/public.dart';

import '../../support/preference_store.dart';

void main() {
  group('A2 — resume after a mid-drain process kill', () {
    test('a SECOND LocalActivityOutboxRepository on the same store picks up '
        'the pending record and completes it exactly once', () async {
      final store = InMemoryKeyValueStore();
      final firstLedger = _FakeRewardLedger(store)..alwaysThrow = true;
      final firstOutbox = LocalActivityOutboxRepository(
        ledger: firstLedger,
        store: store,
        logger: const NoopAppLogger(),
        capacity: 4,
        maxAttempts: 3,
      );
      final firstIngestor = ActivityEventIngestor(
        outbox: firstOutbox,
        logger: const NoopAppLogger(),
      );

      final event = _event(eventId: 'activity-crash-resume');
      final entry = _entry(
        ledgerId: 'ledger-resume',
        sourceEventId: 'activity-crash-resume',
      );
      await firstIngestor.recordSavedActivity(event: event, entry: entry);

      // Ledger is broken — the drain that "was running when the process
      // died" leaves the record pending, never acked.
      await firstIngestor.drain();
      expect(firstOutbox.pendingRecords(), hasLength(1));

      // Process kill: no reference to firstOutbox/firstIngestor survives.
      // A brand-new repository instance on the SAME store is the resume.
      final secondLedger = _FakeRewardLedger(store);
      final secondOutbox = LocalActivityOutboxRepository(
        ledger: secondLedger,
        store: store,
        logger: const NoopAppLogger(),
        capacity: 4,
        maxAttempts: 3,
      );
      final secondIngestor = ActivityEventIngestor(
        outbox: secondOutbox,
        logger: const NoopAppLogger(),
      );

      expect(
        secondOutbox.pendingRecords().map(
          (record) => record.entry.sourceEventId,
        ),
        <String>['activity-crash-resume'],
        reason:
            'the resumed instance must read the pending record back '
            'from the persisted store, not start empty',
      );

      final report = await secondIngestor.drain();

      expect(_ledgerBalance(_ledgerFor(store)), entry.totalXp);

      expect(report.acknowledged, <String>['activity-crash-resume']);
      expect(secondOutbox.pendingRecords(), isEmpty);
    });
  });

  group('A3 — out-of-order delivery matches the sequential run', () {
    test('the later event drained first produces the same ledger content and '
        'balance as draining in occurredAt order, and the persisted round '
        'trip does not change either event\'s epochDay', () async {
      final earlier = _event(
        eventId: 'activity-early',
        occurredAt: DateTime.utc(2026, 8, 10, 9),
        epochDay: 20675,
      );
      final later = _event(
        eventId: 'activity-late',
        occurredAt: DateTime.utc(2026, 8, 20, 9),
        epochDay: 20685,
      );
      final earlyEntry = _entry(
        ledgerId: 'ledger-early',
        sourceEventId: 'activity-early',
        baseXp: 10,
      );
      final lateEntry = _entry(
        ledgerId: 'ledger-late',
        sourceEventId: 'activity-late',
        baseXp: 15,
      );

      // Sequential baseline: enqueue and drain in occurredAt order.
      final sequentialStore = InMemoryKeyValueStore();
      final sequentialIngestor = _ingestor(sequentialStore);
      await sequentialIngestor.recordSavedActivity(
        event: earlier,
        entry: earlyEntry,
      );
      await sequentialIngestor.drain();
      await sequentialIngestor.recordSavedActivity(
        event: later,
        entry: lateEntry,
      );
      await sequentialIngestor.drain();
      final sequentialTotalXp = _ledgerBalance(_ledgerFor(sequentialStore));

      // Out-of-order run: the LATER event is enqueued (and thus drained)
      // FIRST — the outbox drains strictly FIFO, so enqueue order is the
      // lever that puts the later event ahead of the earlier one.
      final oooStore = InMemoryKeyValueStore();
      final oooOutbox = _outbox(oooStore);
      final oooIngestor = ActivityEventIngestor(
        outbox: oooOutbox,
        logger: const NoopAppLogger(),
      );
      await oooIngestor.recordSavedActivity(event: later, entry: lateEntry);
      await oooIngestor.recordSavedActivity(event: earlier, entry: earlyEntry);

      // Resume from a SECOND instance before draining — this is the
      // measured proof that epochDay survives the persisted round trip
      // (ADR 0469 D4), and that FIFO (later, earlier) order is preserved.
      final resumedOutbox = _outbox(oooStore);
      final pendingAfterResume = resumedOutbox.pendingRecords();
      expect(
        pendingAfterResume.map((record) => record.event.epochDay).toList(),
        <int>[20685, 20675],
        reason:
            'FIFO order is (later, earlier); each epochDay must '
            'survive the reload unchanged',
      );

      final resumedIngestor = ActivityEventIngestor(
        outbox: resumedOutbox,
        logger: const NoopAppLogger(),
      );
      final report = await resumedIngestor.drain();

      // Every sourceEventId appears exactly once in the ledger content, and
      // the balance matches the sequential baseline — the real subject of
      // this cell, checked before the weaker acknowledgment-order assertion.
      final oooLedger = _ledgerFor(oooStore);
      final page = oooLedger.readPage(limit: 10);
      expect(page.entries, hasLength(2));
      expect(page.entries.map((entry) => entry.sourceEventId).toSet(), <String>{
        'activity-early',
        'activity-late',
      });
      expect(_ledgerBalance(oooLedger), sequentialTotalXp);

      expect(report.acknowledged, <String>['activity-late', 'activity-early']);
    });
  });

  group('A4 — ledger fault tolerance across repeated failing drains', () {
    test('a ledger exception never escapes drain and never rolls back the '
        'pending record; two failed drains followed by one healthy drain '
        'still yield a single ledger effect', () async {
      final store = InMemoryKeyValueStore();
      final ledger = _FakeRewardLedger(store)..alwaysThrow = true;
      final outbox = _outboxFor(store, ledger, capacity: 4, maxAttempts: 5);
      final ingestor = ActivityEventIngestor(
        outbox: outbox,
        logger: const NoopAppLogger(),
      );

      final entry = _entry(
        ledgerId: 'ledger-fault',
        sourceEventId: 'activity-fault',
      );
      await ingestor.recordSavedActivity(
        event: _event(eventId: 'activity-fault'),
        entry: entry,
      );

      // First failing drain — must not throw across the ingestor surface.
      await ingestor.drain();
      expect(outbox.pendingRecords(), hasLength(1));
      expect(
        outbox.pendingRecords().single.entry.sourceEventId,
        'activity-fault',
      );

      // Second failing drain — still no rollback, still no duplication.
      await ingestor.drain();
      expect(outbox.pendingRecords(), hasLength(1));

      ledger.alwaysThrow = false;
      final report = await ingestor.drain();

      expect(_ledgerBalance(_ledgerFor(store)), entry.totalXp);

      expect(report.acknowledged, <String>['activity-fault']);
      expect(outbox.pendingRecords(), isEmpty);
    });
  });

  group('A5 — quarantine on attempt-limit does not stall the queue', () {
    test('the record hitting maxAttempts is quarantined with '
        'attemptLimitReached, and a healthy record behind it in the SAME '
        'drain pass is still acknowledged', () async {
      final store = InMemoryKeyValueStore();
      final ledger = _FakeRewardLedger(store)
        ..throwForSourceEventIds.add('activity-bad');
      final outbox = _outboxFor(store, ledger, capacity: 4, maxAttempts: 3);
      final ingestor = ActivityEventIngestor(
        outbox: outbox,
        logger: const NoopAppLogger(),
      );

      final badEntry = _entry(
        ledgerId: 'ledger-bad',
        sourceEventId: 'activity-bad',
      );
      await ingestor.recordSavedActivity(
        event: _event(eventId: 'activity-bad'),
        entry: badEntry,
      );

      // Two failing drains raise the persisted attempt counter to 2
      // (maxAttempts - 1); the record is still pending after each.
      await ingestor.drain();
      await ingestor.drain();
      expect(outbox.pendingRecords(), hasLength(1));

      // A healthy record joins the queue BEHIND the bad one.
      final goodEntry = _entry(
        ledgerId: 'ledger-good',
        sourceEventId: 'activity-good',
      );
      await ingestor.recordSavedActivity(
        event: _event(eventId: 'activity-good'),
        entry: goodEntry,
      );

      // Third drain: the bad record's attempt counter reaches 3 and is
      // quarantined; the loop must continue to the good record in the
      // SAME pass instead of stalling.
      final report = await ingestor.drain();

      // The quarantined record's XP never reached the ledger, and the
      // healthy record's XP did — the real subject of this cell, checked
      // before the weaker report-shape assertions below.
      expect(_ledgerBalance(_ledgerFor(store)), goodEntry.totalXp);

      expect(report.quarantined, hasLength(1));
      expect(
        report.quarantined.single.outcome,
        ActivityOutboxOutcome.attemptLimitReached,
      );
      expect(report.quarantined.single.entry?.sourceEventId, 'activity-bad');
      expect(report.acknowledged, <String>['activity-good']);
      expect(outbox.pendingRecords(), isEmpty);
    });
  });

  group('maxAttempts threshold triplet (maxAttempts = 3, drain-BEFORE '
      'persisted attempts — ADR 0469 D5)', () {
    test('alatta: persisted attempts = maxAttempts - 2 (1) -> after this '
        'drain the counter is 2 (< 3); the record stays PENDING and is '
        'reported as dropped, not quarantined', () async {
      final store = InMemoryKeyValueStore();
      final ledger = _FakeRewardLedger(store)
        ..throwForSourceEventIds.add('activity-below');
      final outbox = _outboxFor(store, ledger, capacity: 4, maxAttempts: 3);
      final ingestor = ActivityEventIngestor(
        outbox: outbox,
        logger: const NoopAppLogger(),
      );
      await ingestor.recordSavedActivity(
        event: _event(eventId: 'activity-below'),
        entry: _entry(
          ledgerId: 'ledger-below',
          sourceEventId: 'activity-below',
        ),
      );

      // Setup drain: persisted attempts 0 -> 1 (= maxAttempts - 2).
      await ingestor.drain();

      // Measured drain: persisted attempts 1 -> 2 (< maxAttempts).
      final report = await ingestor.drain();
      expect(report.dropped, <String>['activity-below']);
      expect(report.quarantined, isEmpty);
      expect(outbox.pendingRecords(), hasLength(1));
    });

    test('rajta: persisted attempts = maxAttempts - 1 (2) -> after this '
        'drain the counter is 3 (>= 3); the record is quarantined as '
        'attemptLimitReached', () async {
      final store = InMemoryKeyValueStore();
      final ledger = _FakeRewardLedger(store)
        ..throwForSourceEventIds.add('activity-on');
      final outbox = _outboxFor(store, ledger, capacity: 4, maxAttempts: 3);
      final ingestor = ActivityEventIngestor(
        outbox: outbox,
        logger: const NoopAppLogger(),
      );
      await ingestor.recordSavedActivity(
        event: _event(eventId: 'activity-on'),
        entry: _entry(ledgerId: 'ledger-on', sourceEventId: 'activity-on'),
      );

      // Setup drains: persisted attempts 0 -> 1 -> 2 (= maxAttempts - 1).
      await ingestor.drain();
      await ingestor.drain();

      // Measured drain: persisted attempts 2 -> 3 (>= maxAttempts).
      final report = await ingestor.drain();
      expect(report.quarantined, hasLength(1));
      expect(
        report.quarantined.single.outcome,
        ActivityOutboxOutcome.attemptLimitReached,
      );
      expect(outbox.pendingRecords(), isEmpty);
    });

    test('fölötte: a fresh enqueue for the same sourceEventId after '
        'quarantine is accepted (the ledger still does not know it) and '
        'produces no new quarantine entry', () async {
      final store = InMemoryKeyValueStore();
      final ledger = _FakeRewardLedger(store)
        ..throwForSourceEventIds.add('activity-above');
      final outbox = _outboxFor(store, ledger, capacity: 4, maxAttempts: 3);
      final ingestor = ActivityEventIngestor(
        outbox: outbox,
        logger: const NoopAppLogger(),
      );
      await ingestor.recordSavedActivity(
        event: _event(eventId: 'activity-above'),
        entry: _entry(
          ledgerId: 'ledger-above',
          sourceEventId: 'activity-above',
        ),
      );

      // Drive the record into quarantine: attempts 0 -> 1 -> 2 -> 3.
      await ingestor.drain();
      await ingestor.drain();
      await ingestor.drain();
      expect(outbox.quarantineRecords(), hasLength(1));
      expect(
        ledger.hasProcessedEvent('activity-above'),
        isFalse,
        reason:
            'the ledger never saw this sourceEventId — it was always '
            'the append call that threw',
      );

      final result = await ingestor.recordSavedActivity(
        event: _event(eventId: 'activity-above'),
        entry: _entry(
          ledgerId: 'ledger-above-retry',
          sourceEventId: 'activity-above',
        ),
      );
      expect(result.accepted, isTrue);
      expect(
        outbox.quarantineRecords(),
        hasLength(1),
        reason: 'this enqueue must not add a second quarantine entry',
      );
      expect(outbox.pendingRecords(), hasLength(1));
    });
  });
}

/// The ledger balance, summed over every page of [RewardLedgerRepository.readPage]
/// (ADR 0469 D1, R7) — the correctly terminating pager the round brief
/// prescribes as the replacement for ProfileProjector.rebuild().
int _ledgerBalance(RewardLedgerRepository ledger) {
  var total = 0;
  String? cursor;
  while (true) {
    final page = ledger.readPage(limit: 100, cursor: cursor);
    for (final entry in page.entries) {
      total += entry.totalXp;
    }
    if (page.nextCursor == null) return total;
    cursor = page.nextCursor;
  }
}

RewardLedgerRepository _ledgerFor(InMemoryKeyValueStore store) =>
    LocalRewardLedgerRepository(store: store, logger: const NoopAppLogger());

LocalActivityOutboxRepository _outboxFor(
  InMemoryKeyValueStore store,
  _FakeRewardLedger ledger, {
  required int capacity,
  required int maxAttempts,
}) => LocalActivityOutboxRepository(
  ledger: ledger,
  store: store,
  logger: const NoopAppLogger(),
  capacity: capacity,
  maxAttempts: maxAttempts,
);

LocalActivityOutboxRepository _outbox(InMemoryKeyValueStore store) =>
    _outboxFor(store, _FakeRewardLedger(store), capacity: 8, maxAttempts: 3);

ActivityEventIngestor _ingestor(InMemoryKeyValueStore store) =>
    ActivityEventIngestor(
      outbox: _outbox(store),
      logger: const NoopAppLogger(),
    );

LearningActivityEvent _event({
  required String eventId,
  DateTime? occurredAt,
  int epochDay = 20685,
}) => PracticeActivityEvent(
  eventId: eventId,
  occurredAt: occurredAt ?? DateTime.utc(2026, 8, 20, 12),
  epochDay: epochDay,
  source: ActivitySource.practice,
  trust: EvidenceTrust.scored,
  schemaVersion: learningActivityEventSchemaVersion,
  duration: const Duration(seconds: 1),
  score: 0.9,
);

RewardLedgerEntry _entry({
  required String ledgerId,
  required String sourceEventId,
  int policyVersion = 1,
  int baseXp = 10,
  int bonusXp = 0,
  List<RewardReason> reasonCodes = const <RewardReason>[
    RewardReason.baseExperience,
  ],
}) => RewardLedgerEntry(
  ledgerId: ledgerId,
  sourceEventId: sourceEventId,
  createdAt: DateTime.utc(2026, 8, 20, 12),
  schemaVersion: rewardLedgerEntrySchemaVersion,
  policyVersion: policyVersion,
  baseXp: baseXp,
  bonusXp: bonusXp,
  totalXp: baseXp + bonusXp,
  reasonCodes: reasonCodes,
);

/// A controllable reward ledger that sits in front of the real local one —
/// the same shape as `activity_ingestor_test.dart`'s `_FakeRewardLedger`,
/// extended with per-sourceEventId failure control for A5 (a single
/// process-wide `alwaysThrow` cannot fail one record while a second,
/// healthy record in the SAME drain pass succeeds).
class _FakeRewardLedger implements RewardLedgerRepository {
  _FakeRewardLedger(this.store);

  final InMemoryKeyValueStore store;
  bool alwaysThrow = false;
  final Set<String> throwForSourceEventIds = <String>{};

  LocalRewardLedgerRepository get _local =>
      LocalRewardLedgerRepository(store: store, logger: const NoopAppLogger());

  @override
  Future<bool> appendIfAbsent(RewardLedgerEntry entry) async {
    if (alwaysThrow || throwForSourceEventIds.contains(entry.sourceEventId)) {
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
