import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/storage/json_document_store.dart';
import 'package:strumsight/features/gamification/public.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

void main() {
  group('LocalRewardLedgerRepository', () {
    test(
      'A1: appending one source event twice stores only its first entry',
      () async {
        final fixture = _fixture();
        final first = _entry(id: 'first', sourceEventId: 'event-1');
        final duplicate = _entry(id: 'duplicate', sourceEventId: 'event-1');

        expect(await fixture.repository.appendIfAbsent(first), isTrue);
        expect(await fixture.repository.appendIfAbsent(duplicate), isFalse);

        final page = await fixture.repository.readPage(limit: 10);
        expect(page.entries, [first]);
        expect(
          await fixture.repository.containsSourceEventId('event-1'),
          isTrue,
        );
      },
    );

    test(
      'A2: concurrent appends of one source event create one entry',
      () async {
        final fixture = _fixture();
        final entry = _entry(id: 'concurrent', sourceEventId: 'event-race');

        final results = await Future.wait<bool>([
          fixture.repository.appendIfAbsent(entry),
          fixture.repository.appendIfAbsent(entry),
        ]);

        final page = await fixture.repository.readPage(limit: 10);
        expect(results.where((result) => result), hasLength(1));
        expect(page.entries, [entry]);
        expect(
          _storedItems(fixture.store),
          hasLength(1),
          reason: 'the persisted ledger must contain only one raw record',
        );
      },
    );

    test('A3: the append-only repository exposes no mutation API', () async {
      final RewardLedgerRepository repository = _fixture().repository;

      await repository.appendIfAbsent(_entry(id: 'append-only'));
      expect((await repository.readPage(limit: 1)).entries, hasLength(1));
    });

    test(
      'A4: an unknown entry schema remains raw after a later append',
      () async {
        final unknown = <String, Object?>{
          'schemaVersion': rewardLedgerEntrySchemaVersion + 1,
          'ledgerId': 'future-ledger',
          'sourceEventId': 'future-event',
          'futureField': <String, Object?>{'preserve': true},
        };
        final fixture = _fixture(
          initial: <String, Object>{
            _ledgerKey: _envelope(<Object?>[unknown]),
          },
        );
        final current = _entry(id: 'current', sourceEventId: 'current-event');

        expect(await fixture.repository.appendIfAbsent(current), isTrue);

        final raw = _storedItems(fixture.store);
        expect(raw.first, unknown);
        expect((await fixture.repository.readPage(limit: 10)).entries, [
          current,
        ]);
        expect(
          await fixture.repository.containsSourceEventId('future-event'),
          isTrue,
        );
      },
    );

    test(
      'A5: the entry round-trips policy, XP components, and reason codes',
      () async {
        final fixture = _fixture();
        final entry = _entry(
          id: 'round-trip',
          sourceEventId: 'event-round-trip',
          createdAt: DateTime.utc(2026, 8, 19, 12, 34, 56),
          policyVersion: 7,
          baseXp: 12,
          bonusXp: 3,
          reasons: const <RewardReason>[
            RewardReason.baseXp,
            RewardReason.qualityBonus,
          ],
        );

        await fixture.repository.appendIfAbsent(entry);

        final restored = (await fixture.repository.readPage(
          limit: 1,
        )).entries.single;
        expect(restored, entry);
        expect(restored.policyVersion, 7);
        expect(restored.baseXp, 12);
        expect(restored.bonusXp, 3);
        expect(restored.totalXp, 15);
        expect(restored.reasons, entry.reasons);
      },
    );

    test(
      'A6: a refused whole-document write recovers without a partial entry',
      () async {
        final fixture = _fixture();
        final persisted = _entry(
          id: 'persisted',
          sourceEventId: 'event-persisted',
          createdAt: DateTime.utc(2026, 8, 19, 1),
        );
        final interrupted = _entry(
          id: 'interrupted',
          sourceEventId: 'event-interrupted',
          createdAt: DateTime.utc(2026, 8, 19, 2),
        );
        await fixture.repository.appendIfAbsent(persisted);

        fixture.store.failingKeys.add(_ledgerKey);
        expect(await fixture.repository.appendIfAbsent(interrupted), isFalse);
        fixture.store.failingKeys.remove(_ledgerKey);

        final recovered = _fixture(store: fixture.store).repository;
        expect((await recovered.readPage(limit: 10)).entries, [persisted]);
        expect(await recovered.appendIfAbsent(interrupted), isTrue);
        expect((await recovered.readPage(limit: 10)).entries, [
          persisted,
          interrupted,
        ]);
      },
    );

    test('A7: paging is stable and limit boundaries are explicit', () async {
      final fixture = _fixture();
      final chronological = <RewardLedgerEntry>[
        _entry(
          id: 'third',
          sourceEventId: 'event-third',
          createdAt: DateTime.utc(2026, 8, 19, 3),
        ),
        _entry(
          id: 'first',
          sourceEventId: 'event-first',
          createdAt: DateTime.utc(2026, 8, 19, 1),
        ),
        _entry(
          id: 'second',
          sourceEventId: 'event-second',
          createdAt: DateTime.utc(2026, 8, 19, 2),
        ),
      ];
      for (final entry in chronological) {
        await fixture.repository.appendIfAbsent(entry);
      }

      expect(() => fixture.repository.readPage(limit: 0), throwsArgumentError);

      final collected = <RewardLedgerEntry>[];
      String? cursor;
      do {
        final page = await fixture.repository.readPage(
          limit: 1,
          cursor: cursor,
        );
        collected.addAll(page.entries);
        cursor = page.nextCursor;
      } while (cursor != null);

      expect(collected.map((entry) => entry.ledgerId), [
        'ledger-first',
        'ledger-second',
        'ledger-third',
      ]);

      final allAtOnce = await fixture.repository.readPage(limit: 10);
      expect(allAtOnce.entries.map((entry) => entry.ledgerId), [
        'ledger-first',
        'ledger-second',
        'ledger-third',
      ]);
      expect(allAtOnce.nextCursor, isNull);
    });

    test('A8: RewardReason is a stable enum code contract', () {
      expect(RewardReason.values.map((reason) => reason.name), <String>[
        'baseXp',
        'qualityBonus',
        'masteryUnlocked',
        'verifiedEvidence',
        'tooShort',
        'cancelled',
        'failed',
        'fatalSignalQuality',
      ]);
    });

    test(
      'validates immutable entry invariants without creating clocks or IDs',
      () {
        expect(
          () => _entry(baseXp: 2, bonusXp: 1, totalXp: 4),
          throwsArgumentError,
        );
        expect(() => _entry(sourceEventId: '   '), throwsArgumentError);
        expect(
          () => _entry(baseXp: 1, reasons: const <RewardReason>[]),
          throwsArgumentError,
        );
      },
    );
  });
}

const String _ledgerKey = 'ss.test.gamification.reward_ledger';
const String _legacyLedgerKey = 'reward_ledger_v0';

({LocalRewardLedgerRepository repository, InMemoryKeyValueStore store})
_fixture({Map<String, Object>? initial, InMemoryKeyValueStore? store}) {
  final resolvedStore = store ?? InMemoryKeyValueStore(initial);
  return (
    repository: LocalRewardLedgerRepository(
      document: JsonDocumentStore(
        store: resolvedStore,
        logger: const NoopAppLogger(),
        key: _ledgerKey,
        legacyKey: _legacyLedgerKey,
        name: 'reward_ledger',
      ),
    ),
    store: resolvedStore,
  );
}

RewardLedgerEntry _entry({
  String id = 'default',
  String? sourceEventId,
  DateTime? createdAt,
  int policyVersion = 1,
  int baseXp = 10,
  int bonusXp = 0,
  int? totalXp,
  List<RewardReason> reasons = const <RewardReason>[RewardReason.baseXp],
}) => RewardLedgerEntry(
  ledgerId: 'ledger-$id',
  sourceEventId: sourceEventId ?? 'event-$id',
  createdAt: createdAt ?? DateTime.utc(2026, 8, 19),
  policyVersion: policyVersion,
  baseXp: baseXp,
  bonusXp: bonusXp,
  totalXp: totalXp ?? baseXp + bonusXp,
  reasons: reasons,
);

String _envelope(List<Object?> items) => jsonEncode(<String, Object?>{
  'schemaVersion': documentSchemaVersion,
  'items': items,
});

List<Object?> _storedItems(InMemoryKeyValueStore store) {
  final raw = jsonDecode(store.readString(_ledgerKey)!) as Map<String, dynamic>;
  return List<Object?>.from(raw['items'] as List<Object?>);
}
