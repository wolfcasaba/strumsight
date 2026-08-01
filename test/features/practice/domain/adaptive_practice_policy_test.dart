import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/practice_attempt_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_config.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/adaptive_practice_policy.dart';

void main() {
  const policy = DefaultAdaptivePracticePolicy();

  group('AdaptivePracticePolicy A7', () {
    test('same input returns the same suggestion', () {
      final current = _attempt(completion: const MetricAvailable(0.50));
      final first = policy.evaluate(
        current: current,
        history: const [],
        config: _config,
      );
      final second = policy.evaluate(
        current: current,
        history: const [],
        config: _config,
      );

      expect(first, second);
    });

    test('fixed list priority selects insufficient signal first', () {
      final suggestion = policy.evaluate(
        current: _attempt(
          completion: const MetricInsufficientData('no-signal'),
          timingBias: const Duration(milliseconds: -150),
          direction: const MetricAvailable(0.20),
        ),
        history: const [],
        config: _config,
      );

      expect(suggestion?.reason, AdaptiveSuggestionReason.insufficientSignal);
    });

    test('low completion outranks timing bias and direction error', () {
      final suggestion = policy.evaluate(
        current: _attempt(
          completion: const MetricAvailable(0.50),
          timingBias: const Duration(milliseconds: 150),
          direction: const MetricAvailable(0.20),
        ),
        history: const [],
        config: _config,
      );

      expect(suggestion?.reason, AdaptiveSuggestionReason.lowCompletion);
    });

    test('dominant timing bias outranks direction error', () {
      final suggestion = policy.evaluate(
        current: _attempt(
          timingBias: const Duration(milliseconds: -150),
          direction: const MetricAvailable(0.20),
        ),
        history: const [],
        config: _config,
      );

      expect(suggestion?.reason, AdaptiveSuggestionReason.timingBias);
    });

    test('direction error is suggested when higher priorities are absent', () {
      final suggestion = policy.evaluate(
        current: _attempt(direction: const MetricAvailable(0.20)),
        history: const [],
        config: _config,
      );

      expect(suggestion?.reason, AdaptiveSuggestionReason.directionError);
    });

    test(
      'plain passed outcome alone does not trigger a step-up suggestion',
      () {
        final suggestion = policy.evaluate(
          current: _attempt(
            completion: const MetricAvailable(0.90),
            overall: const MetricAvailable(0.75),
            outcome: PracticeAttemptOutcome.passed,
          ),
          history: const [],
          config: _config,
        );

        expect(suggestion, isNull);
      },
    );

    test('active attempt always returns null', () {
      final suggestion = policy.evaluate(
        current: _attempt(completion: const MetricAvailable(0.20)),
        history: const [],
        config: _config,
        attemptActive: true,
      );

      expect(suggestion, isNull);
    });
  });
}

const _config = PracticeSessionConfig(
  definitionId: 'test',
  definitionSnapshotVersion: 1,
  effectiveTempo: Tempo(100),
  countInBars: 1,
  loopCount: 2,
  metronomeEnabled: false,
  accentEnabled: false,
  backingEnabled: false,
  scoringProfileId: 'test',
  inputLatency: Duration.zero,
  visualLatency: Duration.zero,
  expectedChordHintEnabled: true,
  sessionTimeout: Duration(minutes: 5),
  reducedMotion: false,
);

PracticeAttemptResult _attempt({
  MetricValue completion = const MetricAvailable(0.95),
  MetricValue rhythm = const MetricAvailable(0.90),
  MetricValue direction = const MetricAvailable(0.90),
  MetricValue chord = const MetricAvailable(0.90),
  MetricValue overall = const MetricAvailable(0.90),
  Duration timingBias = Duration.zero,
  PracticeAttemptOutcome outcome = PracticeAttemptOutcome.failed,
}) => PracticeAttemptResult(
  index: 0,
  tempo: const Tempo(100),
  metrics: PracticeMetrics(
    completion: completion,
    rhythm: rhythm,
    direction: direction,
    chord: chord,
    overall: overall,
    totalTargets: 8,
    resolvedTargets: 8,
    maxCombo: 8,
    scorePoints: 0,
    meanAbsoluteOffset: Duration.zero,
    timingBias: timingBias,
  ),
  verdicts: const [],
  outcome: outcome,
);
