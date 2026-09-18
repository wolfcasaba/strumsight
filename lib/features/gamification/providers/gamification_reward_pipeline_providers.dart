import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/logger_provider.dart';
import '../../../core/storage/storage_providers.dart';
import '../application/activity_event_ingestor.dart';
import '../application/reward_eligibility_policy.dart';
import '../application/reward_policy_engine.dart';
import '../data/activity_outbox_repository.dart';
import '../data/local_activity_outbox_repository.dart';
import '../infrastructure/default_reward_eligibility_policy.dart';
import '../infrastructure/default_reward_policy.dart';
import 'gamification_providers.dart';

/// The production reward pipeline (E08 R03/R05/R07 composition, wired in the
/// learner-loop XP round): feature adapters enqueue a canonical (event,
/// ledger entry) pair through [activityEventIngestorProvider]; the outbox
/// drains into the same [gamificationRewardLedgerRepositoryProvider] the
/// hub, the inbox and the practice result screen read. One ledger, one
/// outbox, one policy pair — every feature that awards XP composes these,
/// never its own copy.

/// Bounded so a stuck ledger can never grow the persisted queue without
/// limit; the drain is idempotent and re-runs on the next session.
const int activityOutboxCapacity = 64;
const int activityOutboxMaxAttempts = 3;

final activityOutboxRepositoryProvider = Provider<ActivityOutboxRepository>((
  ref,
) {
  return LocalActivityOutboxRepository(
    ledger: ref.watch(gamificationRewardLedgerRepositoryProvider),
    store: ref.watch(keyValueStoreProvider),
    logger: ref.watch(appLoggerProvider),
    capacity: activityOutboxCapacity,
    maxAttempts: activityOutboxMaxAttempts,
  );
});

final activityEventIngestorProvider = Provider<ActivityEventIngestor>((ref) {
  return ActivityEventIngestor(
    outbox: ref.watch(activityOutboxRepositoryProvider),
    logger: ref.watch(appLoggerProvider),
  );
});

final rewardEligibilityPolicyProvider = Provider<RewardEligibilityPolicy>((_) {
  return DefaultRewardEligibilityPolicy(
    config: RewardEligibilityPolicyConfig.standard(),
  );
});

final rewardPolicyProvider = Provider<RewardPolicy>((_) {
  return DefaultRewardPolicy(config: RewardPolicyConfig.standard());
});
