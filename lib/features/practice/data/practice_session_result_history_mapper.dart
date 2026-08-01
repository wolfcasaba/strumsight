import '../domain/model/practice_history_entry.dart';
import '../domain/model/practice_metric_snapshot.dart';
import '../domain/model/practice_session_result.dart' as presult;

/// Pure mapper: [presult.PracticeSessionResult] → [PracticeHistoryEntry].
///
/// One History V2 record per finished session. The mapper is pure, so a
/// test suite can assert the wire-shape without standing up the storage
/// stack.
class PracticeSessionResultHistoryMapper {
  const PracticeSessionResultHistoryMapper({
    required this.now,
    required this.detailEnabled,
    required this.modeCode,
    required this.sourceCode,
    required this.definitionId,
    required this.displayTitle,
    required this.skillTags,
  });

  /// Wall-clock time for the record's `createdAt`. Injected so tests can
  /// pin the timestamp.
  final DateTime Function() now;

  /// Whether per-attempt detail is persisted. When `false`, the entry
  /// records only the session summary — honors
  /// `FeatureFlags.practiceDetailedHistoryEnabled` (ADR 0084 §Döntés 12).
  final bool detailEnabled;

  /// Stable `PracticeMode.code` for the session's definition.
  final String modeCode;

  /// Stable `PracticeSource.code` for the session's origin.
  final String sourceCode;

  /// Stable practice definition ID — the natural join key with the catalog.
  final String definitionId;

  /// User-or-catalog-chosen title for display.
  final String displayTitle;

  /// Stable skill tags copied from the practice definition.
  final List<String> skillTags;

  PracticeHistoryEntry toHistoryEntry(presult.PracticeSessionResult result) {
    final finalAttempt = result.finalAttempt;
    final bestAttempt = result.bestAttempt;
    final metricSnapshot = finalAttempt == null
        ? const PracticeMetricSnapshot(
            completion: PracticeMetricDimensionNotApplicable(),
            rhythm: PracticeMetricDimensionNotApplicable(),
            direction: PracticeMetricDimensionNotApplicable(),
            chord: PracticeMetricDimensionNotApplicable(),
            overall: PracticeMetricDimensionNotApplicable(),
          )
        : PracticeMetricSnapshot.fromMetrics(finalAttempt.metrics);

    final details = <PracticeAttemptDetail>[
      if (detailEnabled)
        for (final attempt in result.attempts)
          if (attempt.index >= 0 && attempt.index < practiceHistoryDetailLimit)
            PracticeAttemptDetail(
              index: attempt.index,
              metricSnapshot: PracticeMetricSnapshot.fromMetrics(
                attempt.metrics,
              ),
            ),
    ];

    return PracticeHistoryEntry(
      id: result.id,
      modeCode: modeCode,
      sourceCode: sourceCode,
      createdAt: now().toUtc(),
      definitionId: definitionId,
      displayTitle: displayTitle,
      finishReasonCode: result.finishReason.code,
      activeDuration: result.activeDuration,
      pausedDuration: result.pausedDuration,
      attemptsCount: result.attempts.length,
      finalMetricSnapshot: metricSnapshot,
      totalTargets: finalAttempt?.metrics.totalTargets ?? 0,
      resolvedTargets: finalAttempt?.metrics.resolvedTargets ?? 0,
      scorePoints: bestAttempt?.metrics.scorePoints ?? 0,
      maxCombo: bestAttempt?.metrics.maxCombo ?? 0,
      meanAbsoluteOffset:
          bestAttempt?.metrics.meanAbsoluteOffset ?? Duration.zero,
      timingBias: bestAttempt?.metrics.timingBias ?? Duration.zero,
      coachingSummary: List<String>.unmodifiable(result.coachingSummary),
      skillTags: List<String>.unmodifiable(skillTags),
      highestStableTempoBpm: result.highestStableTempo?.bpm,
      detailAttempts: List<PracticeAttemptDetail>.unmodifiable(details),
    );
  }
}
