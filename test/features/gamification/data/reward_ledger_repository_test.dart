import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/storage/json_document_store.dart';
import 'package:strumsight/features/gamification/data/local_reward_ledger_repository.dart';
import 'package:strumsight/features/gamification/domain/rewards/reward_ledger_entry.dart';
import 'package:strumsight/features/gamification/domain/rewards/reward_reason.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

const _ledgerKey = 'ss.gamification.reward_ledger';
const _legacyLedgerKey = 'reward_ledger';

({
  LocalRewardLedgerRepository repository,
  InMemoryKeyValueStore store,
  JsonDocumentStore document,
})
_build({Map<String, Object>? initial}) {
  final store = InMemoryKeyValueStore(initial);
  final document = JsonDocumentStore(
    store: store,
    logger: const NoopAppLogger(),
    key: _ledgerKey,
    legacyKey: _legacyLedgerKey,
    name: 'reward_ledger',
  );
  return (
    repository: LocalRewardLedgerRepository(document: document),
    store: store,
    document: document,
  );
}

({LocalRewardLedgerRepository repository, _GatedLedgerWriteStore store})
_buildWithGatedWriteStore() {
  final store = _GatedLedgerWriteStore();
  final document = JsonDocumentStore(
    store: store,
    logger: const NoopAppLogger(),
    key: _ledgerKey,
    legacyKey: _legacyLedgerKey,
    name: 'reward_ledger',
  );
  return (
    repository: LocalRewardLedgerRepository(document: document),
    store: store,
  );
}

RewardLedgerEntry _entry({
  String ledgerId = 'ledger-1',
  String sourceEventId = 'event-1',
  DateTime? createdAt,
  int baseXp = 10,
  int bonusXp = 3,
  List<RewardReason> reasons = const <RewardReason>[
    RewardReason.activityCompleted,
  ],
}) => RewardLedgerEntry(
  ledgerId: ledgerId,
  sourceEventId: sourceEventId,
  createdAt: createdAt ?? DateTime.utc(2026, 8, 19, 12),
  policyVersion: 1,
  baseXp: baseXp,
  bonusXp: bonusXp,
  totalXp: baseXp + bonusXp,
  reasons: reasons,
);

Future<List<RewardLedgerEntry>> _all(
  LocalRewardLedgerRepository repository,
) async {
  final page = await repository.readPage(limit: 100);
  return page.entries;
}

void main() {
  group('Reward ledger repository', () {
    test('A1: appending one source event twice stores one entry', () async {
      final c = _build();
      final entry = _entry();

      expect(await c.repository.appendIfAbsent(entry), isTrue);
      expect(await c.repository.appendIfAbsent(entry), isFalse);
      expect(await _all(c.repository), <RewardLedgerEntry>[entry]);
      expect(
        await c.repository.containsSourceEventId(entry.sourceEventId),
        isTrue,
      );
    });

    test(
      'A2: concurrent appends of one source event store one entry',
      () async {
        final c = _buildWithGatedWriteStore();
        final entry = _entry();

        final first = c.repository.appendIfAbsent(entry);
        final second = c.repository.appendIfAbsent(entry);
        await Future<void>.delayed(Duration.zero);

        expect(
          c.store.pendingLedgerWrites,
          1,
          reason:
              'the second append must wait behind the first read-check-write',
        );
        c.store.releaseWrites();
        final outcomes = await Future.wait<bool>(<Future<bool>>[first, second]);

        expect(outcomes.where((accepted) => accepted), hasLength(1));
        expect(await _all(c.repository), <RewardLedgerEntry>[entry]);
      },
    );

    test(
      'A5: a persisted entry round-trips policy, XP components, and reasons',
      () async {
        final c = _build();
        final entry = _entry(
          baseXp: 20,
          bonusXp: 5,
          reasons: const <RewardReason>[
            RewardReason.activityCompleted,
            RewardReason.qualityBonus,
          ],
        );

        await c.repository.appendIfAbsent(entry);

        expect(await _all(c.repository), <RewardLedgerEntry>[entry]);
      },
    );

    test(
      'A4: a future-schema entry survives a later append unchanged',
      () async {
        final unknown = <String, Object?>{
          'schemaVersion': rewardLedgerEntrySchemaVersion + 1,
          'opaqueFutureField': 'kept-byte-for-byte-as-json',
        };
        final c = _build(
          initial: <String, Object>{
            _ledgerKey: jsonEncode(<String, Object?>{
              'schemaVersion': documentSchemaVersion,
              'items': <Object?>[unknown],
            }),
          },
        );

        await c.repository.appendIfAbsent(_entry());

        final persisted =
            jsonDecode(c.store.readString(_ledgerKey)!) as Map<String, dynamic>;
        final persistedItems = persisted['items'] as List;
        expect(jsonEncode(persistedItems.first), jsonEncode(unknown));
        expect(await _all(c.repository), <RewardLedgerEntry>[_entry()]);
      },
    );

    test(
      'A6: recovery from the last complete document never exposes a half entry',
      () async {
        final prior = _entry(
          ledgerId: 'ledger-prior',
          sourceEventId: 'event-prior',
        );
        final c = _build(
          initial: <String, Object>{
            _ledgerKey: jsonEncode(<String, Object?>{
              'schemaVersion': documentSchemaVersion,
              'items': <Object?>[prior.toJson()],
            }),
          },
        );

        await c.repository.appendIfAbsent(_entry());
        final restarted = LocalRewardLedgerRepository(document: c.document);

        expect(await _all(restarted), <RewardLedgerEntry>[_entry(), prior]);
      },
    );

    test(
      'A7: pages are stable, complete, and enforce the limit boundary',
      () async {
        final c = _build();
        final entries = <RewardLedgerEntry>[
          _entry(
            ledgerId: 'ledger-c',
            sourceEventId: 'event-c',
            createdAt: DateTime.utc(2026, 8, 19, 14),
          ),
          _entry(
            ledgerId: 'ledger-a',
            sourceEventId: 'event-a',
            createdAt: DateTime.utc(2026, 8, 19, 12),
          ),
          _entry(
            ledgerId: 'ledger-b',
            sourceEventId: 'event-b',
            createdAt: DateTime.utc(2026, 8, 19, 12),
          ),
          _entry(
            ledgerId: 'ledger-b',
            sourceEventId: 'event-d',
            createdAt: DateTime.utc(2026, 8, 19, 12),
          ),
        ];
        for (final entry in entries) {
          await c.repository.appendIfAbsent(entry);
        }

        expect(() => c.repository.readPage(limit: 0), throwsArgumentError);

        final first = await c.repository.readPage(limit: 1);
        final second = await c.repository.readPage(
          limit: 1,
          cursor: first.nextCursor,
        );
        final third = await c.repository.readPage(
          limit: 1,
          cursor: second.nextCursor,
        );
        final fourth = await c.repository.readPage(
          limit: 1,
          cursor: third.nextCursor,
        );
        final all = await c.repository.readPage(limit: entries.length + 1);

        expect(first.entries.single.ledgerId, 'ledger-a');
        expect(second.entries.single.ledgerId, 'ledger-b');
        expect(second.entries.single.sourceEventId, 'event-b');
        expect(third.entries.single.ledgerId, 'ledger-b');
        expect(third.entries.single.sourceEventId, 'event-d');
        expect(fourth.entries.single.ledgerId, 'ledger-c');
        expect(fourth.nextCursor, isNull);
        expect(<String>[
          ...first.entries.map((entry) => entry.ledgerId),
          ...second.entries.map((entry) => entry.ledgerId),
          ...third.entries.map((entry) => entry.ledgerId),
          ...fourth.entries.map((entry) => entry.ledgerId),
        ], all.entries.map((entry) => entry.ledgerId).toList());
        expect(all.nextCursor, isNull);
      },
    );

    test(
      'A8: RewardReason values are stable localization keys, not free text',
      () {
        expect(RewardReason.values.map((reason) => reason.name), <String>[
          'activityCompleted',
          'qualityBonus',
          'streakMilestone',
          'achievementUnlocked',
          'questCompleted',
        ]);
      },
    );
  });
}

final class _GatedLedgerWriteStore extends InMemoryKeyValueStore {
  final Completer<void> _writeGate = Completer<void>();
  int pendingLedgerWrites = 0;

  @override
  Future<void> writeString(String key, String value) async {
    if (key == _ledgerKey && !_writeGate.isCompleted) {
      pendingLedgerWrites++;
      await _writeGate.future;
    }
    await super.writeString(key, value);
  }

  void releaseWrites() => _writeGate.complete();
}
