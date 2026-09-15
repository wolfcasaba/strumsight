import '../../../core/foundation/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../gamification/public.dart';
import '../../streak/public.dart';
import '../domain/model/practice_metrics.dart';
import '../domain/model/practice_session_result.dart' as presult;
import '../domain/repository/practice_session_recorder.dart';
import 'gamification_practice_adapter.dart';

/// The production [PracticeSessionRecorder] composition (learner-loop XP
/// round): persists the session through [inner] exactly as before, and —
/// only after that save succeeded — feeds the session to the gamification
/// chain ([GamificationPracticeAdapter] → outbox → ledger) and drains the
/// outbox, so the result screen's reward card reads a real ledger entry the
/// moment it opens.
///
/// A reward failure can NEVER fail the session: the adapter/drain run
/// inside a guard, the [AppResult] of the history save is what the caller
/// gets back, and the outbox re-drains on the next session anyway.
class RewardingPracticeSessionRecorder implements PracticeSessionRecorder {
  const RewardingPracticeSessionRecorder({
    required PracticeSessionRecorder inner,
    required GamificationPracticeAdapter adapter,
    required ActivityEventIngestor ingestor,
    required String definitionId,
    required DateTime Function() now,
    required AppLogger logger,
  }) : _inner = inner, // ignore: prefer_initializing_formals
       _adapter = adapter, // ignore: prefer_initializing_formals
       _ingestor = ingestor, // ignore: prefer_initializing_formals
       _definitionId = definitionId, // ignore: prefer_initializing_formals
       _now = now, // ignore: prefer_initializing_formals
       _logger = logger; // ignore: prefer_initializing_formals

  final PracticeSessionRecorder _inner;
  final GamificationPracticeAdapter _adapter;
  final ActivityEventIngestor _ingestor;
  final String _definitionId;
  final DateTime Function() _now;
  final AppLogger _logger;

  @override
  Future<AppResult<void>> record(presult.PracticeSessionResult result) async {
    final saved = await _inner.record(result);
    if (saved is Failure<void>) return saved;
    try {
      final signal = practiceGamificationSignalFor(
        result,
        definitionId: _definitionId,
        now: _now(),
      );
      final outcome = await _adapter.recordSession(signal);
      if (outcome.accepted) await _ingestor.drain();
    } catch (error, stackTrace) {
      _logger.warning(
        'practice_reward_failed',
        error: error,
        stackTrace: stackTrace,
        fields: <String, Object?>{'sessionId': result.id},
      );
    }
    return saved;
  }
}

/// Pure mapping of a finished session onto the gamification signal — no
/// clock and no provider inside, so the cells can pin every field.
///
/// * outcome: finished/completed/timed-out sessions are `completed`
///   (whether they earn XP is the eligibility gate's call — a 30-second
///   session is denied there, honestly); cancelled/interrupted are
///   `cancelled`; failed is `failed`.
/// * quality: the best attempt's overall score when it is an available,
///   in-range metric; `null` otherwise (free practice, aborted before an
///   attempt) — the gate treats a missing quality as fatal, so a session
///   without a score never earns quality XP it did not measure.
/// * trust: `scored` when the session was scored, `deviceObserved`
///   otherwise — the app never claims more than it measured.
PracticeGamificationSignal practiceGamificationSignalFor(
  presult.PracticeSessionResult result, {
  required String definitionId,
  required DateTime now,
}) {
  final overall = result.bestAttempt?.metrics.overall;
  final quality = overall is MetricAvailable ? overall.value : null;
  return PracticeGamificationSignal(
    sessionId: result.id,
    lessonId: definitionId,
    outcome: switch (result.finishReason) {
      presult.PracticeFinishReason.completedAllTargets ||
      presult.PracticeFinishReason.userFinished ||
      presult.PracticeFinishReason.timedOut => ActivityOutcome.completed,
      presult.PracticeFinishReason.cancelled ||
      presult.PracticeFinishReason.interrupted => ActivityOutcome.cancelled,
      presult.PracticeFinishReason.failed => ActivityOutcome.failed,
    },
    validDuration: result.activeDuration,
    quality: quality,
    evidenceTrust: quality == null
        ? EvidenceTrust.deviceObserved
        : EvidenceTrust.scored,
    score: quality ?? 0.0,
    epochDay: StreakLogic.epochDayOf(now),
    occurredAt: now,
  );
}

/// Today's policy inputs, read from the ledger the reward chain writes to
/// (the adapter never reads the ledger itself). Bounded page walk with the
/// same non-advancing-cursor guard the gamification projections use.
PracticeRewardHistorySnapshot practiceRewardHistorySnapshotFromLedger(
  RewardLedgerRepository ledger, {
  required int epochDay,
}) {
  const pageSize = 100;
  const maxPages = 50;
  var earnedTodayXp = 0;
  var practiceOccurrenceCount = 0;
  final sourcesToday = <String>{};
  final rewardedEventIds = <String>{};
  String? cursor;
  for (var page = 0; page < maxPages; page++) {
    final result = ledger.readPage(limit: pageSize, cursor: cursor);
    for (final entry in result.entries) {
      rewardedEventIds.add(entry.sourceEventId);
      if (StreakLogic.epochDayOf(entry.createdAt) != epochDay) continue;
      earnedTodayXp += entry.totalXp;
      final source = entry.sourceEventId.split('/').first;
      sourcesToday.add(source);
      if (entry.sourceEventId.startsWith('practice-session/')) {
        practiceOccurrenceCount++;
      }
    }
    final next = result.nextCursor;
    if (next == null || next == cursor) break;
    cursor = next;
  }
  // The session being rewarded adds its own source to today's mix.
  final uniqueSourcesToday =
      sourcesToday.length + (sourcesToday.contains('practice-session') ? 0 : 1);
  return PracticeRewardHistorySnapshot(
    earnedTodayXp: earnedTodayXp,
    practiceOccurrenceCount: practiceOccurrenceCount,
    uniqueSourcesToday: uniqueSourcesToday,
    rewardedEventIds: rewardedEventIds,
    rewardedParentIds: const <String>{},
    rewardedChildParentIds: const <String>{},
  );
}
