import 'package:meta/meta.dart';

import 'practice_metric_snapshot.dart';
import 'practice_session_result.dart' show PracticeFinishReason;
import 'practice_validation.dart';
import 'practice_value_equality.dart';
import 'tempo.dart';

/// Schema version of the [PracticeHistoryEntry] document shape.
///
/// Bumped ONLY on a wire-incompatible change; a bump rejects older records
/// at decode time (the JsonCollectionStore logs and skips them — the user's
/// other records survive). Older builds meeting a newer schema version also
/// skip the record (see [JsonDocumentStore] future-version handling).
const int practiceHistorySchemaVersion = 1;

/// Versioned, cap-capped, idempotently-keyed session-summary record
/// (SDD §20.1, ADR 0084 §Döntés 1–4).
///
/// One record per finished practice session, keyed by [id] (the
/// [PracticeSessionResult.id]). Persisted in a [JsonCollectionStore] with
/// `maxItems = 200`; the V2 store trims the oldest record when full.
///
/// [detailAttempts] holds the last [practiceHistoryDetailLimit] attempts'
/// per-attempt metrics; older sessions keep the summary only. Raw audio is
/// never persisted.
@immutable
final class PracticeHistoryEntry {
  const PracticeHistoryEntry({
    required this.id,
    required this.modeCode,
    required this.sourceCode,
    required this.createdAt,
    required this.definitionId,
    required this.displayTitle,
    required this.finishReasonCode,
    required this.activeDuration,
    required this.pausedDuration,
    required this.attemptsCount,
    required this.finalMetricSnapshot,
    required this.totalTargets,
    required this.resolvedTargets,
    required this.scorePoints,
    required this.maxCombo,
    required this.meanAbsoluteOffset,
    required this.timingBias,
    required this.coachingSummary,
    required this.skillTags,
    this.highestStableTempoBpm,
    this.detailAttempts = const <PracticeAttemptDetail>[],
  }) : assert(
         detailAttempts.length <= practiceHistoryDetailLimit,
         'detailAttempts must not exceed the documented limit',
       ),
       assert(
         attemptsCount >= detailAttempts.length,
         'attemptsCount must cover every persisted detail attempt',
       );

  /// Session ID — the dedup key (ADR 0084 §Döntés 4).
  final String id;

  /// Stable [PracticeMode.code].
  final String modeCode;

  /// Stable `PracticeSource.code` (the *practice* domain enum, never the
  /// progress feature's namesake).
  final String sourceCode;

  final DateTime createdAt;
  final String definitionId;
  final String displayTitle;

  /// Stable [PracticeFinishReason.code].
  final String finishReasonCode;

  final Duration activeDuration;
  final Duration pausedDuration;

  /// Total attempt count, including any kept only as a summary.
  final int attemptsCount;

  /// Snapshot of the final attempt's metrics — the single source of truth
  /// for "what does the result screen render?" when detail attempts are
  /// not retained (the >20 oldest cases).
  final PracticeMetricSnapshot finalMetricSnapshot;

  final int totalTargets;
  final int resolvedTargets;
  final int scorePoints;
  final int maxCombo;

  final Duration meanAbsoluteOffset;

  /// Signed average timing error; negative = early.
  final Duration timingBias;

  /// Read-only canonical coaching codes from the controller's session-level
  /// summary, in the order they were emitted.
  final List<String> coachingSummary;

  /// Read-only stable skill tags copied from the practice definition.
  final List<String> skillTags;

  /// `null` when the session never reached a stable tempo.
  final double? highestStableTempoBpm;

  /// Per-attempt metrics for the last [practiceHistoryDetailLimit] attempts.
  ///
  /// Empty for sessions whose persisted detail window already slid past them.
  final List<PracticeAttemptDetail> detailAttempts;

  /// True when the entry still carries per-attempt detail.
  bool get hasDetailedAttempts => detailAttempts.isNotEmpty;

  /// Highest stable tempo, or `null` when none.
  Tempo? get highestStableTempo =>
      highestStableTempoBpm == null ? null : Tempo(highestStableTempoBpm!);

  /// Resolves [finishReasonCode] back to the enum, or `null` when the code
  /// is unknown (an older/newer build wrote it).
  PracticeFinishReason? get finishReason {
    for (final value in PracticeFinishReason.values) {
      if (value.code == finishReasonCode) return value;
    }
    return null;
  }

  /// Returns every independent validation problem.
  List<PracticeValidationFailure> validate() {
    final failures = <PracticeValidationFailure>[];
    if (id.isEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: 'history.entry.id.empty',
          message: 'History entry ID cannot be empty.',
        ),
      );
    }
    if (modeCode.isEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: 'history.entry.modeCode.empty',
          message: 'History entry mode code cannot be empty.',
        ),
      );
    }
    if (sourceCode.isEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: 'history.entry.sourceCode.empty',
          message: 'History entry source code cannot be empty.',
        ),
      );
    }
    if (definitionId.isEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: 'history.entry.definitionId.empty',
          message: 'History entry definition ID cannot be empty.',
        ),
      );
    }
    if (finishReasonCode.isEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: 'history.entry.finishReasonCode.empty',
          message: 'History entry finish reason code cannot be empty.',
        ),
      );
    }
    if (attemptsCount <= 0) {
      failures.add(
        const PracticeValidationFailure(
          code: 'history.entry.attemptsCount.nonPositive',
          message: 'History entry must record at least one attempt.',
        ),
      );
    }
    if (totalTargets < 0) {
      failures.add(
        const PracticeValidationFailure(
          code: 'history.entry.totalTargets.negative',
          message: 'History entry total targets cannot be negative.',
        ),
      );
    }
    if (resolvedTargets < 0 || resolvedTargets > totalTargets) {
      failures.add(
        const PracticeValidationFailure(
          code: 'history.entry.resolvedTargets.invalid',
          message: 'History entry resolved targets is out of range.',
        ),
      );
    }
    if (scorePoints < 0) {
      failures.add(
        const PracticeValidationFailure(
          code: 'history.entry.scorePoints.negative',
          message: 'History entry score points cannot be negative.',
        ),
      );
    }
    if (maxCombo < 0) {
      failures.add(
        const PracticeValidationFailure(
          code: 'history.entry.maxCombo.negative',
          message: 'History entry max combo cannot be negative.',
        ),
      );
    }
    if (meanAbsoluteOffset < Duration.zero) {
      failures.add(
        const PracticeValidationFailure(
          code: 'history.entry.meanAbsoluteOffset.negative',
          message: 'History entry mean absolute offset cannot be negative.',
        ),
      );
    }
    if (activeDuration < Duration.zero || pausedDuration < Duration.zero) {
      failures.add(
        const PracticeValidationFailure(
          code: 'history.entry.duration.negative',
          message: 'History entry durations cannot be negative.',
        ),
      );
    }
    failures.addAll(finalMetricSnapshot.validate());
    return List<PracticeValidationFailure>.unmodifiable(failures);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeHistoryEntry &&
          other.id == id &&
          other.modeCode == modeCode &&
          other.sourceCode == sourceCode &&
          other.createdAt.microsecondsSinceEpoch ==
              createdAt.microsecondsSinceEpoch &&
          other.definitionId == definitionId &&
          other.displayTitle == displayTitle &&
          other.finishReasonCode == finishReasonCode &&
          other.activeDuration == activeDuration &&
          other.pausedDuration == pausedDuration &&
          other.attemptsCount == attemptsCount &&
          other.finalMetricSnapshot == finalMetricSnapshot &&
          other.totalTargets == totalTargets &&
          other.resolvedTargets == resolvedTargets &&
          other.scorePoints == scorePoints &&
          other.maxCombo == maxCombo &&
          other.meanAbsoluteOffset == meanAbsoluteOffset &&
          other.timingBias == timingBias &&
          listEquals(other.coachingSummary, coachingSummary) &&
          listEquals(other.skillTags, skillTags) &&
          other.highestStableTempoBpm == highestStableTempoBpm &&
          listEquals(other.detailAttempts, detailAttempts);

  @override
  int get hashCode => Object.hash(
    Object.hash(
      id,
      modeCode,
      sourceCode,
      createdAt,
      definitionId,
      displayTitle,
    ),
    Object.hash(
      finishReasonCode,
      activeDuration,
      pausedDuration,
      attemptsCount,
      finalMetricSnapshot,
    ),
    Object.hash(
      totalTargets,
      resolvedTargets,
      scorePoints,
      maxCombo,
      meanAbsoluteOffset,
      timingBias,
    ),
    Object.hash(
      listHash(coachingSummary),
      listHash(skillTags),
      highestStableTempoBpm,
      listHash(detailAttempts),
    ),
  );
}

/// Maximum number of recent attempts whose per-attempt metric snapshot is
/// persisted alongside the session summary (SDD §20.2). The repository
/// trims to this limit before writing.
const int practiceHistoryDetailLimit = 20;

/// One retained attempt's metric snapshot. Capped alongside the parent
/// entry's [practiceHistoryDetailLimit] (ADR 0084 §Döntés 3).
@immutable
final class PracticeAttemptDetail {
  const PracticeAttemptDetail({
    required this.index,
    required this.metricSnapshot,
  });

  final int index;

  final PracticeMetricSnapshot metricSnapshot;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeAttemptDetail &&
          other.index == index &&
          other.metricSnapshot == metricSnapshot;

  @override
  int get hashCode => Object.hash(index, metricSnapshot);
}
