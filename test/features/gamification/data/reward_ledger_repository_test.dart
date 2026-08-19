import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/storage/json_document_store.dart';
import 'package:strumsight/features/gamification/data/local_reward_ledger_repository.dart';
import 'package:strumsight/features/gamification/public.dart';

import '../../../support/preference_store.dart';

void main() {
  group('Reward ledger — append-only idempotency', () {
    test(
      'A1: an already processed source event is not appended twice',
      () async {
        final fixture = _repository();
        final entry = _entry(sourceEventId: 'activity-1');

        expect(await fixture.repository.appendIfAbsent(entry), isTrue);
        expect(await fixture.repository.appendIfAbsent(entry), isFalse);
        expect(
          fixture.repository.readPage(limit: 10).entries,
          <RewardLedgerEntry>[entry],
        );
        expect(fixture.repository.hasProcessedEvent('activity-1'), isTrue);
      },
    );

    test(
      'A2: concurrent appends of one source event create one ledger entry',
      () async {
        final fixture = _repository();
        final entry = _entry(sourceEventId: 'activity-race');

        final outcomes = await Future.wait<bool>(<Future<bool>>[
          fixture.repository.appendIfAbsent(entry),
          fixture.repository.appendIfAbsent(entry),
        ]);

        expect(outcomes.where((outcome) => outcome), hasLength(1));
        expect(fixture.repository.readPage(limit: 10).entries, hasLength(1));
        expect(
          fixture.repository.readPage(limit: 10).entries.single.sourceEventId,
          'activity-race',
        );
      },
    );

    test('A3: the repository contracts expose no mutation or removal API', () {
      final interfaceSource = File(
        'lib/features/gamification/data/reward_ledger_repository.dart',
      ).readAsStringSync();
      final localSource = File(
        'lib/features/gamification/data/local_reward_ledger_repository.dart',
      ).readAsStringSync();
      final forbiddenMutation = RegExp(r'\b(?:update|delete)\w*\b');

      expect(interfaceSource, isNot(contains(forbiddenMutation)));
      expect(localSource, isNot(contains(forbiddenMutation)));
    });

    test(
      'A4: an entry with a newer schema remains byte-equivalent after append',
      () async {
        const futureEntry = <String, Object?>{
          'schemaVersion': rewardLedgerEntrySchemaVersion + 1,
          'ledgerId': 'future-ledger',
          'sourceEventId': 'future-activity',
          'opaqueFutureField': <String, Object?>{'kept': true},
        };
        final fixture = _repository(
          initial: <String, Object>{
            LocalRewardLedgerRepository.storageKey: jsonEncode(
              <String, Object?>{
                'schemaVersion': documentSchemaVersion,
                'data': <String, Object?>{
                  'entries': <Object?>[futureEntry],
                  'processedEventIds': <String>['future-activity'],
                },
              },
            ),
          },
        );

        await fixture.repository.appendIfAbsent(_entry(sourceEventId: 'fresh'));

        final entries = _storedEntries(fixture.store);
        expect(jsonEncode(entries.first), jsonEncode(futureEntry));
        expect(fixture.repository.hasProcessedEvent('future-activity'), isTrue);
      },
    );

    test(
      'A5: policy version, XP components, and reason codes round-trip',
      () async {
        final fixture = _repository();
        final entry = _entry(
          sourceEventId: 'activity-receipt',
          policyVersion: 7,
          baseXp: 11,
          bonusXp: 4,
          reasonCodes: const <RewardReason>[
            RewardReason.baseExperience,
            RewardReason.qualityBonus,
          ],
        );

        await fixture.repository.appendIfAbsent(entry);
        final reloaded = LocalRewardLedgerRepository(
          store: fixture.store,
          logger: const NoopAppLogger(),
        );

        expect(reloaded.readPage(limit: 10).entries.single, entry);
      },
    );

    test(
      'A6: a refused whole-document write leaves no partial ledger entry',
      () async {
        final fixture = _repository();
        final persisted = _entry(sourceEventId: 'persisted');
        await fixture.repository.appendIfAbsent(persisted);
        fixture.store.failingKeys.add(LocalRewardLedgerRepository.storageKey);

        await fixture.repository.appendIfAbsent(
          _entry(sourceEventId: 'refused'),
        );
        final afterRestart = LocalRewardLedgerRepository(
          store: fixture.store,
          logger: const NoopAppLogger(),
        );

        expect(afterRestart.readPage(limit: 10).entries, <RewardLedgerEntry>[
          persisted,
        ]);
      },
    );
  });

  group('Reward ledger — paging', () {
    test(
      'A7: pages are stable, exhaustive, and support all limit boundaries',
      () async {
        final fixture = _repository();
        for (var index = 1; index <= 3; index++) {
          await fixture.repository.appendIfAbsent(
            _entry(ledgerId: 'ledger-$index', sourceEventId: 'activity-$index'),
          );
        }

        expect(
          () => fixture.repository.readPage(limit: 0),
          throwsArgumentError,
        );

        final pageOne = fixture.repository.readPage(limit: 1);
        final pageTwo = fixture.repository.readPage(
          limit: 1,
          cursor: pageOne.nextCursor,
        );
        final pageThree = fixture.repository.readPage(
          limit: 1,
          cursor: pageTwo.nextCursor,
        );
        final fullPage = fixture.repository.readPage(limit: 4);

        expect(pageOne.entries.single.ledgerId, 'ledger-1');
        expect(pageTwo.entries.single.ledgerId, 'ledger-2');
        expect(pageThree.entries.single.ledgerId, 'ledger-3');
        expect(pageThree.nextCursor, isNull);
        expect(
          <String>[
            ...pageOne.entries.map((entry) => entry.ledgerId),
            ...pageTwo.entries.map((entry) => entry.ledgerId),
            ...pageThree.entries.map((entry) => entry.ledgerId),
          ],
          <String>['ledger-1', 'ledger-2', 'ledger-3'],
        );
        expect(fullPage.entries.map((entry) => entry.ledgerId), <String>[
          'ledger-1',
          'ledger-2',
          'ledger-3',
        ]);
        expect(fullPage.nextCursor, isNull);
      },
    );
  });

  group('Reward reason contract', () {
    test('A8: reason codes are stable enum values, never free text', () {
      expect(RewardReason.values.map((reason) => reason.name), <String>[
        'baseExperience',
        'qualityBonus',
        'consistencyBonus',
        'achievementUnlocked',
        'questCompleted',
        'dailyCapApplied',
        'repeatLimited',
        'tooShort',
        'cancelled',
        'failed',
        'insufficientTrust',
        'fatalSignalQuality',
      ]);
    });
  });

  group('Reward ledger entry validation', () {
    test(
      'rejects missing IDs, negative components, and inconsistent totals',
      () {
        expect(() => _entry(ledgerId: ''), throwsArgumentError);
        expect(() => _entry(sourceEventId: ' '), throwsArgumentError);
        expect(() => _entry(baseXp: -1), throwsArgumentError);
        expect(
          () => _entry(baseXp: 1, bonusXp: 1, totalXp: 1),
          throwsArgumentError,
        );
      },
    );
  });
}

({LocalRewardLedgerRepository repository, InMemoryKeyValueStore store})
_repository({Map<String, Object>? initial}) {
  final store = InMemoryKeyValueStore(initial);
  return (
    repository: LocalRewardLedgerRepository(
      store: store,
      logger: const NoopAppLogger(),
    ),
    store: store,
  );
}

RewardLedgerEntry _entry({
  String ledgerId = 'ledger-1',
  String sourceEventId = 'activity-1',
  int policyVersion = 1,
  int baseXp = 10,
  int bonusXp = 0,
  int? totalXp,
  List<RewardReason> reasonCodes = const <RewardReason>[
    RewardReason.baseExperience,
  ],
}) => RewardLedgerEntry(
  ledgerId: ledgerId,
  sourceEventId: sourceEventId,
  createdAt: DateTime.utc(2026, 8, 19, 12),
  schemaVersion: rewardLedgerEntrySchemaVersion,
  policyVersion: policyVersion,
  baseXp: baseXp,
  bonusXp: bonusXp,
  totalXp: totalXp ?? baseXp + bonusXp,
  reasonCodes: reasonCodes,
);

List<Object?> _storedEntries(InMemoryKeyValueStore store) {
  final document =
      jsonDecode(store.readString(LocalRewardLedgerRepository.storageKey)!)
          as Map<String, Object?>;
  final body = document['data']! as Map<String, Object?>;
  return List<Object?>.from(body['entries']! as List<Object?>);
}
