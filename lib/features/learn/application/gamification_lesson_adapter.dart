import 'package:meta/meta.dart';

import '../../gamification/public.dart';

/// The three states of the caller-fed migration switch (ADR 0390 §5). This
/// enum is duplicated locally — the practice adapter owns an identical copy
/// for the same surface, and the two adapter features deliberately do not
/// cross-import each other (public-only boundary, A4).
enum GamificationDualWriteMode { off, dual, newOnly }

/// Inputs the lesson adapter needs about one finished lesson. Pure values
/// only; the adapter never reads the lesson-progress repository or any
/// star/accuracy file (brief §5.2).
///
/// Stars and best accuracy remain in the `learn` feature's own repository;
/// this adapter only knows the canonical lesson id and the measured outcome.
@immutable
final class LessonGamificationSignal {
  const LessonGamificationSignal({
    required this.lessonId,
    required this.outcome,
    required this.validDuration,
    required this.quality,
    required this.evidenceTrust,
    required this.score,
    required this.epochDay,
    required this.occurredAt,
  }) : assert(
         outcome != ActivityOutcome.completed ||
             (validDuration >= Duration.zero),
         'validDuration must be non-negative for completed lessons',
       );

  /// The persisted lesson id. Identical to the
  /// `lesson_progress_repository.dart` key so the same canonical id drives
  /// both surfaces without a translation table.
  final String lessonId;

  /// Terminal outcome the caller classified. The lesson adapter only emits
  /// events for [ActivityOutcome.completed]; the partial / cancelled case
  /// produces no event (the result-screen handler still updates the
  /// progress map for the partial case, which is outside this adapter's
  /// scope).
  final ActivityOutcome outcome;

  final Duration validDuration;
  final double? quality;
  final EvidenceTrust evidenceTrust;

  /// The score published on the [PracticeActivityEvent]; for lessons this is
  /// typically the final accuracy normalized to [0, 1].
  final double score;

  final int epochDay;
  final DateTime occurredAt;
}

/// Outcome of a lesson-adapter invocation. Mirrors the practice adapter's
/// outcome shape but is its own type so callers can branch on the source
/// feature without leaking implementation details.
@immutable
final class LessonGamificationOutcome {
  const LessonGamificationOutcome._({
    required this.eventId,
    required this.accepted,
    required this.dualWriteInvoked,
  });

  const LessonGamificationOutcome.noOp()
    : eventId = null,
      accepted = false,
      dualWriteInvoked = false;

  const LessonGamificationOutcome.rewarded({
    required String eventId,
    required bool dualWriteInvoked,
  }) : eventId = eventId,
       accepted = true,
       dualWriteInvoked = dualWriteInvoked;

  final String? eventId;
  final bool accepted;
  final bool dualWriteInvoked;
}

/// Snapshot the policy engine needs from the surrounding ledger state.
@immutable
final class LessonRewardHistorySnapshot {
  const LessonRewardHistorySnapshot({
    required this.earnedTodayXp,
    required this.lessonOccurrenceCount,
    required this.uniqueSourcesToday,
    required this.rewardedEventIds,
    required this.rewardedParentIds,
    required this.rewardedChildParentIds,
  });

  final int earnedTodayXp;

  /// How many times this lesson has already been rewarded today.
  final int lessonOccurrenceCount;
  final int uniqueSourcesToday;
  final Set<String> rewardedEventIds;
  final Set<String> rewardedParentIds;
  final Set<String> rewardedChildParentIds;
}

/// Snapshot builder for the lesson adapter. The lesson feature knows how to
/// read the ledger slice that matters for the current lesson; the adapter
/// never touches the [LessonProgressRepository].
typedef LessonHistoryBuilder =
    LessonRewardHistorySnapshot Function(int epochDay, String lessonId);

/// Signature for the legacy statistics sink invoked in dual-write mode. The
/// sink receives the [LessonGamificationSignal] verbatim — it cannot
/// fabricate a [RewardLedgerEntry] from this surface, so it cannot
/// double-write XP through the ledger (A7 defense).
typedef LessonLegacySink =
    Future<void> Function(LessonGamificationSignal signal);

/// Pure adapter: maps one finished lesson into the canonical gamification
/// chain. Mirrors the practice adapter's structure but pins the source to
/// [ActivitySource.learn] and never reads the lesson-progress repository
/// (brief §5.2 — stars stay in the `learn` feature).
///
/// Imports the gamification feature ONLY through its [public.dart] barrel
/// (A4, public-only boundary).
class GamificationLessonAdapter {
  const GamificationLessonAdapter({
    required ActivityEventIngestor ingestor,
    required RewardEligibilityPolicy eligibility,
    required RewardPolicy rewardPolicy,
    required LessonHistoryBuilder historyBuilder,
    required GamificationDualWriteMode dualWriteMode,
    required LessonLegacySink legacySink,
  }) : _ingestor = ingestor,
       _eligibility = eligibility,
       _rewardPolicy = rewardPolicy,
       _historyBuilder = historyBuilder,
       _dualWriteMode = dualWriteMode,
       _legacySink = legacySink;

  final ActivityEventIngestor _ingestor;
  final RewardEligibilityPolicy _eligibility;
  final RewardPolicy _rewardPolicy;
  final LessonHistoryBuilder _historyBuilder;
  final GamificationDualWriteMode _dualWriteMode;
  final LessonLegacySink _legacySink;

  /// Adapter version stamped on the produced [RewardLedgerEntry]. Bumped only
  /// when the wiring logic itself changes.
  static const int adapterPolicyVersion = 1;

  static const int _schemaVersion = learningActivityEventSchemaVersion;

  /// Stable event id derived from the lesson id (ADR 0390 §4). Distinct
  /// prefix from the practice adapter so the two event streams never share
  /// ids.
  static String stableEventId(String lessonId) => 'learn-lesson/$lessonId/v1';

  Future<LessonGamificationOutcome> recordLesson(
    LessonGamificationSignal signal,
  ) async {
    if (_dualWriteMode == GamificationDualWriteMode.off) {
      return const LessonGamificationOutcome.noOp();
    }

    // Lesson events are emitted only on completed lessons. The
    // lesson-progress repository continues to update partial sessions on its
    // own — this adapter deliberately does not reach into it.
    if (signal.outcome != ActivityOutcome.completed) {
      return const LessonGamificationOutcome.noOp();
    }

    final decision = _eligibility.evaluate(
      RewardEligibilityRequest(
        source: ActivitySource.learn,
        outcome: signal.outcome,
        trust: signal.evidenceTrust,
        validDuration: signal.validDuration,
        quality: signal.quality,
      ),
    );

    if (!decision.baseXp.isGranted) {
      return const LessonGamificationOutcome.noOp();
    }

    final eventId = stableEventId(signal.lessonId);
    final event = PracticeActivityEvent(
      eventId: eventId,
      occurredAt: signal.occurredAt,
      epochDay: signal.epochDay,
      source: ActivitySource.learn,
      trust: signal.evidenceTrust,
      schemaVersion: _schemaVersion,
      duration: signal.validDuration,
      score: signal.score,
    );

    final history = _historyBuilder(signal.epochDay, signal.lessonId);
    final policyRequest = RewardPolicyRequest(
      eventId: eventId,
      practiceKey: signal.lessonId,
      parentEventId: null,
      epochDay: signal.epochDay,
      source: ActivitySource.learn,
      eligibility: decision,
      validDuration: signal.validDuration,
      qualityScore: signal.quality ?? 0.0,
      improvementDelta: 0,
      uniqueSourcesToday: history.uniqueSourcesToday,
    );
    final policyHistory = RewardPolicyHistory(
      epochDay: signal.epochDay,
      earnedTodayXp: history.earnedTodayXp,
      practiceOccurrenceCount: history.lessonOccurrenceCount,
      rewardedEventIds: history.rewardedEventIds,
      rewardedParentIds: history.rewardedParentIds,
      rewardedChildParentIds: history.rewardedChildParentIds,
    );
    final policyDecision = _rewardPolicy.decide(policyRequest, policyHistory);
    final points = policyDecision.points;

    final entry = _buildLedgerEntry(
      lessonId: signal.lessonId,
      eventId: eventId,
      occurredAt: signal.occurredAt,
      points: points,
      policyVersion: policyDecision.policyVersion,
    );

    await _ingestor.recordSavedActivity(event: event, entry: entry);

    final invokedLegacy = _dualWriteMode == GamificationDualWriteMode.dual;
    if (invokedLegacy) {
      await _legacySink(signal);
    }

    return LessonGamificationOutcome.rewarded(
      eventId: eventId,
      dualWriteInvoked: invokedLegacy,
    );
  }

  RewardLedgerEntry _buildLedgerEntry({
    required String lessonId,
    required String eventId,
    required DateTime occurredAt,
    required ExperiencePoints points,
    required int policyVersion,
  }) {
    final baseXp = points.baseXp;
    final bonusXp =
        points.durationXp +
        points.qualityXp +
        points.improvementXp +
        points.diversityXp;
    final totalXp = points.totalXp;
    return RewardLedgerEntry(
      ledgerId: 'learn-$lessonId-${points.totalXp}',
      sourceEventId: eventId,
      createdAt: occurredAt,
      schemaVersion: rewardLedgerEntrySchemaVersion,
      policyVersion: policyVersion,
      baseXp: baseXp,
      bonusXp: bonusXp,
      totalXp: totalXp,
      reasonCodes: <RewardReason>[
        if (totalXp > 0) RewardReason.baseExperience,
        ...points.reductionReasons,
      ],
    );
  }
}
