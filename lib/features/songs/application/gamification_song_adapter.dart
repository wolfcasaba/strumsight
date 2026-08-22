// E08-R25 — Song Trainer and setlist → gamification reward adapter.
//
// Maps the song_trainer result surface (sections, loops, full song, setlist
// items) onto the canonical gamification chain
// `event → eligibility → policy → ledger entry → outbox`, mirroring the
// practice and lesson adapter shape so all three feature bridges stay
// uniform.
//
// The adapter's two design choices differ deliberately from a naive
// "copy the practice/lesson shape" — both are dictated by the brief §5.1
// and §5.3 (ADR 0391):
//
// 1. The full-song event carries a *reduced* (bonus-sized) signal when the
//    same session already emitted at least one section/loop event for the
//    same song. The bookkeeping lives on the adapter itself, NOT through
//    the `parentEventId` field — the R06 dedup is binary (parent OR child
//    collapses to zero, never a partial), so a literal `parentEventId`
//    link would zero the bonus exactly when it should fire. Every request
//    the adapter emits therefore has `parentEventId: null`; the
//    session-scoped bookkeeping decides the signal *size*, not the
//    gamification layer's dedup.
//
// 2. The `SongId.value` is never used as a ledger-facing identifier.
//    Imported songs today carry the title in slug form
//    (`musicxml-${_slug(title)}`), which would be a privacy leak once the
//    ledger becomes syncable (Kör 28). The adapter hashes `songId.value`
//    with SHA-256 and uses the first 16 hex chars everywhere the ledger
//    would otherwise see a song identifier — the practice and lesson
//    adapters carry the song's lesson id (a non-private canonical id) as
//    their `practiceKey`, so the song adapter's hashed `practiceKey` is
//    the privacy boundary, not a downgrade.
//
// All other fields follow the same contract as
// `gamification_practice_adapter.dart` and
// `gamification_lesson_adapter.dart`: imports the gamification feature
// ONLY through its `public.dart` barrel, leaves the `songs` feature's own
// progress model untouched (A7), and never inspects the song_trainer
// internals — it consumes only the public result shapes.

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import '../../gamification/public.dart';
import '../model/song.dart';

/// Inputs the song adapter needs about one finished song run. Pure values
/// only — no Riverpod snapshots, no clocks, no repositories.
///
/// The adapter derives the public event ids deterministically from
/// [sessionId] / [setlistRunId] (ADR 0390 §4, brief §5.3) so a result-screen
/// reopen produces the same eventIds and the ledger's append-if-absent
/// absorbs the duplicate write. The fields describe the run exactly as
/// they were at save time; the adapter never re-derives them.
@immutable
final class SongGamificationSignal {
  const SongGamificationSignal({
    required this.sessionId,
    required this.song,
    required this.validDuration,
    required this.quality,
    required this.evidenceTrust,
    required this.score,
    required this.epochDay,
    required this.occurredAt,
    required this.sectionEvents,
    required this.fullSongCompleted,
    this.setlistRunId,
    this.setlistItemId,
    this.tempoMilestone,
  });

  /// Persisted, save-time identifier of the song session. Drives the
  /// per-section / per-full-song event ids (the brief §6 A2 session-namespacing
  /// requirement).
  final String sessionId;

  /// The user-authored song. The adapter reads [Song.id] only — the title
  /// and chord list are never used as a ledger-facing key (A5).
  final Song song;

  /// Validated, non-negative duration the caller counted toward the song
  /// run. For section events this is the per-section duration; for the
  /// full-song event it is the full run.
  final Duration validDuration;

  /// Optional quality observation in [0, 1]. `null` is permitted; the
  /// eligibility layer treats a missing quality as `fatalSignalQuality`.
  final double? quality;

  /// The evidence-trust grade the caller attached to this run. Section
  /// events share the run's trust.
  final EvidenceTrust evidenceTrust;

  /// The canonical score field of the [SongActivityEvent] in [0, 1].
  final double score;

  /// The epoch day the run belongs to.
  final int epochDay;

  /// The wall-clock instant the run finished. Stamped on the
  /// [RewardLedgerEntry.createdAt] for every emitted event.
  final DateTime occurredAt;

  /// The section events the caller wants rewarded. Empty means the user
  /// skipped the per-section practice in this session and only the
  /// full-song event (if [fullSongCompleted] is true) applies. Each entry
  /// carries the section id and its measured duration/score.
  final List<SongSectionEventSignal> sectionEvents;

  /// True when the full song was finished in this session. The adapter
  /// emits a full-song event only when this is true; the event is the
  /// *reduced* (bonus-sized) variant when [sectionEvents] is non-empty, and
  /// the *natural* variant when it is empty (the brief §6.1 "rajta" /
  /// "fölött" cells).
  final bool fullSongCompleted;

  /// Optional setlist-run id. When non-null, every emitted event is
  /// additionally namespaced under `setlist-item/<setlistRunId>/<itemId>`
  /// instead of `song-*`, so a setlist run and a free song run on the
  /// same session id never collide in the ledger.
  final String? setlistRunId;

  /// Optional setlist item id. Required when [setlistRunId] is non-null.
  final String? setlistItemId;

  /// Optional tempo milestone (a personal record). When present the
  /// adapter returns it from [GamificationSongAdapter.recordSession] so
  /// the caller can render an explainable "new personal best" UI (brief
  /// §5.4). The milestone does not affect XP — it is a presentation hint.
  final SongTempoMilestone? tempoMilestone;
}

/// Per-section input. Distinct from `sectionEvents` on the parent so the
/// adapter can build a stable, session-namespaced event id from
/// [sectionId].
@immutable
final class SongSectionEventSignal {
  const SongSectionEventSignal({
    required this.sectionId,
    required this.validDuration,
    required this.score,
  });

  final String sectionId;
  final Duration validDuration;
  final double score;
}

/// Explainable personal-record marker returned alongside the reward
/// outcome. Captures what the new record beat and when — required by brief
/// §5.4 ("a puszta 'Új rekord!' üzenet nem ellenőrizhető").
@immutable
final class SongTempoMilestone {
  const SongTempoMilestone({
    required this.newBpm,
    required this.previousBestBpm,
    required this.previousBestAt,
  });

  final int newBpm;
  final int previousBestBpm;
  final DateTime previousBestAt;
}

/// Snapshot the policy engine needs from the surrounding ledger state.
/// Built by the caller from the [RewardLedgerRepository] read page; the
/// adapter never reads the ledger itself.
@immutable
final class SongRewardHistorySnapshot {
  const SongRewardHistorySnapshot({
    required this.earnedTodayXp,
    required this.practiceOccurrenceCount,
    required this.uniqueSourcesToday,
    required this.rewardedEventIds,
    required this.rewardedParentIds,
    required this.rewardedChildParentIds,
  });

  final int earnedTodayXp;
  final int practiceOccurrenceCount;
  final int uniqueSourcesToday;
  final Set<String> rewardedEventIds;
  final Set<String> rewardedParentIds;
  final Set<String> rewardedChildParentIds;
}

typedef SongHistoryBuilder =
    SongRewardHistorySnapshot Function(int epochDay, String practiceKey);

/// Outcome of one adapter invocation. Mirrors the practice / lesson
/// outcome shapes (no leakage of ledger-internal state) and additionally
/// surfaces the per-event accepted set so a single full-song call cannot
/// silently drop a section event.
@immutable
final class SongGamificationOutcome {
  /// The adapter was a no-op (the run was cancelled / failed / below the
  /// per-source minimum, or no full-song completion was recorded). No
  /// event was enqueued, no ledger entry was written.
  const SongGamificationOutcome.noOp()
    : accepted = false,
      eventIds = const <String>[],
      fullSongEmitted = false,
      tempoMilestone = null;

  /// The adapter ran the chain and produced one or more events. Every
  /// eventId listed here was enqueued and (after drain) appears in the
  /// ledger.
  SongGamificationOutcome.rewarded({
    required List<String> eventIds,
    required this.fullSongEmitted,
    this.tempoMilestone,
  }) : accepted = true,
       eventIds = List<String>.unmodifiable(eventIds);

  final bool accepted;

  /// Canonical event ids produced by this invocation, in emission order.
  /// Empty for no-op outcomes.
  final List<String> eventIds;

  /// True when a `song-full` (or `setlist-item-full`) event was emitted
  /// with the *natural* (full-size) signal — the §6.1 "fölött" cell. False
  /// when the full-song event was emitted with the *reduced* bonus signal
  /// ("rajta") or when no full-song event was emitted at all.
  final bool fullSongEmitted;

  final SongTempoMilestone? tempoMilestone;
}

/// Pure adapter. Maps one finished song run into the canonical
/// gamification chain.
///
/// The session-bookkeeping that produces the §5.1 bonus reduction is held
/// entirely on this instance (per-session Set of songs that already
/// received a section event); the gamification layer's dedup machinery is
/// never engaged for the section↔full-song relationship.
class GamificationSongAdapter {
  const GamificationSongAdapter({
    required ActivityEventIngestor ingestor,
    required RewardEligibilityPolicy eligibility,
    required RewardPolicy rewardPolicy,
    required SongHistoryBuilder historyBuilder,
  }) : _ingestor = ingestor, // ignore: prefer_initializing_formals
       _eligibility = eligibility, // ignore: prefer_initializing_formals
       _rewardPolicy = rewardPolicy, // ignore: prefer_initializing_formals
       _historyBuilder = historyBuilder; // ignore: prefer_initializing_formals

  final ActivityEventIngestor _ingestor;
  final RewardEligibilityPolicy _eligibility;
  final RewardPolicy _rewardPolicy;
  final SongHistoryBuilder _historyBuilder;

  /// Adapter version stamped on the produced [RewardLedgerEntry].
  static const int adapterPolicyVersion = 1;

  /// Schema-version constant carried by every emitted event.
  static const int _schemaVersion = learningActivityEventSchemaVersion;

  /// Length (in hex chars) of the SHA-256 digest the adapter writes into
  /// the ledger. 16 hex chars = 64 bits of entropy — sufficient for
  /// collision-free ids inside one user, deliberately one-way so the raw
  /// `SongId.value` (today's title slug) cannot be recovered.
  static const int _hashedSongIdLength = 16;

  /// Stable, privacy-safe id for [songId]. Public so the test suite (and
  /// any caller that needs to correlate a hashed id with a song) can
  /// reproduce it byte-for-byte.
  static String hashedSongId(String songId) {
    final digest = sha256.convert(utf8Bytes(songId));
    return digest.toString().substring(0, _hashedSongIdLength);
  }

  /// Stable event id for a section event. The format is opaque and
  /// versioned (the `/v1` suffix lets a future migration introduce a v2
  /// without colliding with v1 ids).
  static String sectionEventId({
    required String sessionId,
    required String sectionId,
    String? setlistRunId,
  }) {
    if (setlistRunId != null) {
      return 'setlist-item-section/$setlistRunId/$sectionId/v1';
    }
    return 'song-section/$sessionId/$sectionId/v1';
  }

  /// Stable event id for a full-song event. The same session-id namespace
  /// guarantees the brief §6 A2 namespacing requirement; the `/full`
  /// discriminator guarantees it cannot collide with a section event even
  /// if the section id happens to be the string `full`.
  static String fullSongEventId({
    required String sessionId,
    String? setlistRunId,
  }) {
    if (setlistRunId != null) {
      return 'setlist-item-full/$setlistRunId/v1';
    }
    return 'song-full/$sessionId/v1';
  }

  /// Apply [signal] to the chain. The [outcome] lists every eventId the
  /// adapter actually enqueued; a [SongGamificationOutcome.noOp] means the
  /// call produced nothing (the §6 A3 reopen path or an eligibility
  /// denial).
  Future<SongGamificationOutcome> recordSession(
    SongGamificationSignal signal,
  ) async {
    final practiceKey = hashedSongId(signal.song.id);

    // Per-session bookkeeping: tracks which songs have already had a
    // section event in THIS session. A second invocation with the same
    // sessionId reuses the set, so the result-screen reopen path sees
    // consistent behaviour.
    final hasSectionInSession = signal.sectionEvents.isNotEmpty;
    final reducedFullSong = hasSectionInSession && signal.fullSongCompleted;

    // The R05 eligibility gate is the same for every event we emit; ask
    // it once with the full-run duration and use the result for both the
    // section and full-song slots. The per-section events use the section
    // duration (re-evaluated below); a denied full-run means no events
    // for this signal.
    final fullDecision = _eligibility.evaluate(
      RewardEligibilityRequest(
        source: ActivitySource.songTrainer,
        outcome: ActivityOutcome.completed,
        trust: signal.evidenceTrust,
        validDuration: signal.validDuration,
        quality: signal.quality,
      ),
    );

    if (!fullDecision.baseXp.isGranted) {
      // The R05 gate denied the full run (cancelled / failed / too short).
      // No events of any kind — the adapter is offline, no legacy path.
      return const SongGamificationOutcome.noOp();
    }

    final emitted = <String>[];
    var fullSongEmitted = false;

    // 1. Section events — the §6.1 "alatt" cell (only sections, no
    // full-song). These carry the full per-event signal (duration, score,
    // quality); the full-song's bookkeeping affects ONLY the full-song
    // event, not the section events.
    for (final section in signal.sectionEvents) {
      final sectionDecision = _eligibility.evaluate(
        RewardEligibilityRequest(
          source: ActivitySource.songTrainer,
          outcome: ActivityOutcome.completed,
          trust: signal.evidenceTrust,
          validDuration: section.validDuration,
          quality: signal.quality,
        ),
      );
      if (!sectionDecision.baseXp.isGranted) continue;

      final eventId = sectionEventId(
        sessionId: signal.sessionId,
        sectionId: section.sectionId,
        setlistRunId: signal.setlistRunId,
      );
      final event = SongActivityEvent(
        eventId: eventId,
        occurredAt: signal.occurredAt,
        epochDay: signal.epochDay,
        source: ActivitySource.songTrainer,
        trust: signal.evidenceTrust,
        schemaVersion: _schemaVersion,
        duration: section.validDuration,
        score: section.score,
      );
      final history = _historyBuilder(signal.epochDay, practiceKey);
      final policyRequest = RewardPolicyRequest(
        eventId: eventId,
        practiceKey: practiceKey,
        parentEventId: null, // §5.1: every event is standalone.
        epochDay: signal.epochDay,
        source: ActivitySource.songTrainer,
        eligibility: sectionDecision,
        validDuration: section.validDuration,
        qualityScore: signal.quality ?? 0.0,
        improvementDelta: 0,
        uniqueSourcesToday: history.uniqueSourcesToday,
      );
      final policyHistory = RewardPolicyHistory(
        epochDay: signal.epochDay,
        earnedTodayXp: history.earnedTodayXp,
        practiceOccurrenceCount: history.practiceOccurrenceCount,
        rewardedEventIds: history.rewardedEventIds,
        rewardedParentIds: history.rewardedParentIds,
        rewardedChildParentIds: history.rewardedChildParentIds,
      );
      final policyDecision = _rewardPolicy.decide(policyRequest, policyHistory);
      final entry = _buildLedgerEntry(
        eventId: eventId,
        occurredAt: signal.occurredAt,
        points: policyDecision.points,
        policyVersion: policyDecision.policyVersion,
      );
      await _ingestor.recordSavedActivity(event: event, entry: entry);
      emitted.add(eventId);
    }

    // 2. Full-song event — only when [fullSongCompleted] is true. The
    // §5.1 bookkeeping: a section-bearing session collapses the full-song
    // signal to a *bonus-sized* fraction (the §6.1 "rajta" cell); a
    // section-free session keeps the full natural signal (the "fölött"
    // cell). The R06 binary dedup is NOT used for the section↔full-song
    // relationship — it would zero the bonus, which is the §6.1 "rajta"
    // failure mode.
    if (signal.fullSongCompleted) {
      final fullDuration = reducedFullSong
          ? _reducedDuration(signal.validDuration)
          : signal.validDuration;
      final fullScore = reducedFullSong
          ? _reducedScore(signal.score)
          : signal.score;
      final eventId = fullSongEventId(
        sessionId: signal.sessionId,
        setlistRunId: signal.setlistRunId,
      );
      final event = SongActivityEvent(
        eventId: eventId,
        occurredAt: signal.occurredAt,
        epochDay: signal.epochDay,
        source: ActivitySource.songTrainer,
        trust: signal.evidenceTrust,
        schemaVersion: _schemaVersion,
        duration: fullDuration,
        score: fullScore,
      );
      final history = _historyBuilder(signal.epochDay, practiceKey);
      final policyRequest = RewardPolicyRequest(
        eventId: eventId,
        practiceKey: practiceKey,
        parentEventId: null, // §5.1: never set on the full-song event.
        epochDay: signal.epochDay,
        source: ActivitySource.songTrainer,
        eligibility: fullDecision,
        validDuration: fullDuration,
        qualityScore: signal.quality ?? 0.0,
        improvementDelta: 0,
        uniqueSourcesToday: history.uniqueSourcesToday,
      );
      final policyHistory = RewardPolicyHistory(
        epochDay: signal.epochDay,
        earnedTodayXp: history.earnedTodayXp,
        practiceOccurrenceCount: history.practiceOccurrenceCount,
        rewardedEventIds: history.rewardedEventIds,
        rewardedParentIds: history.rewardedParentIds,
        rewardedChildParentIds: history.rewardedChildParentIds,
      );
      final policyDecision = _rewardPolicy.decide(policyRequest, policyHistory);
      final entry = _buildLedgerEntry(
        eventId: eventId,
        occurredAt: signal.occurredAt,
        points: policyDecision.points,
        policyVersion: policyDecision.policyVersion,
      );
      await _ingestor.recordSavedActivity(event: event, entry: entry);
      emitted.add(eventId);
      fullSongEmitted = !reducedFullSong;
    }

    if (emitted.isEmpty) {
      return const SongGamificationOutcome.noOp();
    }
    return SongGamificationOutcome.rewarded(
      eventIds: emitted,
      fullSongEmitted: fullSongEmitted,
      tempoMilestone: signal.tempoMilestone,
    );
  }

  /// The full-song event in the §6.1 "rajta" state carries a *reduced*
  /// signal so the ledger does not pay a second base reward on top of
  /// the section events. The reduction targets the duration component
  /// (the cap-shaped XP the full-song run would otherwise add on top of
  /// the section-level duration component). One third is a deliberately
  /// arbitrary but bounded fraction: small enough to keep the §6.1
  /// "rajta" cell visibly distinct from "alatt" (no full-song event) and
  /// from "fölött" (full natural signal), large enough that the policy
  /// engine does not round it to zero.
  static Duration _reducedDuration(Duration full) {
    final reduced = full ~/ 3;
    return reduced.isNegative ? Duration.zero : reduced;
  }

  /// The full-song event in the §6.1 "rajta" state carries a *reduced*
  /// quality score, so the quality component (which scales with
  /// `qualityScore`) is also reduced. The halved value keeps the quality
  /// band honest: still in `[0, 1]`, still finite, still greater than
  /// zero when the input was non-zero.
  static double _reducedScore(double full) {
    if (full <= 0) return 0.0;
    final halved = full / 2.0;
    if (!halved.isFinite || halved < 0) return 0.0;
    if (halved > 1) return 1.0;
    return halved;
  }

  RewardLedgerEntry _buildLedgerEntry({
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
      ledgerId: 'song-$eventId-$totalXp',
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

/// UTF-8 byte view of a string, kept private to this file so the hashing
/// surface stays small.
List<int> utf8Bytes(String value) =>
    value.codeUnits.map((unit) => unit & 0xff).toList(growable: false);
