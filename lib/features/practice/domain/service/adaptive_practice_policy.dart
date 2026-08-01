import '../model/practice_attempt_result.dart';
import '../model/practice_metrics.dart';
import '../model/practice_session_config.dart';
import '../model/speed_builder_state.dart';
import '../model/tempo.dart';
import 'speed_builder_engine.dart';

export '../model/speed_builder_state.dart'
    show AdaptiveSuggestion, AdaptiveSuggestionKind, AdaptiveSuggestionReason;

abstract interface class AdaptivePracticePolicy {
  AdaptiveSuggestion? evaluate({
    required PracticeAttemptResult current,
    required List<PracticeAttemptResult> history,
    required PracticeSessionConfig config,
    bool attemptActive = false,
  });
}

/// Metric-driven adaptive policy evaluated only at attempt boundaries.
final class DefaultAdaptivePracticePolicy implements AdaptivePracticePolicy {
  const DefaultAdaptivePracticePolicy();

  static const double lowMetricThreshold = 0.70;
  static const Duration dominantTimingBias = Duration(milliseconds: 100);
  static const double tempoReductionBpm = 10;

  @override
  AdaptiveSuggestion? evaluate({
    required PracticeAttemptResult current,
    required List<PracticeAttemptResult> history,
    required PracticeSessionConfig config,
    bool attemptActive = false,
  }) {
    if (attemptActive) return null;

    final candidates = <_SuggestionCandidate>[
      _SuggestionCandidate(
        applies: _hasInsufficientSignal(current.metrics),
        suggestion: const AdaptiveSuggestion(
          reason: AdaptiveSuggestionReason.insufficientSignal,
          kind: AdaptiveSuggestionKind.retry,
        ),
      ),
      _SuggestionCandidate(
        applies: _isBelow(current.metrics.completion, lowMetricThreshold),
        suggestion: AdaptiveSuggestion(
          reason: AdaptiveSuggestionReason.lowCompletion,
          kind: AdaptiveSuggestionKind.reduceTempo,
          suggestedTempo: _reducedTempo(config.effectiveTempo),
        ),
      ),
      _SuggestionCandidate(
        applies: current.metrics.timingBias.abs() >= dominantTimingBias,
        suggestion: AdaptiveSuggestion(
          reason: AdaptiveSuggestionReason.timingBias,
          kind: config.metronomeEnabled
              ? AdaptiveSuggestionKind.shorterLoop
              : AdaptiveSuggestionKind.enableMetronome,
        ),
      ),
      _SuggestionCandidate(
        applies: _isBelow(current.metrics.direction, lowMetricThreshold),
        suggestion: const AdaptiveSuggestion(
          reason: AdaptiveSuggestionReason.directionError,
          kind: AdaptiveSuggestionKind.focusDirection,
        ),
      ),
      _SuggestionCandidate(
        applies: _isBelow(current.metrics.chord, lowMetricThreshold),
        suggestion: const AdaptiveSuggestion(
          reason: AdaptiveSuggestionReason.chordError,
          kind: AdaptiveSuggestionKind.focusChordChanges,
        ),
      ),
      _SuggestionCandidate(
        applies:
            current.outcome == PracticeAttemptOutcome.failed &&
            config.effectiveTempo.bpm > Tempo.minimumBpm,
        suggestion: AdaptiveSuggestion(
          reason: AdaptiveSuggestionReason.tempoTooHigh,
          kind: AdaptiveSuggestionKind.reduceTempo,
          suggestedTempo: _reducedTempo(config.effectiveTempo),
        ),
      ),
      _SuggestionCandidate(
        applies:
            const SpeedBuilderEngine().isStepUpPass(current) &&
            !_hasConsecutiveStepUpPasses(history, current, 3),
        suggestion: const AdaptiveSuggestion(
          reason: AdaptiveSuggestionReason.positiveReinforcement,
          kind: AdaptiveSuggestionKind.increaseTempo,
        ),
      ),
      _SuggestionCandidate(
        applies: _hasConsecutiveStepUpPasses(history, current, 3),
        suggestion: const AdaptiveSuggestion(
          reason: AdaptiveSuggestionReason.nextDifficulty,
          kind: AdaptiveSuggestionKind.nextDifficulty,
        ),
      ),
    ];

    for (final candidate in candidates) {
      if (candidate.applies) return candidate.suggestion;
    }
    return null;
  }

  static bool _hasInsufficientSignal(PracticeMetrics metrics) =>
      metrics.completion is MetricInsufficientData ||
      metrics.overall is MetricInsufficientData ||
      (metrics.totalTargets > 0 && metrics.resolvedTargets == 0);

  static bool _isBelow(MetricValue metric, double threshold) =>
      metric is MetricAvailable && metric.value < threshold;

  static Tempo _reducedTempo(Tempo current) => Tempo(
    (current.bpm - tempoReductionBpm).clamp(Tempo.minimumBpm, Tempo.maximumBpm),
  );

  static bool _hasConsecutiveStepUpPasses(
    List<PracticeAttemptResult> history,
    PracticeAttemptResult current,
    int count,
  ) {
    const engine = SpeedBuilderEngine();
    var streak = engine.isStepUpPass(current) ? 1 : 0;
    for (
      var index = history.length - 1;
      index >= 0 && streak < count;
      index--
    ) {
      if (!engine.isStepUpPass(history[index])) break;
      streak++;
    }
    return streak >= count;
  }
}

final class _SuggestionCandidate {
  const _SuggestionCandidate({required this.applies, required this.suggestion});

  final bool applies;
  final AdaptiveSuggestion suggestion;
}
