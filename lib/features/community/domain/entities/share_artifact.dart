/// Versioned, minimal Community share artifacts (E09-R10, ADR 0404).
///
/// The Community module exposes results from other features — practice,
/// songs, audio analysis, gamification — through a sealed hierarchy of
/// explicit, hand-picked fields. The contract is the same source of truth on
/// both sides of the wire (Flutter JSON, backend Pydantic discriminated
/// union in `backend/app/community/schemas/artifacts.py`).
///
/// ## Why a sealed hierarchy (ADR 0404 §D2)
///
/// Every artifact is an **explicit, versioned projection** of a source
/// feature's data. The Community module NEVER imports another feature's
/// internal types — only its `public.dart` barrel (§5.1, A1/A5). The
/// mapper at the source side is the seam that translates a typed source
/// value into this minimal artifact; downstream layers receive nothing
/// but the artifact's named fields.
///
/// The hierarchy is sealed so an exhaustive `switch` over `ShareArtifact`
/// is checked at compile time (a future concrete subtype cannot be added
/// without the call sites compiling it).
///
/// ## Why `type` is the discriminator (ADR 0404 §D2, brief §6.1)
///
/// Every artifact carries a `type` string literal at its root — e.g.
/// `"practiceSummary"`, `"songResult"`. The JSON round-trip and the
/// backend discriminated union both key off `type`; the field set is
/// NOT the discriminator (an unknown field set with the right keys
/// would otherwise silently decode to the wrong subtype — the exact
/// §6.1 "mezők jelenlétéből következtet típusra" failure mode).
///
/// ## Why the artifact is minimal (ADR 0404 §D2, brief §5.1)
///
/// The artifact holds nothing the wire does not need: no nyers audio,
/// no video, no waveform samples, no landmark buffers, no internal
/// device IDs, no DSP debug scores. The source features own those;
/// this contract only carries what the Community surface shows.
///
/// ## Why the schema is versioned (ADR 0404 §D3, brief §5.2)
///
/// Every artifact carries its own `schemaVersion`. The current
/// `shareArtifactSchemaVersion == 1`. Unknown or manipulated versions
/// are rejected by the backend discriminated union (a
/// `pydantic.ValidationError`) — there is no best-effort fallback
/// (a future schema bump cannot silently degrade older clients).
///
/// ## Why `sourceId` survives deletion (SDD §11.3, brief §A4 measure-matrix)
///
/// The originating source row may be deleted under retention policy
/// while the artifact still lives in the Community post — the
/// artifact's `sourceId` is the only pointer back, so it must stay
/// stable across that deletion.
library;

import 'community_post.dart';

/// The single wire-level schema version. Bumped only on a
/// backward-incompatible shape change. An artifact whose
/// `schemaVersion` differs is rejected by the backend (ADR 0404 §D3,
/// brief §5.2).
const int shareArtifactSchemaVersion = 1;

/// The closed set of `type` discriminator literals. The Pydantic
/// discriminated union on the backend mirrors this set — adding a new
/// subtype here without a matching backend case is a contract
/// violation caught by the §6.1 measure-matrix A3 cell.
enum ShareArtifactType {
  practiceSummary('practiceSummary'),
  songResult('songResult'),
  originalProgression('originalProgression'),
  planTemplate('planTemplate'),
  analysisImprovement('analysisImprovement'),
  achievement('achievement'),
  challenge('challenge');

  const ShareArtifactType(this.code);

  /// Stable wire identifier — independent of enum declaration order.
  final String code;
}

/// Resolves a wire identifier to its [ShareArtifactType] without
/// guessing a fallback. Returns `null` for an unknown value so the
/// caller can surface a precise error.
ShareArtifactType? shareArtifactTypeFromCode(String code) {
  for (final value in ShareArtifactType.values) {
    if (value.code == code) return value;
  }
  return null;
}

/// The sealed Community share-artifact hierarchy.
///
/// Every concrete subtype extends [CommunityShareArtifact] (the
/// Kör 5 base class — Kör 10 does not modify it, the round's
/// `allowed_paths` keeps `community_post.dart` off-limits). The
/// subclassing is sealed so a future concrete artifact cannot be
/// added without every exhaustive `switch` recompiling.
sealed class ShareArtifact extends CommunityShareArtifact {
  const ShareArtifact({
    required super.schemaVersion,
    required super.sourceId,
    required super.createdAt,
  });

  /// The wire discriminator. Constant per subtype — never caller-set.
  ShareArtifactType get type;

  /// The wire payload — every field is part of the public contract.
  /// The backend discriminated union enforces the field set per
  /// subtype (`extra="forbid"`); an artifact MUST list every field it
  /// carries.
  Map<String, Object?> toJson();

  /// Reverse of [toJson]. An unknown `type` is rejected — there is no
  /// best-effort fallback (ADR 0404 §D3, brief §5.2).
  static ShareArtifact fromJson(Object? json) {
    final object = _requireObject(json);
    final typeCode = _requireString(object, 'type');
    final type = shareArtifactTypeFromCode(typeCode);
    if (type == null) {
      throw ArgumentError.value(typeCode, 'type', 'is not a known artifact');
    }
    return switch (type) {
      ShareArtifactType.practiceSummary =>
        PracticeSummaryArtifact.fromJson(object),
      ShareArtifactType.songResult => SongResultArtifact.fromJson(object),
      ShareArtifactType.originalProgression =>
        OriginalProgressionArtifact.fromJson(object),
      ShareArtifactType.planTemplate =>
        PlanTemplateArtifact.fromJson(object),
      ShareArtifactType.analysisImprovement =>
        AnalysisImprovementArtifact.fromJson(object),
      ShareArtifactType.achievement => AchievementArtifact.fromJson(object),
      ShareArtifactType.challenge => ChallengeArtifact.fromJson(object),
    };
  }
}

// ---------------------------------------------------------------------------
// Practice summary (practice_share_mapper.dart)
// ---------------------------------------------------------------------------

/// Practice session result exported as a Community artifact. Carries
/// only the user-visible summary fields — total duration, attempt
/// count, finish reason, best overall score, chord canonical coaching
/// codes — no raw attempt events, no per-attempt DSP detail (ADR 0404
/// §D2, brief §5.1).
final class PracticeSummaryArtifact extends ShareArtifact {
  const PracticeSummaryArtifact({
    required super.schemaVersion,
    required super.sourceId,
    required super.createdAt,
    required this.activeSeconds,
    required this.pausedSeconds,
    required this.attemptCount,
    required this.finishReasonCode,
    this.bestScore,
    this.coachingCodes = const <String>[],
  })  : _coachingCodes = List<String>.unmodifiable(coachingCodes);

  @override
  ShareArtifactType get type => ShareArtifactType.practiceSummary;

  final int activeSeconds;
  final int pausedSeconds;
  final int attemptCount;

  /// The wire-level code of [PracticeFinishReason] — never the enum
  /// ordinal, never a stringified value. The server resolves the code
  /// independently (the discriminator pattern, ADR 0404 §D2).
  final String finishReasonCode;

  /// The best overall score in `[0.0, 1.0]`, or null when no score is
  /// available. NEVER fabricated from a missing value.
  final double? bestScore;

  final List<String> _coachingCodes;

  /// Read-only canonical coaching codes from
  /// [PracticeSessionResult.coachingSummary] (Kör 10 explicitly excludes
  /// raw per-attempt events).
  List<String> get coachingCodes => _coachingCodes;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': type.code,
        'schemaVersion': schemaVersion,
        'sourceId': sourceId,
        'createdAt': createdAt.toIso8601String(),
        'activeSeconds': activeSeconds,
        'pausedSeconds': pausedSeconds,
        'attemptCount': attemptCount,
        'finishReasonCode': finishReasonCode,
        'bestScore': bestScore,
        'coachingCodes': _coachingCodes,
      };

  static PracticeSummaryArtifact fromJson(Map<String, Object?> object) {
    return PracticeSummaryArtifact(
      schemaVersion: _requireInt(object, 'schemaVersion'),
      sourceId: _requireString(object, 'sourceId'),
      createdAt: _requireIsoDate(object, 'createdAt'),
      activeSeconds: _requireInt(object, 'activeSeconds'),
      pausedSeconds: _requireInt(object, 'pausedSeconds'),
      attemptCount: _requireInt(object, 'attemptCount'),
      finishReasonCode: _requireString(object, 'finishReasonCode'),
      bestScore: _nullableDouble(object, 'bestScore'),
      coachingCodes: _stringList(object, 'coachingCodes'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeSummaryArtifact &&
          other.schemaVersion == schemaVersion &&
          other.sourceId == sourceId &&
          other.createdAt == createdAt &&
          other.activeSeconds == activeSeconds &&
          other.pausedSeconds == pausedSeconds &&
          other.attemptCount == attemptCount &&
          other.finishReasonCode == finishReasonCode &&
          other.bestScore == bestScore &&
          _listEquals(other._coachingCodes, _coachingCodes);

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        sourceId,
        createdAt,
        activeSeconds,
        pausedSeconds,
        attemptCount,
        finishReasonCode,
        bestScore,
        Object.hashAll(_coachingCodes),
      );
}

// ---------------------------------------------------------------------------
// Song-result / original-progression / plan-template (song_share_mapper.dart)
// ---------------------------------------------------------------------------

/// A user-authored song shared as a Community artifact. Carries the
/// progression, strum pattern, tempo and time signature — no audio,
/// no internal scoring (ADR 0404 §D2).
final class SongResultArtifact extends ShareArtifact {
  const SongResultArtifact({
    required super.schemaVersion,
    required super.sourceId,
    required super.createdAt,
    required this.songName,
    required this.chords,
    required this.strumPattern,
    required this.bpm,
    required this.beatsPerBar,
  });

  @override
  ShareArtifactType get type => ShareArtifactType.songResult;

  final String songName;
  final List<String> chords;

  /// The wire-level strum pattern — one character per eighth-note slot:
  /// `d` (down), `u` (up), `-` (rest). The length is `beatsPerBar * 2`.
  final String strumPattern;

  final int bpm;
  final int beatsPerBar;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': type.code,
        'schemaVersion': schemaVersion,
        'sourceId': sourceId,
        'createdAt': createdAt.toIso8601String(),
        'songName': songName,
        'chords': chords,
        'strumPattern': strumPattern,
        'bpm': bpm,
        'beatsPerBar': beatsPerBar,
      };

  static SongResultArtifact fromJson(Map<String, Object?> object) {
    return SongResultArtifact(
      schemaVersion: _requireInt(object, 'schemaVersion'),
      sourceId: _requireString(object, 'sourceId'),
      createdAt: _requireIsoDate(object, 'createdAt'),
      songName: _requireString(object, 'songName', allowEmpty: true),
      chords: _stringList(object, 'chords'),
      strumPattern: _requireString(object, 'strumPattern'),
      bpm: _requireInt(object, 'bpm'),
      beatsPerBar: _requireInt(object, 'beatsPerBar'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongResultArtifact &&
          other.schemaVersion == schemaVersion &&
          other.sourceId == sourceId &&
          other.createdAt == createdAt &&
          other.songName == songName &&
          _listEquals(other.chords, chords) &&
          other.strumPattern == strumPattern &&
          other.bpm == bpm &&
          other.beatsPerBar == beatsPerBar;

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        sourceId,
        createdAt,
        songName,
        Object.hashAll(chords),
        strumPattern,
        bpm,
        beatsPerBar,
      );
}

/// The "original progression" angle on a [Song]. Same wire shape as
/// [SongResultArtifact] but a distinct discriminator so a future
/// server-side renderer can show "this is the user's composition"
/// rather than "this is a song they practiced".
final class OriginalProgressionArtifact extends ShareArtifact {
  const OriginalProgressionArtifact({
    required super.schemaVersion,
    required super.sourceId,
    required super.createdAt,
    required this.songName,
    required this.chords,
    required this.strumPattern,
    required this.bpm,
    required this.beatsPerBar,
  });

  @override
  ShareArtifactType get type => ShareArtifactType.originalProgression;

  final String songName;
  final List<String> chords;
  final String strumPattern;
  final int bpm;
  final int beatsPerBar;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': type.code,
        'schemaVersion': schemaVersion,
        'sourceId': sourceId,
        'createdAt': createdAt.toIso8601String(),
        'songName': songName,
        'chords': chords,
        'strumPattern': strumPattern,
        'bpm': bpm,
        'beatsPerBar': beatsPerBar,
      };

  static OriginalProgressionArtifact fromJson(Map<String, Object?> object) {
    return OriginalProgressionArtifact(
      schemaVersion: _requireInt(object, 'schemaVersion'),
      sourceId: _requireString(object, 'sourceId'),
      createdAt: _requireIsoDate(object, 'createdAt'),
      songName: _requireString(object, 'songName', allowEmpty: true),
      chords: _stringList(object, 'chords'),
      strumPattern: _requireString(object, 'strumPattern'),
      bpm: _requireInt(object, 'bpm'),
      beatsPerBar: _requireInt(object, 'beatsPerBar'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OriginalProgressionArtifact &&
          other.schemaVersion == schemaVersion &&
          other.sourceId == sourceId &&
          other.createdAt == createdAt &&
          other.songName == songName &&
          _listEquals(other.chords, chords) &&
          other.strumPattern == strumPattern &&
          other.bpm == bpm &&
          other.beatsPerBar == beatsPerBar;

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        sourceId,
        createdAt,
        songName,
        Object.hashAll(chords),
        strumPattern,
        bpm,
        beatsPerBar,
      );
}

/// A plan template built around a [Song]. Same wire shape as
/// [SongResultArtifact] but a distinct discriminator so a future
/// server-side renderer can show it as a "try this routine" rather
/// than a shared clip.
final class PlanTemplateArtifact extends ShareArtifact {
  const PlanTemplateArtifact({
    required super.schemaVersion,
    required super.sourceId,
    required super.createdAt,
    required this.songName,
    required this.chords,
    required this.strumPattern,
    required this.bpm,
    required this.beatsPerBar,
  });

  @override
  ShareArtifactType get type => ShareArtifactType.planTemplate;

  final String songName;
  final List<String> chords;
  final String strumPattern;
  final int bpm;
  final int beatsPerBar;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': type.code,
        'schemaVersion': schemaVersion,
        'sourceId': sourceId,
        'createdAt': createdAt.toIso8601String(),
        'songName': songName,
        'chords': chords,
        'strumPattern': strumPattern,
        'bpm': bpm,
        'beatsPerBar': beatsPerBar,
      };

  static PlanTemplateArtifact fromJson(Map<String, Object?> object) {
    return PlanTemplateArtifact(
      schemaVersion: _requireInt(object, 'schemaVersion'),
      sourceId: _requireString(object, 'sourceId'),
      createdAt: _requireIsoDate(object, 'createdAt'),
      songName: _requireString(object, 'songName', allowEmpty: true),
      chords: _stringList(object, 'chords'),
      strumPattern: _requireString(object, 'strumPattern'),
      bpm: _requireInt(object, 'bpm'),
      beatsPerBar: _requireInt(object, 'beatsPerBar'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlanTemplateArtifact &&
          other.schemaVersion == schemaVersion &&
          other.sourceId == sourceId &&
          other.createdAt == createdAt &&
          other.songName == songName &&
          _listEquals(other.chords, chords) &&
          other.strumPattern == strumPattern &&
          other.bpm == bpm &&
          other.beatsPerBar == beatsPerBar;

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        sourceId,
        createdAt,
        songName,
        Object.hashAll(chords),
        strumPattern,
        bpm,
        beatsPerBar,
      );
}

// ---------------------------------------------------------------------------
// Analysis improvement (analysis_share_mapper.dart)
// ---------------------------------------------------------------------------

/// A single metric's before/after movement in one analysis comparison
/// (ADR 0404 §D2). The Community surface shows the per-metric verdicts
/// — not the underlying raw measurement samples, not the comparison's
/// internal session IDs (those stay private).
final class _MetricImprovement {
  const _MetricImprovement({
    required this.metricId,
    required this.directionCode,
    required this.beforeValue,
    required this.afterValue,
    required this.relativeDelta,
  });

  final String metricId;

  /// Wire code: `improved`, `regressed`, `unchanged`, `inconclusive`.
  /// Mirrors [MetricComparisonDirection] from
  /// `audio_analysis/domain/comparison/analysis_comparison.dart` —
  /// re-declared here as a wire literal so the Community domain does
  /// NOT import audio_analysis internals.
  final String directionCode;

  final double? beforeValue;
  final double? afterValue;
  final double? relativeDelta;

  Map<String, Object?> toJson() => <String, Object?>{
        'metricId': metricId,
        'directionCode': directionCode,
        'beforeValue': beforeValue,
        'afterValue': afterValue,
        'relativeDelta': relativeDelta,
      };

  static _MetricImprovement fromJson(Map<String, Object?> object) {
    return _MetricImprovement(
      metricId: _requireString(object, 'metricId'),
      directionCode: _requireString(object, 'directionCode'),
      beforeValue: _nullableDouble(object, 'beforeValue'),
      afterValue: _nullableDouble(object, 'afterValue'),
      relativeDelta: _nullableDouble(object, 'relativeDelta'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _MetricImprovement &&
          other.metricId == metricId &&
          other.directionCode == directionCode &&
          other.beforeValue == beforeValue &&
          other.afterValue == afterValue &&
          other.relativeDelta == relativeDelta;

  @override
  int get hashCode => Object.hash(
        metricId,
        directionCode,
        beforeValue,
        afterValue,
        relativeDelta,
      );
}

/// One before/after analysis comparison, surfaced as a minimal
/// per-metric verdict set (ADR 0404 §D2). The session IDs are
/// referenced by `sourceId` only — they are NOT carried as fields
/// here (the A5 measure-matrix: nyers audio / waveform / landmark
/// are explicitly out of scope).
final class AnalysisImprovementArtifact extends ShareArtifact {
  AnalysisImprovementArtifact({
    required super.schemaVersion,
    required super.sourceId,
    required super.createdAt,
    required List<_MetricImprovement> metrics,
  }) : _metrics = List<_MetricImprovement>.unmodifiable(metrics);

  @override
  ShareArtifactType get type => ShareArtifactType.analysisImprovement;

  final List<_MetricImprovement> _metrics;

  List<_MetricImprovement> get metrics => _metrics;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': type.code,
        'schemaVersion': schemaVersion,
        'sourceId': sourceId,
        'createdAt': createdAt.toIso8601String(),
        'metrics': [for (final m in _metrics) m.toJson()],
      };

  static AnalysisImprovementArtifact fromJson(Map<String, Object?> object) {
    final rawMetrics = object['metrics'];
    if (rawMetrics is! List<Object?>) {
      throw ArgumentError.value(rawMetrics, 'metrics', 'must be a list');
    }
    return AnalysisImprovementArtifact(
      schemaVersion: _requireInt(object, 'schemaVersion'),
      sourceId: _requireString(object, 'sourceId'),
      createdAt: _requireIsoDate(object, 'createdAt'),
      metrics: <_MetricImprovement>[
        for (final raw in rawMetrics) _MetricImprovement.fromJson(
          _requireObject(raw),
        ),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnalysisImprovementArtifact &&
          other.schemaVersion == schemaVersion &&
          other.sourceId == sourceId &&
          other.createdAt == createdAt &&
          _listEquals(other._metrics, _metrics);

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        sourceId,
        createdAt,
        Object.hashAll(_metrics),
      );
}

// ---------------------------------------------------------------------------
// Achievement / Challenge (achievement_share_mapper.dart)
// ---------------------------------------------------------------------------

/// Achievement unlock shared as a Community artifact. Carries the
/// catalog id, category and progress value — no hidden objectives, no
/// hidden tier prerequisites, no localization keys (the server
/// resolves keys).
final class AchievementArtifact extends ShareArtifact {
  const AchievementArtifact({
    required super.schemaVersion,
    required super.sourceId,
    required super.createdAt,
    required this.achievementId,
    required this.categoryCode,
    required this.catalogVersion,
    required this.progressValue,
    this.completedAt,
  });

  @override
  ShareArtifactType get type => ShareArtifactType.achievement;

  /// The catalog id (e.g. `"first_strum"`) — stable snake-case id
  /// from [AchievementDefinition.id].
  final String achievementId;

  /// Wire code for [AchievementCategory] — `consistency`, `practice`,
  /// etc. The server resolves the category independently.
  final String categoryCode;

  final int catalogVersion;
  final num progressValue;
  final DateTime? completedAt;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': type.code,
        'schemaVersion': schemaVersion,
        'sourceId': sourceId,
        'createdAt': createdAt.toIso8601String(),
        'achievementId': achievementId,
        'categoryCode': categoryCode,
        'catalogVersion': catalogVersion,
        'progressValue': progressValue,
        'completedAt': completedAt?.toIso8601String(),
      };

  static AchievementArtifact fromJson(Map<String, Object?> object) {
    final completedRaw = object['completedAt'];
    final completedAt = completedRaw is String
        ? DateTime.tryParse(completedRaw)
        : null;
    if (completedRaw != null && completedAt == null) {
      throw ArgumentError.value(
        completedRaw,
        'completedAt',
        'must be an ISO date or null',
      );
    }
    return AchievementArtifact(
      schemaVersion: _requireInt(object, 'schemaVersion'),
      sourceId: _requireString(object, 'sourceId'),
      createdAt: _requireIsoDate(object, 'createdAt'),
      achievementId: _requireString(object, 'achievementId'),
      categoryCode: _requireString(object, 'categoryCode'),
      catalogVersion: _requireInt(object, 'catalogVersion'),
      progressValue: _requireNum(object, 'progressValue'),
      completedAt: completedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AchievementArtifact &&
          other.schemaVersion == schemaVersion &&
          other.sourceId == sourceId &&
          other.createdAt == createdAt &&
          other.achievementId == achievementId &&
          other.categoryCode == categoryCode &&
          other.catalogVersion == catalogVersion &&
          other.progressValue == progressValue &&
          other.completedAt == completedAt;

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        sourceId,
        createdAt,
        achievementId,
        categoryCode,
        catalogVersion,
        progressValue,
        completedAt,
      );
}

/// Daily challenge shared as a Community artifact. Carries the
/// challenge type, content identifier and reward-ledger receipt —
/// including the **rewardStatus** field that maps the existing
/// gamification `LedgerEntrySyncStatus` (verified / unverified) to
/// the Community surface (ADR 0404 §D4, brief §5.3).
///
/// The Community domain does NOT import the gamification enum
/// directly — `rewardStatusCode` is a wire literal that the mapper
/// builds and the backend discriminated union validates.
final class ChallengeArtifact extends ShareArtifact {
  const ChallengeArtifact({
    required super.schemaVersion,
    required super.sourceId,
    required super.createdAt,
    required this.challengeTypeCode,
    required this.challengeName,
    required this.rewardStatusCode,
    this.completedAt,
    this.rewardXp,
    this.ledgerId,
  });

  @override
  ShareArtifactType get type => ShareArtifactType.challenge;

  /// Wire code for [DailyChallengeType] — `strumPattern`,
  /// `chordChange`, `rhythm`, `songSection`, `timing`.
  final String challengeTypeCode;

  /// Human-readable challenge name from
  /// [StrumPatternChallenge.name] (or `contentId` for the typed
  /// subtypes). Empty is allowed for content-only challenges.
  final String challengeName;

  /// Wire code for the gamification [LedgerEntrySyncStatus] —
  /// `unverified` or `verified` (ADR 0404 §D4). The Community domain
  /// never imports the gamification enum directly; the mapper
  /// translates at the seam.
  final String rewardStatusCode;

  final DateTime? completedAt;

  /// The XP receipt value from the matched
  /// [RewardLedgerEntry.totalXp], or null when no receipt is
  /// attached yet (the challenge is in-flight or unattributed).
  final int? rewardXp;

  /// The reward-ledger entry id of the matched receipt, or null
  /// when no receipt is attached yet.
  final String? ledgerId;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': type.code,
        'schemaVersion': schemaVersion,
        'sourceId': sourceId,
        'createdAt': createdAt.toIso8601String(),
        'challengeTypeCode': challengeTypeCode,
        'challengeName': challengeName,
        'rewardStatusCode': rewardStatusCode,
        'completedAt': completedAt?.toIso8601String(),
        'rewardXp': rewardXp,
        'ledgerId': ledgerId,
      };

  static ChallengeArtifact fromJson(Map<String, Object?> object) {
    final completedRaw = object['completedAt'];
    final completedAt = completedRaw is String
        ? DateTime.tryParse(completedRaw)
        : null;
    if (completedRaw != null && completedAt == null) {
      throw ArgumentError.value(
        completedRaw,
        'completedAt',
        'must be an ISO date or null',
      );
    }
    return ChallengeArtifact(
      schemaVersion: _requireInt(object, 'schemaVersion'),
      sourceId: _requireString(object, 'sourceId'),
      createdAt: _requireIsoDate(object, 'createdAt'),
      challengeTypeCode: _requireString(object, 'challengeTypeCode'),
      challengeName: _requireString(object, 'challengeName', allowEmpty: true),
      rewardStatusCode: _requireString(object, 'rewardStatusCode'),
      completedAt: completedAt,
      rewardXp: _nullableInt(object, 'rewardXp'),
      ledgerId: _nullableString(object, 'ledgerId'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChallengeArtifact &&
          other.schemaVersion == schemaVersion &&
          other.sourceId == sourceId &&
          other.createdAt == createdAt &&
          other.challengeTypeCode == challengeTypeCode &&
          other.challengeName == challengeName &&
          other.rewardStatusCode == rewardStatusCode &&
          other.completedAt == completedAt &&
          other.rewardXp == rewardXp &&
          other.ledgerId == ledgerId;

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        sourceId,
        createdAt,
        challengeTypeCode,
        challengeName,
        rewardStatusCode,
        completedAt,
        rewardXp,
        ledgerId,
      );
}

// ---------------------------------------------------------------------------
// SharePreview — the user-facing toggle surface (D5, brief §5.1).
// ---------------------------------------------------------------------------

/// Field-level share toggles. Each flag is a preview-side decision;
/// the artifact itself is always built from the source value (A5 /
/// A6 measure-matrix). All flags default to `false` — the
/// conservative, off-by-default stance the §9.3 SDD invariant
/// demands. Toggling a flag to `true` MUST be an explicit user
/// action; a future Kör 11+ feed code reads the flags and
/// materialises the artifact.
final class SharePreview {
  const SharePreview({
    this.includeChordTimeline = false,
    this.includeStrumPattern = false,
    this.includeTempo = false,
    this.includeStreakDays = false,
    this.includeBestScore = false,
  });

  /// Surface chord-by-bar progression in the rendered card.
  final bool includeChordTimeline;

  /// Surface the per-slot down/up arrows.
  final bool includeStrumPattern;

  /// Surface the BPM readout.
  final bool includeTempo;

  /// Surface the streak-day chip (weekly recap-style artifact only).
  final bool includeStreakDays;

  /// Surface the best-score chip (practice summary only).
  final bool includeBestScore;

  /// A conservative default — every flag is `false`. The user
  /// explicitly opts into each field before the artifact is
  /// materialised (D5, brief §5.1, §9.3 invariant).
  static const SharePreview conservative = SharePreview();

  /// All-flags-off: same as [conservative] but named for the
  /// "explicit never share extras" intent (D5).
  static const SharePreview none = SharePreview();
}

// ---------------------------------------------------------------------------
// Codec helpers — pure, no I/O, no time, no random. The same shape
// is mirrored in `backend/app/community/schemas/artifacts.py`.
// ---------------------------------------------------------------------------

Map<String, Object?> _requireObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  throw ArgumentError.value(value, 'json', 'must be an object');
}

String _requireString(
  Map<String, Object?> object,
  String field, {
  bool allowEmpty = false,
}) {
  final value = object[field];
  if (value is String) {
    if (!allowEmpty && value.isEmpty) {
      throw ArgumentError.value(value, field, 'must not be empty');
    }
    return value;
  }
  throw ArgumentError.value(value, field, 'must be a string');
}

String? _nullableString(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value == null) return null;
  if (value is String) return value;
  throw ArgumentError.value(value, field, 'must be a string or null');
}

int _requireInt(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is int) return value;
  throw ArgumentError.value(value, field, 'must be an integer');
}

int? _nullableInt(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value == null) return null;
  if (value is int) return value;
  throw ArgumentError.value(value, field, 'must be an integer or null');
}

double? _nullableDouble(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  throw ArgumentError.value(value, field, 'must be a number or null');
}

num _requireNum(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is num) return value;
  throw ArgumentError.value(value, field, 'must be a number');
}

DateTime _requireIsoDate(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is! String) {
    throw ArgumentError.value(value, field, 'must be an ISO date string');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw ArgumentError.value(value, field, 'must be an ISO date string');
  }
  return parsed;
}

List<String> _stringList(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is! List<Object?>) {
    throw ArgumentError.value(value, field, 'must be a list of strings');
  }
  if (value.any((item) => item is! String)) {
    throw ArgumentError.value(value, field, 'must be a list of strings');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}