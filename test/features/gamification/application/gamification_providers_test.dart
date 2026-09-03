// E16-R01 (ADR 0496) — the gamification feature's own composition layer.
// A3: absence is carried in TYPE (GamificationDerivedCount.available),
// never a bare placeholder zero. A4: XP/level comes from the persisted
// ledger/profile snapshot only, and reading twice never double-counts.
// §0.0.A/R3 #3/#5/#8: achievement-progress, streak-reason and the reward
// inbox are all real projections over persisted state, not baked constants.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/logging/logger_provider.dart';
import 'package:strumsight/features/gamification/application/achievement_evaluator.dart';
import 'package:strumsight/features/gamification/application/streak_service.dart';
import 'package:strumsight/features/gamification/data/gamification_repository.dart';
import 'package:strumsight/features/gamification/data/gamification_storage_schema.dart';
import 'package:strumsight/features/gamification/data/local_reward_ledger_repository.dart';
import 'package:strumsight/features/gamification/domain/rewards/reward_ledger_entry.dart';
import 'package:strumsight/features/gamification/domain/rewards/reward_reason.dart';
import 'package:strumsight/features/gamification/infrastructure/default_achievement_catalog.dart';
import 'package:strumsight/features/gamification/providers/gamification_providers.dart';

import '../../../support/preference_store.dart';

ProviderContainer _containerWith(Map<String, Object> seed) {
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(seed),
      appLoggerProvider.overrideWithValue(const NoopAppLogger()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

String _ledgerDocument(List<RewardLedgerEntry> entries) => storedDocument({
  'entries': entries.map((entry) => entry.toJson()).toList(),
  'processedEventIds': entries.map((entry) => entry.sourceEventId).toList(),
});

RewardLedgerEntry _achievementReceipt(String achievementId, {int index = 1}) =>
    RewardLedgerEntry(
      ledgerId: 'achievement:$achievementId:evt-$index',
      sourceEventId: 'achievement:$achievementId',
      createdAt: DateTime.utc(2026, 1, index),
      schemaVersion: rewardLedgerEntrySchemaVersion,
      policyVersion: achievementEvaluatorPolicyVersion,
      baseXp: 0,
      bonusXp: 0,
      totalXp: 0,
      reasonCodes: const <RewardReason>[RewardReason.achievementUnlocked],
    );

RewardLedgerEntry _rewardEntry(String sourceEventId, {int totalXp = 20}) =>
    RewardLedgerEntry(
      ledgerId: 'ledger-$sourceEventId',
      sourceEventId: sourceEventId,
      createdAt: DateTime.utc(2026, 2, 1),
      schemaVersion: rewardLedgerEntrySchemaVersion,
      policyVersion: 1,
      baseXp: totalXp,
      bonusXp: 0,
      totalXp: totalXp,
      reasonCodes: const <RewardReason>[RewardReason.baseExperience],
    );

void main() {
  group('honest-count providers carry absence in type (A3)', () {
    test('activeQuestCountProvider is unavailable, not a placeholder zero', () {
      final container = _containerWith({});
      final count = container.read(activeQuestCountProvider);
      expect(count.value, 0);
      expect(count.available, isFalse);
    });

    test('masteryUnlockedCountProvider is unavailable', () {
      final container = _containerWith({});
      final count = container.read(masteryUnlockedCountProvider);
      expect(count.value, 0);
      expect(count.available, isFalse);
    });

    test('weeklyConsistencyDaysProvider is unavailable', () {
      final container = _containerWith({});
      final count = container.read(weeklyConsistencyDaysProvider);
      expect(count.value, 0);
      expect(count.available, isFalse);
    });

    // Fix-round review M1: latestSessionXp gets the same type-carried-gap
    // treatment as the three counts above (a different wrapper class since
    // the value is an ExperiencePoints breakdown, not a plain int).
    test('latestSessionXpProvider is unavailable, not a placeholder empty', () {
      final container = _containerWith({});
      final derived = container.read(latestSessionXpProvider);
      expect(derived.value.totalXp, 0);
      expect(derived.available, isFalse);
    });

    // Fix-round review B2: the quest board is routed through a provider
    // (matching the pattern above) instead of a bare literal in the router,
    // and reading it twice must not re-run a generator (A1's "quest-provider
    // instabil" cell — there is no generator here, but the contract is that
    // there never becomes one that runs per-watch without carrying
    // `available`).
    test('questBoardProvider is unavailable with empty projections', () {
      final container = _containerWith({});
      final board = container.read(questBoardProvider);
      expect(board.available, isFalse);
      expect(board.dailyChallenge, isNull);
      expect(board.dailyChallengeAvailable, isFalse);
      expect(board.dailyQuests, isEmpty);
      expect(board.weeklyQuests, isEmpty);
    });

    test('questBoardProvider is stable across repeated reads', () {
      final container = _containerWith({});
      final first = container.read(questBoardProvider);
      container.invalidate(questBoardProvider);
      final second = container.read(questBoardProvider);
      expect(second.available, first.available);
      expect(second.dailyQuests, equals(first.dailyQuests));
      expect(second.weeklyQuests, equals(first.weeklyQuests));
    });
  });

  group(
    'gamificationProfileProvider — XP from the persisted snapshot (A4)',
    () {
      test('reads totalXp from the profile snapshot, not a re-derivation', () {
        final container = _containerWith({
          GamificationStorageKeys.profileSnapshot: storedDocument(const {
            'schemaVersion': gamificationStorageSchemaVersion,
            'totalXp': 250,
          }),
        });

        final profile = container.read(gamificationProfileProvider);

        expect(profile.totalXp, 250);
        expect(profile.currentLevel.number, 3);
      });

      test('reading the profile twice is stable and writes nothing back', () {
        final store = InMemoryKeyValueStore({
          GamificationStorageKeys.profileSnapshot: storedDocument(const {
            'schemaVersion': gamificationStorageSchemaVersion,
            'totalXp': 40,
          }),
        });
        final container = ProviderContainer(
          overrides: [
            preferenceStoreOverride(store),
            appLoggerProvider.overrideWithValue(const NoopAppLogger()),
          ],
        );
        addTearDown(container.dispose);

        final first = container.read(gamificationProfileProvider);
        container.invalidate(gamificationProfileProvider);
        final second = container.read(gamificationProfileProvider);

        expect(second.totalXp, first.totalXp);
        expect(store.writeLog, isEmpty);
      });
    },
  );

  group(
    'streakEvaluationProvider — real reason, not a baked qualified (§0.0.A/R3 #5)',
    () {
      test(
        'no activity today yields the service\'s own unqualified reason',
        () {
          final container = _containerWith({});

          final evaluation = container.read(streakEvaluationProvider);

          expect(evaluation.reason, isNot(StreakEvaluationReason.qualified));
          expect(
            evaluation.reason,
            StreakEvaluationReason.insufficientActivity,
          );
        },
      );
    },
  );

  group(
    'achievementProgressProvider — ledger receipts, not re-evaluated rules (§0.0.A/R3 #3)',
    () {
      final firstAchievementId = defaultAchievementCatalog.definitions.first.id;

      test(
        'an achievement with no ledger receipt reads as not unlocked',
        () async {
          final container = _containerWith({});

          final progress = await container.read(
            achievementProgressProvider.future,
          );

          final entry = progress[firstAchievementId];
          expect(entry?.completedAt, isNull);
        },
      );

      test(
        'an achievement with a valid ledger receipt reads as unlocked',
        () async {
          final receipt = _achievementReceipt(firstAchievementId);
          final container = _containerWith({
            LocalRewardLedgerRepository.storageKey: _ledgerDocument([receipt]),
          });

          final progress = await container.read(
            achievementProgressProvider.future,
          );

          final entry = progress[firstAchievementId];
          expect(entry, isNotNull);
          expect(entry!.completedAt, isNotNull);
          expect(entry.rewardLedgerEntryId, receipt.ledgerId);
        },
      );

      test(
        'the projection is stable across repeated reads (no instability)',
        () async {
          final receipt = _achievementReceipt(firstAchievementId);
          final store = InMemoryKeyValueStore({
            LocalRewardLedgerRepository.storageKey: _ledgerDocument([receipt]),
          });
          final container = ProviderContainer(
            overrides: [
              preferenceStoreOverride(store),
              appLoggerProvider.overrideWithValue(const NoopAppLogger()),
            ],
          );
          addTearDown(container.dispose);

          final first = await container.read(
            achievementProgressProvider.future,
          );
          container.invalidate(achievementProgressProvider);
          final second = await container.read(
            achievementProgressProvider.future,
          );

          expect(
            second[firstAchievementId]?.completedAt,
            first[firstAchievementId]?.completedAt,
          );
          // The evaluator only ever WRITES via appendIfAbsent when it decides a
          // new unlock — an empty-history rebuild never calls it, so re-reading
          // this projection must never append to the ledger it reads from.
          expect(store.writeLog, isEmpty);
        },
      );
    },
  );

  group(
    'rewardInboxItemsProvider — ledger-joined, no fabricated events (§0.0.A/R3 #8)',
    () {
      test('an inbox item without a matching ledger entry is skipped', () {
        final container = _containerWith({
          GamificationStorageKeys.rewardInbox: storedCollection([
            GamificationInboxItem(
              id: 'orphan-event',
              createdAt: DateTime.utc(2026, 3, 1),
            ).toJson(),
          ]),
        });

        final items = container.read(rewardInboxItemsProvider);

        expect(items, isEmpty);
      });

      test(
        'an inbox item with a matching ledger entry is projected honestly',
        () {
          final entry = _rewardEntry('practice-evt-1', totalXp: 35);
          final container = _containerWith({
            GamificationStorageKeys.rewardInbox: storedCollection([
              GamificationInboxItem(
                id: 'practice-evt-1',
                createdAt: DateTime.utc(2026, 3, 1),
              ).toJson(),
            ]),
            LocalRewardLedgerRepository.storageKey: _ledgerDocument([entry]),
          });

          final items = container.read(rewardInboxItemsProvider);

          expect(items, hasLength(1));
          expect(items.single.event.earnedXp, 35);
          expect(items.single.event.sourceLedgerId, entry.ledgerId);
          expect(items.single.seen, isFalse);
        },
      );

      // Fix-round review B3: this layer must not bake user-facing English
      // into titleKey/bodyKey (it has no AppLocalizations to resolve a real
      // string, and inventing one is the bug that was fixed) — the router's
      // `_localizedRewardInboxItems` is responsible for the real text.
      test(
        'titleKey/bodyKey are not baked English — the router localizes them',
        () {
          final entry = _rewardEntry('practice-evt-3', totalXp: 12);
          final container = _containerWith({
            GamificationStorageKeys.rewardInbox: storedCollection([
              GamificationInboxItem(
                id: 'practice-evt-3',
                createdAt: DateTime.utc(2026, 3, 1),
              ).toJson(),
            ]),
            LocalRewardLedgerRepository.storageKey: _ledgerDocument([entry]),
          });

          final event = container.read(rewardInboxItemsProvider).single.event;

          expect(event.titleKey, isNot(contains(' ')));
          expect(event.bodyKey, isNot(contains(' ')));
        },
      );
    },
  );

  group(
    'markGamificationInboxItemSeen — write-back refreshes the projection',
    () {
      test(
        'marks the matching item seen and the inbox provider reflects it',
        () async {
          final entry = _rewardEntry('practice-evt-2', totalXp: 10);
          final store = InMemoryKeyValueStore({
            GamificationStorageKeys.rewardInbox: storedCollection([
              GamificationInboxItem(
                id: 'practice-evt-2',
                createdAt: DateTime.utc(2026, 3, 2),
              ).toJson(),
            ]),
            LocalRewardLedgerRepository.storageKey: _ledgerDocument([entry]),
          });
          final container = ProviderContainer(
            overrides: [
              preferenceStoreOverride(store),
              appLoggerProvider.overrideWithValue(const NoopAppLogger()),
            ],
          );
          addTearDown(container.dispose);

          expect(container.read(inboxUnseenCountProvider), 1);
          expect(container.read(rewardInboxItemsProvider).single.seen, isFalse);

          await markGamificationInboxItemSeen(
            current: container.read(gamificationInboxProvider),
            repository: container.read(gamificationRepositoryProvider),
            id: 'practice-evt-2',
            onWritten: () => container.invalidate(gamificationInboxProvider),
          );

          expect(container.read(inboxUnseenCountProvider), 0);
          expect(container.read(rewardInboxItemsProvider).single.seen, isTrue);
        },
      );

      // Fix-round review m2: the write report (notably `trimmedCount`) was
      // previously discarded; `onReplaced` gives the caller a way to read it.
      test(
        'onReplaced receives the write report instead of it being dropped',
        () async {
          final entry = _rewardEntry('practice-evt-4', totalXp: 5);
          final store = InMemoryKeyValueStore({
            GamificationStorageKeys.rewardInbox: storedCollection([
              GamificationInboxItem(
                id: 'practice-evt-4',
                createdAt: DateTime.utc(2026, 3, 3),
              ).toJson(),
            ]),
            LocalRewardLedgerRepository.storageKey: _ledgerDocument([entry]),
          });
          final container = ProviderContainer(
            overrides: [
              preferenceStoreOverride(store),
              appLoggerProvider.overrideWithValue(const NoopAppLogger()),
            ],
          );
          addTearDown(container.dispose);

          GamificationInboxWriteReport? received;
          await markGamificationInboxItemSeen(
            current: container.read(gamificationInboxProvider),
            repository: container.read(gamificationRepositoryProvider),
            id: 'practice-evt-4',
            onWritten: () => container.invalidate(gamificationInboxProvider),
            onReplaced: (report) => received = report,
          );

          expect(received, isNotNull);
          expect(received!.trimmedCount, 0);
        },
      );
    },
  );
}
