import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/practice_attempt_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/speed_builder_policy.dart';
import 'package:strumsight/features/practice/domain/model/speed_builder_state.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/speed_builder_engine.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  test('A10 — randomized Speed Builder invariants', () {
    const engine = SpeedBuilderEngine();
    for (var trial = 0; trial < 100; trial++) {
      final random = math.Random(seed + trial * 1009);
      final start = 30.0 + random.nextInt(220);
      final step = 1.0 + random.nextInt(20);
      final target = math.min(300.0, start + random.nextInt(51));
      final policy = SpeedBuilderPolicy(
        startBpm: Tempo(start),
        targetBpm: Tempo(target),
        stepBpm: step,
        requiredConsecutivePasses: 1 + random.nextInt(4),
        maxAttempts: 1 + random.nextInt(100),
        reduceAfterConsecutiveFails: 1 + random.nextInt(4),
      );
      var state = SpeedBuilderState.initial(policy);
      var maximumAttemptTempo = start;

      for (var index = 0; index < 140; index++) {
        final previous = state;
        final arbitraryBpm = 30.0 + random.nextInt(271);
        final attempt = _attempt(
          index: random.nextInt(200) - 50,
          bpm: arbitraryBpm,
          pass: random.nextBool(),
          insufficient: random.nextInt(8) == 0,
        );
        final previousAttemptCount = state.attempts.length;

        expect(() => state = engine.record(previous, attempt), returnsNormally);
        expect(state, engine.record(previous, attempt));
        if (state.attempts.length > previousAttemptCount) {
          maximumAttemptTempo = math.max(
            maximumAttemptTempo,
            attempt.tempo.bpm,
          );
        }
        final bpm = state.currentTempo.bpm;
        expect(bpm, inInclusiveRange(start, target));
        expect(
          (bpm - previous.currentTempo.bpm).abs(),
          lessThanOrEqualTo(step),
        );
        expect(state.attempts.length, lessThanOrEqualTo(policy.maxAttempts));
        final stable = state.highestStableTempo;
        if (stable != null) {
          expect(stable.bpm, lessThanOrEqualTo(maximumAttemptTempo));
        }
      }
    }
  });
}

PracticeAttemptResult _attempt({
  required int index,
  required double bpm,
  required bool pass,
  required bool insufficient,
}) => PracticeAttemptResult(
  index: index,
  tempo: Tempo(bpm),
  metrics: PracticeMetrics(
    completion: insufficient
        ? const MetricInsufficientData('random')
        : MetricAvailable(pass ? 0.95 : 0.20),
    rhythm: MetricAvailable(pass ? 0.80 : 0.20),
    direction: const MetricNotApplicable(),
    chord: const MetricNotApplicable(),
    overall: MetricAvailable(pass ? 0.85 : 0.20),
    totalTargets: 1,
    resolvedTargets: 1,
    maxCombo: 1,
    scorePoints: 0,
    meanAbsoluteOffset: Duration.zero,
    timingBias: Duration.zero,
  ),
  verdicts: const [],
  outcome: pass ? PracticeAttemptOutcome.passed : PracticeAttemptOutcome.failed,
);
