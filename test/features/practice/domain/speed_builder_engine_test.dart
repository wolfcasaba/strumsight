import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/practice_attempt_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/speed_builder_policy.dart';
import 'package:strumsight/features/practice/domain/model/speed_builder_state.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/speed_builder_engine.dart';

void main() {
  const engine = SpeedBuilderEngine();

  group('SpeedBuilderEngine', () {
    test('A2 — two step-up passes advance once and reset streak', () {
      final policy = _policy();
      var state = SpeedBuilderState.initial(policy);

      state = engine.record(state, _attempt(0, 80, stepUpPass: true));
      expect(state.currentTempo, const Tempo(80));
      expect(state.successStreak, 1);

      state = engine.record(state, _attempt(1, 80, stepUpPass: true));
      expect(state.currentTempo, const Tempo(90));
      expect(state.successStreak, 0);

      state = engine.record(state, _attempt(2, 90, stepUpPass: true));
      expect(state.currentTempo, const Tempo(90));
      expect(state.successStreak, 1);

      state = engine.record(state, _attempt(3, 90, stepUpPass: false));
      expect(state.successStreak, 0);

      state = engine.record(state, _attempt(4, 90, stepUpPass: true));
      expect(state.currentTempo, const Tempo(90));
      expect(state.successStreak, 1);
    });

    test('step-up pass uses metrics rather than plain passed outcome', () {
      final policy = _policy(requiredConsecutivePasses: 1);
      var state = SpeedBuilderState.initial(policy);
      state = engine.record(
        state,
        _attempt(
          0,
          80,
          completion: const MetricAvailable(0.90),
          overall: const MetricAvailable(0.75),
          rhythm: const MetricAvailable(0.90),
          outcome: PracticeAttemptOutcome.passed,
        ),
      );
      expect(state.currentTempo, const Tempo(80));
      expect(state.failStreak, 1);

      state = engine.record(
        state,
        _attempt(
          1,
          80,
          completion: const MetricAvailable(0.95),
          overall: const MetricAvailable(0.85),
          rhythm: const MetricNotApplicable(),
          outcome: PracticeAttemptOutcome.failed,
        ),
      );
      expect(state.currentTempo, const Tempo(90));
    });

    test('insufficient or unavailable required metrics cannot step up', () {
      final policy = _policy(requiredConsecutivePasses: 1);
      for (final attempt in <PracticeAttemptResult>[
        _attempt(0, 80, completion: const MetricInsufficientData('no-signal')),
        _attempt(0, 80, overall: const MetricNotApplicable()),
        _attempt(0, 80, rhythm: const MetricInsufficientData('no-rhythm')),
        _attempt(0, 80, rhythm: const MetricAvailable(0.79)),
      ]) {
        final state = engine.record(SpeedBuilderState.initial(policy), attempt);
        expect(state.currentTempo, const Tempo(80));
        expect(state.failStreak, 1);
      }
    });

    test('A3 — two fails step down but never below start', () {
      final policy = _policy();
      var state = SpeedBuilderState.initial(policy);
      state = engine.record(state, _attempt(0, 80, stepUpPass: true));
      state = engine.record(state, _attempt(1, 80, stepUpPass: true));
      expect(state.currentTempo, const Tempo(90));

      state = engine.record(state, _attempt(2, 90, stepUpPass: false));
      expect(state.currentTempo, const Tempo(90));
      state = engine.record(state, _attempt(3, 90, stepUpPass: false));
      expect(state.currentTempo, const Tempo(80));
      expect(state.failStreak, 0);

      state = engine.record(state, _attempt(4, 80, stepUpPass: false));
      state = engine.record(state, _attempt(5, 80, stepUpPass: false));
      expect(state.currentTempo, const Tempo(80));
      expect(state.failStreak, 0);
    });

    test('A3/A4 — target bound is closed and completion needs full streak', () {
      final policy = _policy(startBpm: 110, targetBpm: 120);
      var state = SpeedBuilderState.initial(policy);
      state = engine.record(state, _attempt(0, 110, stepUpPass: true));
      state = engine.record(state, _attempt(1, 110, stepUpPass: true));
      expect(state.currentTempo, const Tempo(120));
      expect(state.status, SpeedBuilderStatus.active);

      state = engine.record(state, _attempt(2, 120, stepUpPass: true));
      expect(state.status, SpeedBuilderStatus.active);
      state = engine.record(state, _attempt(3, 120, stepUpPass: true));
      expect(state.status, SpeedBuilderStatus.completed);
      expect(state.currentTempo, const Tempo(120));
      expect(state.successStreak, 0);
    });

    test('A5 — max attempts closes idempotently', () {
      final policy = _policy(maxAttempts: 3);
      var state = SpeedBuilderState.initial(policy);
      for (var index = 0; index < 3; index++) {
        state = engine.record(state, _attempt(index, 80, stepUpPass: false));
      }
      expect(state.status, SpeedBuilderStatus.maxAttemptsReached);
      final closed = state;
      expect(
        engine.record(state, _attempt(3, 80, stepUpPass: true)),
        same(closed),
      );
    });

    test('A5 — user finish preserves history and stable BPM', () {
      final policy = _policy();
      var state = SpeedBuilderState.initial(policy);
      state = engine.record(state, _attempt(0, 80, stepUpPass: true));
      state = engine.record(state, _attempt(1, 80, stepUpPass: true));
      final finished = engine.finish(state);

      expect(finished.status, SpeedBuilderStatus.userFinished);
      expect(finished.attempts, state.attempts);
      expect(finished.highestStableTempo, const Tempo(80));
      expect(engine.finish(finished), same(finished));
    });

    test('finish derives stable BPM from preserved history', () {
      final policy = _policy();
      final restored = SpeedBuilderState(
        policy: policy,
        currentTempo: const Tempo(90),
        successStreak: 0,
        failStreak: 0,
        attempts: [
          _attempt(0, 80, stepUpPass: true),
          _attempt(1, 80, stepUpPass: true),
        ],
        highestStableTempo: null,
        status: SpeedBuilderStatus.active,
      );

      final finished = engine.finish(restored);

      expect(finished.highestStableTempo, const Tempo(80));
      expect(finished.attempts, restored.attempts);
    });

    test('A6 — highest stable BPM requires consecutive passes per tempo', () {
      final cases =
          <({List<({double bpm, bool pass})> sequence, Tempo? expected})>[
            (
              sequence: [
                (bpm: 80, pass: true),
                (bpm: 80, pass: true),
                (bpm: 90, pass: true),
                (bpm: 90, pass: false),
              ],
              expected: const Tempo(80),
            ),
            (
              sequence: [
                (bpm: 80, pass: true),
                (bpm: 80, pass: true),
                (bpm: 90, pass: true),
                (bpm: 90, pass: true),
              ],
              expected: const Tempo(90),
            ),
            (
              sequence: [(bpm: 80, pass: true), (bpm: 90, pass: true)],
              expected: null,
            ),
            (
              sequence: [
                (bpm: 80, pass: true),
                (bpm: 80, pass: false),
                (bpm: 80, pass: true),
                (bpm: 80, pass: true),
              ],
              expected: const Tempo(80),
            ),
            (
              sequence: [
                (bpm: 80, pass: true),
                (bpm: 80, pass: true),
                (bpm: 90, pass: true),
                (bpm: 90, pass: false),
                (bpm: 90, pass: true),
                (bpm: 90, pass: true),
              ],
              expected: const Tempo(90),
            ),
          ];

      for (final cell in cases) {
        var state = SpeedBuilderState.initial(_policy(maxAttempts: 20));
        for (var index = 0; index < cell.sequence.length; index++) {
          final entry = cell.sequence[index];
          state = engine.record(
            state,
            _attempt(index, entry.bpm, stepUpPass: entry.pass),
          );
        }
        expect(
          state.highestStableTempo,
          cell.expected,
          reason: '${cell.sequence}',
        );
      }
    });
  });
}

SpeedBuilderPolicy _policy({
  double startBpm = 80,
  double targetBpm = 120,
  double stepBpm = 10,
  int maxAttempts = 20,
  int requiredConsecutivePasses = 2,
  int reduceAfterConsecutiveFails = 2,
}) => SpeedBuilderPolicy(
  startBpm: Tempo(startBpm),
  targetBpm: Tempo(targetBpm),
  stepBpm: stepBpm,
  maxAttempts: maxAttempts,
  requiredConsecutivePasses: requiredConsecutivePasses,
  reduceAfterConsecutiveFails: reduceAfterConsecutiveFails,
);

PracticeAttemptResult _attempt(
  int index,
  double bpm, {
  bool? stepUpPass,
  MetricValue? completion,
  MetricValue? overall,
  MetricValue? rhythm,
  PracticeAttemptOutcome outcome = PracticeAttemptOutcome.failed,
}) {
  final passing = stepUpPass ?? false;
  return PracticeAttemptResult(
    index: index,
    tempo: Tempo(bpm),
    metrics: PracticeMetrics(
      completion: completion ?? MetricAvailable(passing ? 0.95 : 0.94),
      rhythm: rhythm ?? MetricAvailable(passing ? 0.80 : 0.79),
      direction: const MetricNotApplicable(),
      chord: const MetricNotApplicable(),
      overall: overall ?? MetricAvailable(passing ? 0.85 : 0.84),
      totalTargets: 8,
      resolvedTargets: 8,
      maxCombo: 8,
      scorePoints: 0,
      meanAbsoluteOffset: Duration.zero,
      timingBias: Duration.zero,
    ),
    verdicts: const [],
    outcome: outcome,
  );
}
