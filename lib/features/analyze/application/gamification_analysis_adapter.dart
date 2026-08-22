// E08-R26 — Analyze → gamification reward adapter.
//
// Maps a caller-supplied clip analysis signal onto the canonical gamification
// chain `event → eligibility → policy → ledger entry → outbox`, mirroring the
// practice / lesson / song adapter shape so every cross-feature bridge stays
// uniform.
//
// Two design choices are dictated by brief §0.0/2 and §5.4 (ADR 0392):
//
// 1. The adapter does NOT import `AnalyzeResult`. The model has no
//    `sourceHash` / `analyzerVersion` field today and the brief pins those
//    out of scope. The adapter therefore defines its own caller-fed signal
//    type — `AnalysisGamificationSignal` — that the analyze feature (a
//    future round) is expected to populate when it persists a session.
//    The ledger-side `practiceKey` is the source-hash digest, so two
//    recordings of the same clip produce the same ledger signal.
//
// 2. The dedup is on `(sourceHash, analyzerVersion)` — NOT on the clip id
//    alone. Re-running the same clip with a new analyzer version is a
//    legitimate new result (brief §5.4, the §6.1 A5 cell); re-running the
//    same clip with the SAME analyzer version is a duplicate and must be
//    collapsed. The event-id format encodes both, so the ledger's
//    append-if-absent absorbs the duplicate and a fresh version produces
//    a fresh event id.
//
// All other fields follow the same contract as the song / practice /
// lesson adapters: imports the gamification feature ONLY through its
// `public.dart` barrel, never inspects the analyze feature's internals,
// and never introduces a new network or platform call (A8).

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import '../../gamification/public.dart';

/// Inputs the analysis adapter needs about one finished analysis. Pure
/// values only — no Riverpod snapshots, no clocks, no repositories.
///
/// The adapter derives the public event id deterministically from
/// [sourceHash] and [analyzerVersion] (ADR 0392 §0.0/2) so a
/// result-screen reopen produces the same event id and the ledger's
/// append-if-absent absorbs the duplicate write.
@immutable
final class AnalysisGamificationSignal {
  const AnalysisGamificationSignal({
    required this.sessionId,
    required this.sourceHash,
    required this.analyzerVersion,
    required this.validDuration,
    required this.quality,
    required this.evidenceTrust,
    required this.score,
    required this.epochDay,
    required this.occurredAt,
  });

  /// Persisted, save-time identifier of the analysis session. The
  /// adapter namespaces the event under this id (brief §6 A2
  /// session-namespacing).
  final String sessionId;

  /// Caller-supplied stable hash of the underlying clip. Two recordings
  /// of the same clip MUST produce the same `sourceHash`. The adapter
  /// does not compute this — the analyze feature does, at save time —
  /// because the brief excludes the analyzer result from the adapter's
  /// import surface (§0.0/2).
  final String sourceHash;

  /// Caller-supplied analyzer version string (e.g. `"dsp-v3.2.0"` or
  /// `"crnn-v1.0.0"`). A new version is a legitimate new result
  /// (brief §5.4); the same version re-running on the same clip is a
  /// duplicate.
  final String analyzerVersion;

  /// Validated, non-negative duration the caller counted toward the
  /// analysis session.
  final Duration validDuration;

  /// Optional quality observation in `[0, 1]`. `null` is permitted; the
  /// eligibility layer treats a missing quality as `fatalSignalQuality`.
  final double? quality;

  /// The evidence-trust grade the caller attached to the analysis.
  final EvidenceTrust evidenceTrust;

  /// Canonical score field of the [AnalysisActivityEvent] in `[0, 1]`.
  final double score;

  /// Epoch day the analysis belongs to.
  final int epochDay;

  /// Wall-clock instant the analysis finished; stamped on the
  /// [RewardLedgerEntry.createdAt].
  final DateTime occurredAt;
}

/// Snapshot the policy engine needs from the surrounding ledger state.
/// Caller-built from the [RewardLedgerRepository] read page; the
/// adapter never reads the ledger itself.
@immutable
final class AnalysisRewardHistorySnapshot {
  const AnalysisRewardHistorySnapshot({
    required this.earnedTodayXp,
    required this.analysisOccurrenceCount,
    required this.uniqueSourcesToday,
    required this.rewardedEventIds,
    required this.rewardedParentIds,
    required this.rewardedChildParentIds,
  });

  final int earnedTodayXp;
  final int analysisOccurrenceCount;
  final int uniqueSourcesToday;
  final Set<String> rewardedEventIds;
  final Set<String> rewardedParentIds;
  final Set<String> rewardedChildParentIds;
}

typedef AnalysisHistoryBuilder =
    AnalysisRewardHistorySnapshot Function(int epochDay, String practiceKey);

/// Outcome of one adapter invocation.
@immutable
final class AnalysisGamificationOutcome {
  const AnalysisGamificationOutcome.noOp() : eventId = null, accepted = false;

  const AnalysisGamificationOutcome.rewarded({required this.eventId})
    : accepted = true;

  final String? eventId;
  final bool accepted;
}

/// Pure adapter. Maps one finished analysis session into the canonical
/// gamification chain.
///
/// The dedup discipline lives on the event-id format: same
/// `(sourceHash, analyzerVersion)` → same `eventId` → ledger collapses.
/// A different analyzer version is a fresh event id, so a legitimate
/// analyzer-version bump rewards the new analysis (brief §5.4, A5).
class GamificationAnalysisAdapter {
  const GamificationAnalysisAdapter({
    required ActivityEventIngestor ingestor,
    required RewardEligibilityPolicy eligibility,
    required RewardPolicy rewardPolicy,
    required AnalysisHistoryBuilder historyBuilder,
    required bool featureEnabled,
  }) : _ingestor = ingestor, // ignore: prefer_initializing_formals
       _eligibility = eligibility, // ignore: prefer_initializing_formals
       _rewardPolicy = rewardPolicy, // ignore: prefer_initializing_formals
       _historyBuilder = historyBuilder, // ignore: prefer_initializing_formals
       _featureEnabled = featureEnabled; // ignore: prefer_initializing_formals

  final ActivityEventIngestor _ingestor;
  final RewardEligibilityPolicy _eligibility;
  final RewardPolicy _rewardPolicy;
  final AnalysisHistoryBuilder _historyBuilder;
  final bool _featureEnabled;

  /// Adapter version stamped on the produced [RewardLedgerEntry].
  static const int adapterPolicyVersion = 1;

  /// Schema-version constant carried by every emitted event.
  static const int _schemaVersion = learningActivityEventSchemaVersion;

  /// Stable, hash-derived identifier the adapter writes into the
  /// ledger. Public so the test suite (and any caller that needs to
  /// correlate a hashed id) can reproduce it byte-for-byte. The
  /// SHA-256 first-16-hex-chars encoding mirrors the song adapter
  /// (E08-R25) for consistency.
  static String practiceKey(String sourceHash) {
    final digest = sha256.convert(utf8Bytes(sourceHash));
    return digest.toString().substring(0, 16);
  }

  /// Stable event id for an analysis event. Encodes both
  /// [sourceHash] and [analyzerVersion] so a version bump is a fresh
  /// id (A5) and a re-run with the same version collapses to the same
  /// id (A4).
  static String eventIdFor({
    required String sourceHash,
    required String analyzerVersion,
  }) {
    final key = practiceKey(sourceHash);
    return 'analysis/$key/${_safeAnalyzerVersion(analyzerVersion)}/v1';
  }

  /// Apply [signal] to the chain. Returns the resulting outcome; the
  /// caller observes [AnalysisGamificationOutcome.accepted] to know
  /// whether the outbox saw an event.
  Future<AnalysisGamificationOutcome> recordSession(
    AnalysisGamificationSignal signal,
  ) async {
    // A7 — feature-switch fallback. If the analyze feature is not
    // available in this build, the adapter is a no-op (no event, no
    // ledger entry). The brief §5.5 calls this out as the measured
    // build-stays-clean guarantee.
    if (!_featureEnabled) {
      return const AnalysisGamificationOutcome.noOp();
    }

    final decision = _eligibility.evaluate(
      RewardEligibilityRequest(
        source: ActivitySource.analyze,
        outcome: ActivityOutcome.completed,
        trust: signal.evidenceTrust,
        validDuration: signal.validDuration,
        quality: signal.quality,
      ),
    );

    if (!decision.baseXp.isGranted) {
      // R05 gate denied — too short / cancelled / failed. No event.
      return const AnalysisGamificationOutcome.noOp();
    }

    final eventId = eventIdFor(
      sourceHash: signal.sourceHash,
      analyzerVersion: signal.analyzerVersion,
    );
    final practiceKeyValue = practiceKey(signal.sourceHash);

    final event = AnalysisActivityEvent(
      eventId: eventId,
      occurredAt: signal.occurredAt,
      epochDay: signal.epochDay,
      source: ActivitySource.analyze,
      trust: signal.evidenceTrust,
      schemaVersion: _schemaVersion,
      duration: signal.validDuration,
      score: signal.score,
    );

    final history = _historyBuilder(signal.epochDay, practiceKeyValue);
    final policyRequest = RewardPolicyRequest(
      eventId: eventId,
      practiceKey: practiceKeyValue,
      parentEventId: null,
      epochDay: signal.epochDay,
      source: ActivitySource.analyze,
      eligibility: decision,
      validDuration: signal.validDuration,
      qualityScore: signal.quality ?? 0.0,
      improvementDelta: 0,
      uniqueSourcesToday: history.uniqueSourcesToday,
    );
    final policyHistory = RewardPolicyHistory(
      epochDay: signal.epochDay,
      earnedTodayXp: history.earnedTodayXp,
      practiceOccurrenceCount: history.analysisOccurrenceCount,
      rewardedEventIds: history.rewardedEventIds,
      rewardedParentIds: history.rewardedParentIds,
      rewardedChildParentIds: history.rewardedChildParentIds,
    );
    final policyDecision = _rewardPolicy.decide(policyRequest, policyHistory);

    final entry = _buildLedgerEntry(
      sessionId: signal.sessionId,
      eventId: eventId,
      practiceKey: practiceKeyValue,
      occurredAt: signal.occurredAt,
      points: policyDecision.points,
      policyVersion: policyDecision.policyVersion,
    );

    await _ingestor.recordSavedActivity(event: event, entry: entry);

    return AnalysisGamificationOutcome.rewarded(eventId: eventId);
  }

  RewardLedgerEntry _buildLedgerEntry({
    required String sessionId,
    required String eventId,
    required String practiceKey,
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
      ledgerId: 'analysis/$practiceKey/$eventId/$totalXp',
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

/// UTF-8 byte view of a string, kept private so the hashing surface
/// stays small.
List<int> utf8Bytes(String value) =>
    value.codeUnits.map((unit) => unit & 0xff).toList(growable: false);

/// Normalises an analyzer-version string into a path-safe slug so it
/// can live inside an event id. The version is opaque to the ledger
/// (the source-hash key already disambiguates clips); we only need
/// to ensure it does not contain `/` characters that would confuse
/// the id format.
String _safeAnalyzerVersion(String version) {
  return version.trim().replaceAll('/', '_');
}
