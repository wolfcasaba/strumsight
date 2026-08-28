// E12-R10 — idempotency invariant: repeated deliveries of the same
// sourceEventId must produce exactly one ledger effect. The measure is the
// ledger balance summed over RewardLedgerRepository.readPage (ADR 0469 D1,
// revised in the 1st fix round — R7: ProfileProjector.rebuild() throws on a
// non-empty, single-page ledger, an L349 residual in a forbidden-zone file),
// never a call-count mock (ADR 0469 D1/D2) — a call-count assertion would
// stay green under an implementation that appends the same entry twice.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/gamification/data/local_reward_ledger_repository.dart';
import 'package:strumsight/features/gamification/public.dart';

import '../../support/preference_store.dart';

void main() {
  group('A1 — 100 repeats of one sourceEventId, single batch drain', () {
    test('the projected balance reflects exactly one ledger effect even '
        'though every repeat carries a distinct ledgerId', () async {
      final fixture = _Fixture(capacity: 120, maxAttempts: 3);
      const sourceEventId = 'activity-repeat';
      final event = fixture.event(eventId: sourceEventId);

      for (var i = 0; i < 100; i++) {
        final entry = fixture.entry(
          ledgerId: 'ledger-$i',
          sourceEventId: sourceEventId,
        );
        final result = await fixture.ingestor.recordSavedActivity(
          event: event,
          entry: entry,
        );
        expect(
          result.accepted,
          isTrue,
          reason:
              'repeat #$i must enqueue — the ledger has not been drained '
              'yet, so nothing supersedes it',
        );
      }

      final report = await fixture.ingestor.drain();

      final ledger = _ledgerFor(fixture.store);
      expect(
        _ledgerBalance(ledger),
        fixture.entry(sourceEventId: sourceEventId).totalXp,
      );
      expect(
        _ledgerEntryCount(ledger, sourceEventId),
        1,
        reason:
            'the ledger must contain exactly one entry for this '
            'sourceEventId, no matter how many repeats were enqueued',
      );

      expect(report.acknowledged, hasLength(100));
      expect(report.quarantined, isEmpty);
    });
  });

  group('A1b — 100 repeats as enqueue -> drain pairs', () {
    test(
      'from the second repeat, enqueue is rejected as superseded-by-ledger '
      'and the projected balance never grows past the first effect',
      () async {
        final fixture = _Fixture(capacity: 8, maxAttempts: 3);
        const sourceEventId = 'activity-repeat-pairs';
        final event = fixture.event(eventId: sourceEventId);
        final firstEntry = fixture.entry(
          ledgerId: 'ledger-pair-0',
          sourceEventId: sourceEventId,
        );

        for (var i = 0; i < 100; i++) {
          final entry = fixture.entry(
            ledgerId: 'ledger-pair-$i',
            sourceEventId: sourceEventId,
          );
          final result = await fixture.ingestor.recordSavedActivity(
            event: event,
            entry: entry,
          );

          if (i == 0) {
            expect(result.accepted, isTrue);
          } else {
            expect(
              result.accepted,
              isFalse,
              reason:
                  'repeat #$i must be rejected — the ledger already '
                  'carries this sourceEventId from the first pair\'s drain',
            );
            expect(
              result.evicted?.outcome,
              ActivityOutboxOutcome.supersededByLedger,
            );
          }

          await fixture.ingestor.drain();
        }

        expect(_ledgerBalance(_ledgerFor(fixture.store)), firstEntry.totalXp);
      },
    );
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

/// The number of ledger entries carrying [sourceEventId], summed over every
/// page — the ledger-content half of the A1 measure (brief §6, F2).
int _ledgerEntryCount(RewardLedgerRepository ledger, String sourceEventId) {
  var count = 0;
  String? cursor;
  while (true) {
    final page = ledger.readPage(limit: 100, cursor: cursor);
    count += page.entries
        .where((entry) => entry.sourceEventId == sourceEventId)
        .length;
    if (page.nextCursor == null) return count;
    cursor = page.nextCursor;
  }
}

RewardLedgerRepository _ledgerFor(InMemoryKeyValueStore store) =>
    LocalRewardLedgerRepository(store: store, logger: const NoopAppLogger());

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

/// A controllable reward ledger that sits in front of the real local one —
/// the same shape as `activity_ingestor_test.dart`'s `_FakeRewardLedger`
/// (brief §4 mandates reusing this pattern; a new mock-ledger is forbidden).
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
