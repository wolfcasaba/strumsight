import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/logger_provider.dart';
import '../../../core/storage/storage_providers.dart';
import '../data/gamification_repository.dart';
import '../data/gamification_storage_schema.dart';
import '../data/local_gamification_repository.dart';
import '../data/local_reward_ledger_repository.dart';
import '../data/migration/legacy_streak_migrator.dart';
import '../data/reward_ledger_repository.dart';
import '../domain/achievements/achievement_progress.dart';
import '../domain/levels/level_curve.dart';
import '../domain/levels/level_definition.dart';
import '../domain/profile/gamification_profile.dart';
import '../domain/profile/reward_inbox_item.dart';
import '../domain/rewards/experience_points.dart';
import '../domain/rewards/reward_ledger_entry.dart';
import '../domain/rewards/reward_reason.dart';
import '../domain/streak/streak_state.dart';
import '../infrastructure/default_achievement_catalog.dart';
import '../presentation/screens/quests_screen.dart' show QuestViewProjection;
import 'achievement_evaluator.dart';
import 'daily_challenge_service.dart' show DailyChallengeInstance;
import 'streak_service.dart';

/// The gamification feature's own Riverpod composition layer (ADR 0496 §1).
///
/// Everything the router used to build ad hoc — the repository instances,
/// the level curve, the profile/streak/inbox projections — lives here so the
/// router can stay a pure consumer. Re-exported via `public.dart`.

final gamificationRepositoryProvider = Provider<GamificationRepository>((ref) {
  final repo = LocalGamificationRepository(
    store: ref.watch(keyValueStoreProvider),
    logger: ref.watch(appLoggerProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final gamificationRewardLedgerRepositoryProvider =
    Provider<RewardLedgerRepository>((ref) {
      return LocalRewardLedgerRepository(
        store: ref.watch(keyValueStoreProvider),
        logger: ref.watch(appLoggerProvider),
      );
    });

/// Single source of truth for level thresholds (moved verbatim out of the
/// router — ADR 0496 §1 forbids a baked `LevelCurve` living in the router).
final levelCurveProvider = Provider<LevelCurve>((_) {
  return LevelCurve(<LevelDefinition>[
    LevelDefinition(
      number: 1,
      levelThreshold: 0,
      titleKey: 'gamification.level.beginner',
    ),
    LevelDefinition(
      number: 2,
      levelThreshold: 100,
      titleKey: 'gamification.level.explorer',
    ),
    LevelDefinition(
      number: 3,
      levelThreshold: 250,
      titleKey: 'gamification.level.consistent',
    ),
    LevelDefinition(
      number: 4,
      levelThreshold: 500,
      titleKey: 'gamification.level.advanced',
    ),
  ]);
});

final gamificationProfileProvider = Provider<GamificationProfile>((ref) {
  final repo = ref.watch(gamificationRepositoryProvider);
  final curve = ref.watch(levelCurveProvider);
  final read = repo.readProfileSnapshot();
  final totalXp =
      read.status == GamificationReadStatus.available && read.value != null
      ? read.value!.totalXp
      : 0;
  return GamificationProfile(
    schemaVersion: gamificationProfileSchemaVersion,
    totalXp: totalXp,
    progress: curve.progressForTotalXp(totalXp),
  );
});

/// Legacy streak, read-only projection.
///
/// BACKLOG (`docs/ui/legacy-backlog.md`, E16-R01 entry 1): writing the
/// migrated result back into the V2 namespaced envelope needs a
/// `GamificationRepository` streak-write method that does not exist yet, and
/// `data/**` is this round's tilos zona — so every read re-runs the legacy
/// migration instead of persisting its result once.
///
/// A malformed legacy document makes [LegacyStreakMigrator.migrate] throw
/// [FormatException] (review m5) — caught here and logged rather than
/// crashing the hub AND the streak-detail screen on the same corrupt read.
final streakStateProvider = Provider<StreakState>((ref) {
  final store = ref.watch(keyValueStoreProvider);
  StreakState? migrated;
  try {
    migrated = LegacyStreakMigrator(store).migrate();
  } on FormatException catch (error, stackTrace) {
    ref
        .read(appLoggerProvider)
        .error(
          'gamification.streak.legacy_migration_failed',
          error: error,
          stackTrace: stackTrace,
        );
  }
  return migrated ??
      StreakState(
        current: 0,
        longest: 0,
        lastQualifiedDay: -1,
        totalQualifiedDays: 0,
        freezes: 0,
      );
});

/// Today's local epoch day — a dedicated provider (rather than an inline
/// `DateTime.now()` call) so a test can override it deterministically,
/// mirroring `DefaultStreakPolicy._epochDayFor`'s conversion.
final todayEpochDayProvider = Provider<int>((_) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
});

/// Streak-reason projection (§0.0.A/R3 #5) — the persisted [StreakState] run
/// through the existing [StreakService], with no canonical activity for
/// today (that requires a live activity stream this round does not wire).
/// The screen therefore gets the service's OWN reason for "no activity yet"
/// (e.g. `grace`/`insufficientActivity`/`plannedRest`) instead of a baked
/// `qualified`.
final streakEvaluationProvider = Provider<StreakEvaluation>((ref) {
  final previous = ref.watch(streakStateProvider);
  final epochDay = ref.watch(todayEpochDayProvider);
  return StreakService().evaluate(
    StreakEvaluationRequest(previous: previous, epochDay: epochDay),
  );
});

final gamificationInboxProvider = Provider<List<GamificationInboxItem>>((ref) {
  final repo = ref.watch(gamificationRepositoryProvider);
  final read = repo.readInbox();
  if (read.status == GamificationReadStatus.available && read.value != null) {
    return read.value!;
  }
  return const <GamificationInboxItem>[];
});

/// Counted over [rewardInboxItemsProvider] (the ledger-joined projection),
/// NOT the raw [gamificationInboxProvider] — an inbox item without a ledger
/// pair never reaches the inbox screen (R3 #8), so counting the raw list
/// would show the hub badge a higher number than the screen can ever render
/// (the false-number class this round's honesty rule forbids).
final inboxUnseenCountProvider = Provider<int>((ref) {
  return ref
      .watch(rewardInboxItemsProvider)
      .where((RewardInboxItem item) => !item.seen)
      .length;
});

/// Honest count that distinguishes "measured zero" from "not computable from
/// the currently persisted state" (ADR 0496 §2 / §0.0.A/R5) — used for
/// screen fields that require a plain non-nullable `int` and therefore
/// cannot themselves express an absence.
final class GamificationDerivedCount {
  const GamificationDerivedCount({
    required this.value,
    required this.available,
  });

  final int value;
  final bool available;
}

/// Active-quest count for the hub tile.
///
/// Quest generation needs a persisted snapshot (`plannedObjectives`,
/// `availableDays`, `baselineWeeklyMinutes`) that does not exist anywhere on
/// the tree (ADR 0496 §0.0.A/R2) — `DailyQuestGenerator`/
/// `WeeklyQuestGenerator` cannot be invoked with real state this round, so
/// the count stays `available: false` until a future round persists one.
final activeQuestCountProvider = Provider<GamificationDerivedCount>((_) {
  return const GamificationDerivedCount(value: 0, available: false);
});

/// Mastery-milestone count for the hub tile — same gap as
/// [activeQuestCountProvider]: `MasteryEvaluator.evaluate(evidence:)` needs
/// evidence that is not persisted anywhere (ADR 0496 §0.0.A/R2).
final masteryUnlockedCountProvider = Provider<GamificationDerivedCount>((_) {
  return const GamificationDerivedCount(value: 0, available: false);
});

/// Quest-board projection for the Quests screen (review B2) — same
/// "type-carried gap" as [GamificationDerivedCount]/[activeQuestCountProvider]:
/// no persisted quest snapshot exists to generate real
/// `dailyQuests`/`weeklyQuests`/`dailyChallenge` from (ADR 0496 §0.0.A/R2,
/// BACKLOG `docs/ui/legacy-backlog.md` E16-R01 entry 4), so [available]
/// stays `false` and every field stays empty. Routing this through a
/// provider (instead of a bare literal in the router) is the fix itself —
/// A2 forbids an un-measured literal even when the value happens to be the
/// screen's own legitimate empty-state contract.
final class GamificationQuestBoard {
  const GamificationQuestBoard({
    required this.dailyChallenge,
    required this.dailyChallengeAvailable,
    required this.dailyQuests,
    required this.weeklyQuests,
    required this.available,
  });

  final DailyChallengeInstance? dailyChallenge;
  final bool dailyChallengeAvailable;
  final List<QuestViewProjection> dailyQuests;
  final List<QuestViewProjection> weeklyQuests;
  final bool available;
}

final questBoardProvider = Provider<GamificationQuestBoard>((_) {
  return const GamificationQuestBoard(
    dailyChallenge: null,
    dailyChallengeAvailable: false,
    dailyQuests: <QuestViewProjection>[],
    weeklyQuests: <QuestViewProjection>[],
    available: false,
  );
});

/// Weekly-consistency day count for the streak-detail screen —
/// `StreakService.weeklyConsistency` needs a day-by-day qualified-day
/// history; only the aggregate `totalQualifiedDays` counter is persisted
/// (ADR 0496 §0.0.A/R2), so the per-day history cannot be reconstructed.
final weeklyConsistencyDaysProvider = Provider<GamificationDerivedCount>((_) {
  return const GamificationDerivedCount(value: 0, available: false);
});

/// Same "type-carried gap" as [GamificationDerivedCount] (ADR 0496 §2 /
/// §0.0.A/R5), for the one gap value that isn't a plain `int`. See review
/// M1 — `LevelDetailScreen` has no absence contract for its required
/// `ExperiencePoints` parameter, so the router still passes [value] through
/// unconditionally (BACKLOG, `docs/ui/legacy-backlog.md` E16-R01 entry 5);
/// [available] exists for parity with the three counts above and so a
/// future round that DOES add a screen-side contract has something to read.
final class GamificationDerivedExperience {
  const GamificationDerivedExperience({
    required this.value,
    required this.available,
  });

  final ExperiencePoints value;
  final bool available;
}

/// Latest-session XP breakdown for the level-detail screen.
///
/// [RewardLedgerEntry] only persists the collapsed `baseXp`+`bonusXp` view;
/// the five-component [ExperiencePoints] breakdown this screen renders is
/// not persisted anywhere (same gap class as the two counts above). Returning
/// `.empty()` avoids guessing a false split of `bonusXp` across four
/// components that were never separately recorded.
final latestSessionXpProvider = Provider<GamificationDerivedExperience>((_) {
  return GamificationDerivedExperience(
    value: ExperiencePoints.empty(),
    available: false,
  );
});

final achievementEvaluatorProvider = Provider<AchievementEvaluator>((ref) {
  return AchievementEvaluator(
    catalog: defaultAchievementCatalog,
    ledger: ref.watch(gamificationRewardLedgerRepositoryProvider),
  );
});

/// Achievement progress (§0.0.A/R3 #3) — projected through the EXISTING
/// [AchievementEvaluator.rebuild] method against the ledger's idempotent
/// receipts. No per-event evidence history is persisted (ADR 0496 §0.0.A/R2),
/// so the call supplies an empty history: every unlocked achievement is still
/// correctly reported (its receipt lives in the ledger, read by the
/// evaluator's own receipt index), while the live progress ratio for a
/// not-yet-unlocked achievement honestly reads as unknown/zero rather than
/// being re-derived by this provider.
final achievementProgressProvider =
    FutureProvider<Map<String, AchievementProgress>>((ref) async {
      final evaluator = ref.watch(achievementEvaluatorProvider);
      final result = await evaluator.rebuild(
        history: const <AchievementEvaluationEvidence>[],
      );
      return result.progressByAchievement;
    });

/// Reward-inbox projection (§0.0.A/R3 #8) — joins the storage-shaped
/// [GamificationInboxItem] (id/createdAt/viewedAt only) against the
/// [RewardLedgerRepository] by `sourceEventId == id`. An inbox item with no
/// matching ledger entry is SKIPPED rather than backed by an invented
/// [RewardEvent] (the brief's explicit "no fabricated RewardEvent" rule).
final rewardInboxItemsProvider = Provider<List<RewardInboxItem>>((ref) {
  final inboxItems = ref.watch(gamificationInboxProvider);
  if (inboxItems.isEmpty) return const <RewardInboxItem>[];

  final ledger = ref.watch(gamificationRewardLedgerRepositoryProvider);
  final entriesBySourceEventId = <String, RewardLedgerEntry>{};
  String? cursor;
  do {
    final page = ledger.readPage(limit: 100, cursor: cursor);
    for (final entry in page.entries) {
      entriesBySourceEventId[entry.sourceEventId] = entry;
    }
    // Same non-advancing-cursor guard as
    // `AchievementEvaluator._buildReceiptIndex` (review m1) — this loop
    // runs synchronously inside a provider build (UI thread), so a
    // repository bug that returns a stuck `nextCursor` would otherwise hang
    // the frame instead of failing loudly.
    if (page.nextCursor != null && page.nextCursor == cursor) {
      throw StateError('ledger page cursor did not advance');
    }
    cursor = page.nextCursor;
  } while (cursor != null);

  final items = <RewardInboxItem>[];
  for (final inboxItem in inboxItems) {
    final entry = entriesBySourceEventId[inboxItem.id];
    if (entry == null) continue;
    items.add(
      RewardInboxItem(
        id: inboxItem.id,
        event: _rewardEventFor(entry),
        addedAt: inboxItem.createdAt,
        seen: inboxItem.isViewed,
      ),
    );
  }
  return items;
});

/// Review B3 — `titleKey`/`bodyKey` are never rendered from here. This layer
/// has no `BuildContext`/`AppLocalizations`, so it cannot resolve real
/// display text, and it must not invent English literals either (the
/// composition layer is not the i18n boundary). The placeholder below is
/// discarded and replaced with an EXISTING ARB string by the router, which
/// does have `AppLocalizations` — see `_localizedRewardInboxItems` in
/// `app_router.dart`.
RewardEvent _rewardEventFor(RewardLedgerEntry entry) {
  final kind = _rewardKindFor(entry.reasonCodes);
  return RewardEvent(
    id: entry.sourceEventId,
    kind: kind,
    titleKey: kind.name,
    bodyKey: kind.name,
    earnedXp: entry.totalXp,
    earnedAt: entry.createdAt,
    sourceLedgerId: entry.ledgerId,
  );
}

RewardKind _rewardKindFor(List<RewardReason> reasonCodes) {
  if (reasonCodes.contains(RewardReason.achievementUnlocked)) {
    return RewardKind.masteryMilestone;
  }
  if (reasonCodes.contains(RewardReason.questCompleted)) {
    return RewardKind.questCompleted;
  }
  return RewardKind.dailyReward;
}

/// Marks one already-projected inbox entry as seen by writing the matching
/// [GamificationInboxItem.viewedAt] back through
/// [GamificationRepository.replaceInbox] (§0.0.A/R3 #8 — the read-side join
/// above makes this round-trip possible).
///
/// Takes its dependencies as plain values rather than a Riverpod [Ref] on
/// purpose: the production caller is a router `Consumer`'s `WidgetRef`, a
/// unit test drives a `ProviderContainer` directly, and `Ref`/`WidgetRef`
/// share no common public supertype — [onWritten] is the caller's own
/// `invalidate(gamificationInboxProvider)` call, letting either caller reuse
/// this one write-then-refresh sequence.
///
/// [onReplaced] is optional and receives the [GamificationInboxWriteReport]
/// from [GamificationRepository.replaceInbox] (review m2 — the report,
/// notably `trimmedCount`, was previously discarded silently).
Future<void> markGamificationInboxItemSeen({
  required List<GamificationInboxItem> current,
  required GamificationRepository repository,
  required String id,
  required void Function() onWritten,
  void Function(GamificationInboxWriteReport report)? onReplaced,
}) async {
  final index = current.indexWhere((item) => item.id == id);
  if (index < 0 || current[index].isViewed) return;
  final updated = List<GamificationInboxItem>.of(current);
  updated[index] = GamificationInboxItem(
    id: current[index].id,
    createdAt: current[index].createdAt,
    viewedAt: DateTime.now().toUtc(),
  );
  final report = await repository.replaceInbox(updated);
  onReplaced?.call(report);
  onWritten();
}
