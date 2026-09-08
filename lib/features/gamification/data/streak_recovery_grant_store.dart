/// R34 — the persisted half of streak RECOVERY (audit §5.6,
/// `docs/ui/legacy-backlog.md` §6.2).
///
/// Measured before this round: `StreakEvaluationRequest.recoveryEligible` —
/// the ONLY recovery concept the domain has, a LOWER qualification threshold
/// for one session (`DefaultStreakPolicy` applies `minRecoveryDuration`
/// instead of `minQualifiedDuration`) — was never set to `true` anywhere in
/// `lib/`. R22 wired the broken-streak CTA to the practice hub, which is
/// where such a session starts, but nothing credited the easier threshold,
/// so the promise in `streakV2RecoveryCta` ("Start a recovery practice")
/// was navigation only.
///
/// This store is that credit, and nothing more:
///
///   * it is a GRANT, not a currency — granting twice does not stack, and a
///     grant is never bought, so there is no ledger to keep;
///   * it is SINGLE USE — the first evaluation that actually consumes it
///     clears it, so a recovery cannot silently lower every future day's bar;
///   * it is only consumed by a day that has a canonical activity. A day the
///     learner did not practise at all must not burn the grant: the request
///     type itself refuses `recoveryEligible` without an activity, and
///     spending the credit on a day it could not apply to would take the
///     recovery away for nothing.
///
/// Storage is one integer — the epoch day the grant was made on — under this
/// feature's own key namespace. A scalar needs no document envelope, and the
/// four enveloped gamification documents keep their pinned key list
/// (`GamificationStorageKeys.all`) untouched.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/key_value_store.dart';
import '../../../core/storage/storage_providers.dart';
import '../../practice_generator/public.dart' show WeeklyScheduleDecision;
import '../application/streak_service.dart';
import '../domain/activity/learning_activity_event.dart';
import '../domain/streak/streak_state.dart';

/// Reads, grants and consumes the single-use recovery credit.
final class StreakRecoveryGrantStore {
  const StreakRecoveryGrantStore({required this._store});

  /// This feature's own key. Deliberately NOT part of
  /// `GamificationStorageKeys`: that list is the enumeration of the four
  /// enveloped documents and is pinned at four by
  /// `gamification_repository_test.dart`.
  static const String storageKey = 'ss.gamification.streak_recovery_grant';

  final KeyValueStore _store;

  /// The local epoch day the recovery was granted on, or `null` when no
  /// grant is outstanding.
  int? grantedOnEpochDay() => _store.readInt(storageKey);

  /// Whether an outstanding grant covers [epochDay].
  ///
  /// The grant covers the day it was made on and every later day: the CTA
  /// says "start a recovery practice", and a learner who taps it at 23:55
  /// and practises at 00:05 must still get what they were promised. It never
  /// covers a day BEFORE the grant — that would rewrite history.
  bool appliesTo(int epochDay) {
    final granted = grantedOnEpochDay();
    return granted != null && epochDay >= granted;
  }

  /// Credits the lower threshold for the next session.
  ///
  /// Idempotent by construction: the stored value is the newest grant day,
  /// so tapping the CTA twice grants one recovery, not two.
  Future<void> grant(int epochDay) => _store.writeInt(storageKey, epochDay);

  /// Drops the outstanding grant without using it.
  Future<void> revoke() => _store.remove(storageKey);

  /// Builds the evaluation request for [epochDay], applying and CONSUMING an
  /// outstanding grant when — and only when — this day can actually use it.
  ///
  /// Returns a request whose `recoveryEligible` is `true` exactly when a
  /// grant covers [epochDay] and [activity] is present. In every other case
  /// the grant is left standing: a day with no measured activity cannot
  /// qualify under either threshold, so spending the credit there would take
  /// the recovery away for nothing.
  Future<StreakEvaluationRequest> requestFor({
    required StreakState previous,
    required int epochDay,
    LearningActivityEvent? activity,
    WeeklyScheduleDecision? weeklySchedule,
  }) async {
    final eligible = activity != null && appliesTo(epochDay);
    if (eligible) await revoke();
    return StreakEvaluationRequest(
      previous: previous,
      epochDay: epochDay,
      activity: activity,
      weeklySchedule: weeklySchedule,
      recoveryEligible: eligible,
    );
  }
}

/// Composition-root binding. `keyValueStoreProvider` has no default on
/// purpose, so a test that builds this must inject a store — the same rule
/// every other persisted surface follows.
final streakRecoveryGrantStoreProvider = Provider<StreakRecoveryGrantStore>(
  (ref) => StreakRecoveryGrantStore(store: ref.watch(keyValueStoreProvider)),
);
