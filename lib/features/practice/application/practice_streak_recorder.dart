import '../../../core/foundation/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../streak/public.dart';
import '../domain/model/practice_session_result.dart' as presult;
import '../domain/repository/practice_session_recorder.dart';
import '../domain/service/practice_session_eligibility.dart';

/// Credits the practice streak for a saved Practice V2 session (learner-loop
/// round 4, "one progress model"). Before this round a V2 session never
/// touched the streak: only Learn (through `PracticeSessionRecording`) and
/// Live (directly) did, so the Today and Profile hubs could show a zero
/// streak to a learner who had just finished a scored practice.
///
/// The gate is the canonical [PracticeSessionEligibility] predicate — the
/// same one Learn uses — and the credit is [StreakController]'s idempotent
/// per-day call. The V1 practice log is deliberately NOT written: the
/// aggregated feed already unions the V2 history with the V1 log, so a V1
/// mirror entry would double-count the session on the daily goal.
class StreakCreditingPracticeSessionRecorder
    implements PracticeSessionRecorder {
  const StreakCreditingPracticeSessionRecorder({
    required PracticeSessionRecorder inner,
    required StreakController streak,
    required PracticeSessionEligibility eligibility,
    required DateTime Function() now,
    required AppLogger logger,
  }) : _inner = inner, // ignore: prefer_initializing_formals
       _streak = streak, // ignore: prefer_initializing_formals
       _eligibility = eligibility, // ignore: prefer_initializing_formals
       _now = now, // ignore: prefer_initializing_formals
       _logger = logger; // ignore: prefer_initializing_formals

  final PracticeSessionRecorder _inner;
  final StreakController _streak;
  final PracticeSessionEligibility _eligibility;
  final DateTime Function() _now;
  final AppLogger _logger;

  @override
  Future<AppResult<void>> record(presult.PracticeSessionResult result) async {
    final saved = await _inner.record(result);
    if (saved is Failure<void>) return saved;
    if (!practiceSessionCreditsStreak(result, _eligibility)) return saved;
    try {
      await _streak.recordPracticeToday(_now());
    } catch (error, stackTrace) {
      _logger.warning(
        'practice_streak_credit_failed',
        error: error,
        stackTrace: stackTrace,
        fields: <String, Object?>{'sessionId': result.id},
      );
    }
    return saved;
  }
}

/// Pure: does [result] count as a real practice moment for the streak?
/// Cancelled/failed sessions never do; otherwise the canonical predicate
/// decides from the active time and the resolved targets of the final
/// attempt (V2 free practice reports no strum count, so that branch of the
/// predicate stays at zero and the active-time threshold carries it).
bool practiceSessionCreditsStreak(
  presult.PracticeSessionResult result,
  PracticeSessionEligibility eligibility,
) {
  switch (result.finishReason) {
    case presult.PracticeFinishReason.cancelled:
    case presult.PracticeFinishReason.failed:
    case presult.PracticeFinishReason.interrupted:
      return false;
    case presult.PracticeFinishReason.completedAllTargets:
    case presult.PracticeFinishReason.userFinished:
    case presult.PracticeFinishReason.timedOut:
      break;
  }
  return eligibility.isEligible(
    PracticeSessionEligibilityInput(
      activeDuration: result.activeDuration,
      resolvedRequiredTargets:
          result.finalAttempt?.metrics.resolvedTargets ?? 0,
      freePracticeStrums: 0,
    ),
  );
}
