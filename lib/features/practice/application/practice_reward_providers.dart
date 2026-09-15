import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../gamification/public.dart';
import 'gamification_practice_adapter.dart';
import 'practice_reward_recorder.dart';

/// The production [GamificationPracticeAdapter] over the shared reward
/// pipeline (learner-loop XP round, ADR 0283 §Döntés 4 "future composition
/// root"). Mode is `newOnly`: the Practice V2 session has no legacy
/// statistics sink of its own to dual-write (the V1 log/streak credit is
/// the Learn and Song Trainer flows' `PracticeSessionRecording`, which the
/// V2 session never called), so there is nothing to run in parallel and
/// nothing to double-count.
final practiceGamificationAdapterProvider =
    Provider<GamificationPracticeAdapter>((ref) {
      final ledger = ref.watch(gamificationRewardLedgerRepositoryProvider);
      return GamificationPracticeAdapter(
        ingestor: ref.watch(activityEventIngestorProvider),
        eligibility: ref.watch(rewardEligibilityPolicyProvider),
        rewardPolicy: ref.watch(rewardPolicyProvider),
        historyBuilder: (epochDay, _) =>
            practiceRewardHistorySnapshotFromLedger(ledger, epochDay: epochDay),
        dualWriteMode: GamificationDualWriteMode.newOnly,
        legacySink: _noLegacySink,
      );
    });

Future<void> _noLegacySink(PracticeGamificationSignal _) async {}
