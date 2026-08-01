import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/practice_attempt_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_insight.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_result.dart'
    as presult;
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_coach.dart';

// `PracticeAttemptOutcome` lives on `practice_attempt_result.dart`, not on
// `practice_session_result.dart` (which is imported as `presult`).
PracticeAttemptOutcome _passed = PracticeAttemptOutcome.passed;

void main() {
  group('PracticeCoach — A4: every insight has evidence', () {
    test('zero strum observations → noSignal', () {
      final insight = _coach(
        result: _result(metrics: _metrics(const MetricAvailable(0.5))),
        context: _context(strumCount: 0, pairedEvents: 0),
      );
      expect(insight.code, PracticeInsightCode.noSignal);
    });

    test('completion 0.4 + overall 0.9 → lowCompletion (priority wins)', () {
      final insight = _coach(
        result: _result(
          metrics: _metrics(
            const MetricAvailable(0.4),
            overall: const MetricAvailable(0.9),
          ),
        ),
        context: _context(strumCount: 20, pairedEvents: 0),
      );
      expect(insight.code, PracticeInsightCode.lowCompletion);
    });

    test('paired events 80% late (≥ 8 paired, ≥ 70% share) → biasLate', () {
      final insight = _coach(
        result: _result(
          metrics: _metrics(
            const MetricAvailable(0.7),
            rhythm: const MetricAvailable(0.6),
            direction: const MetricAvailable(0.85),
            chord: const MetricAvailable(0.85),
            overall: const MetricAvailable(0.75),
          ),
        ),
        context: _context(
          strumCount: 30,
          pairedEvents: 20,
          timingBias: const Duration(milliseconds: 30),
          lateShare: 0.8,
        ),
      );
      expect(insight.code, PracticeInsightCode.biasLate);
    });

    test('paired events 80% early → biasEarly', () {
      final insight = _coach(
        result: _result(
          metrics: _metrics(
            const MetricAvailable(0.7),
            rhythm: const MetricAvailable(0.6),
            direction: const MetricAvailable(0.85),
            chord: const MetricAvailable(0.85),
            overall: const MetricAvailable(0.75),
          ),
        ),
        context: _context(
          strumCount: 30,
          pairedEvents: 20,
          timingBias: const Duration(milliseconds: -30),
          earlyShare: 0.8,
        ),
      );
      expect(insight.code, PracticeInsightCode.biasEarly);
    });

    test('direction 0.45 + rhythm 0.9 → directionError', () {
      final insight = _coach(
        result: _result(
          metrics: _metrics(
            const MetricAvailable(0.8),
            rhythm: const MetricAvailable(0.9),
            direction: const MetricAvailable(0.45),
            chord: const MetricAvailable(0.85),
            overall: const MetricAvailable(0.8),
          ),
        ),
        context: _context(strumCount: 30, pairedEvents: 0),
      );
      expect(insight.code, PracticeInsightCode.directionError);
    });

    test('every dimension > 0.9 → positiveReinforcement', () {
      final insight = _coach(
        result: _result(
          metrics: _metrics(
            const MetricAvailable(1.0),
            rhythm: const MetricAvailable(0.95),
            direction: const MetricAvailable(0.95),
            chord: const MetricAvailable(0.95),
            overall: const MetricAvailable(0.95),
          ),
        ),
        context: _context(strumCount: 20, pairedEvents: 0),
      );
      expect(insight.code, PracticeInsightCode.positiveReinforcement);
    });

    test('chord 0.4 + chord-pair G→D median-worst → chordPairProblem', () {
      // M4 — the chord-pair branch is only reachable when the chord
      // metric itself is also below threshold; this test pins the
      // positive chordPairProblem cell of the A4 matrix (chord < 0.6 AND
      // a chord-pair with ≥ 3 measurements that is the median-slowest by
      // ≥ 30%).
      final insight = _coach(
        result: _result(
          metrics: _metrics(
            const MetricAvailable(0.7),
            rhythm: const MetricAvailable(0.8),
            direction: const MetricAvailable(0.85),
            chord: const MetricAvailable(0.4),
            overall: const MetricAvailable(0.75),
          ),
        ),
        context: _context(
          strumCount: 30,
          pairedEvents: 0,
          slowestPair: const SlowestChordPair(
            pairKey: 'G->D',
            attempts: 4,
            relativeDelayToFastest: 0.45,
          ),
        ),
      );
      expect(insight.code, PracticeInsightCode.chordPairProblem);
    });

    test(
      'low completion AND direction error at the same time → completion wins',
      () {
        // M4 — the existing lowCompletion test (lines 25–36) leaves
        // direction as NotApplicable, so it never exercised the tie-break
        // between completion and direction. This test gives a real
        // direction metric below the threshold so both branches COULD
        // fire, and pins the §5.8 priority order: completion wins.
        final insight = _coach(
          result: _result(
            metrics: _metrics(
              const MetricAvailable(0.4),
              rhythm: const MetricAvailable(0.85),
              direction: const MetricAvailable(0.5),
              chord: const MetricAvailable(0.85),
              overall: const MetricAvailable(0.55),
            ),
          ),
          context: _context(strumCount: 30, pairedEvents: 0),
        );
        expect(insight.code, PracticeInsightCode.lowCompletion);
      },
    );
  });

  group('PracticeCoach — A5: minimum evidence threshold', () {
    test('3 paired events, 2 late → no bias insight (too little evidence)', () {
      final insight = _coach(
        result: _result(
          metrics: _metrics(
            const MetricAvailable(0.7),
            rhythm: const MetricAvailable(0.6),
            direction: const MetricAvailable(0.85),
            chord: const MetricAvailable(0.85),
            overall: const MetricAvailable(0.75),
          ),
        ),
        context: _context(
          strumCount: 6,
          pairedEvents: 3,
          timingBias: const Duration(milliseconds: 30),
          lateShare: 0.66,
        ),
      );
      expect(insight.code, isNot(PracticeInsightCode.biasLate));
    });

    test('20 paired events, 16 late → biasLate', () {
      final insight = _coach(
        result: _result(
          metrics: _metrics(
            const MetricAvailable(0.7),
            rhythm: const MetricAvailable(0.6),
            direction: const MetricAvailable(0.85),
            chord: const MetricAvailable(0.85),
            overall: const MetricAvailable(0.75),
          ),
        ),
        context: _context(
          strumCount: 30,
          pairedEvents: 20,
          timingBias: const Duration(milliseconds: 30),
          lateShare: 0.8,
        ),
      );
      expect(insight.code, PracticeInsightCode.biasLate);
    });

    test('one measured chord-pair → no pair insight (R15 threshold = 3)', () {
      final insight = _coach(
        result: _result(
          metrics: _metrics(
            const MetricAvailable(0.7),
            rhythm: const MetricAvailable(0.8),
            direction: const MetricAvailable(0.85),
            chord: const MetricAvailable(0.85),
            overall: const MetricAvailable(0.75),
          ),
        ),
        context: _context(
          strumCount: 30,
          pairedEvents: 0,
          slowestPair: const SlowestChordPair(
            pairKey: 'G->D',
            attempts: 1,
            relativeDelayToFastest: 0.5,
          ),
        ),
      );
      expect(insight.code, isNot(PracticeInsightCode.chordPairProblem));
    });
  });
}

presult.PracticeSessionResult _result({required PracticeMetrics metrics}) {
  final attempt = PracticeAttemptResult(
    index: 0,
    tempo: const Tempo(90),
    metrics: metrics,
    verdicts: const <PracticeVerdict>[],
    outcome: _passed,
  );
  return presult.PracticeSessionResult(
    id: 'session-1',
    activeDuration: const Duration(seconds: 30),
    pausedDuration: Duration.zero,
    attempts: <PracticeAttemptResult>[attempt],
    finishReason: presult.PracticeFinishReason.userFinished,
    highestStableTempo: const Tempo(90),
    coachingSummary: const <String>[],
  );
}

PracticeMetrics _metrics(
  MetricValue completion, {
  MetricValue rhythm = const MetricNotApplicable(),
  MetricValue direction = const MetricNotApplicable(),
  MetricValue chord = const MetricNotApplicable(),
  MetricValue overall = const MetricNotApplicable(),
}) {
  return PracticeMetrics(
    completion: completion,
    rhythm: rhythm,
    direction: direction,
    chord: chord,
    overall: overall,
    totalTargets: 16,
    resolvedTargets: 14,
    maxCombo: 8,
    scorePoints: 800,
    meanAbsoluteOffset: const Duration(milliseconds: 20),
    timingBias: Duration.zero,
  );
}

PracticeSessionContext _context({
  required int strumCount,
  required int pairedEvents,
  Duration? timingBias,
  double? lateShare,
  double? earlyShare,
  SlowestChordPair? slowestPair,
}) {
  return PracticeSessionContext(
    strumCount: strumCount,
    pairedEventCount: pairedEvents,
    timingBias: timingBias,
    lateShare: lateShare,
    earlyShare: earlyShare,
    slowestChordPair: slowestPair,
  );
}

PracticeInsight _coach({
  required presult.PracticeSessionResult result,
  required PracticeSessionContext context,
}) {
  return const PracticeCoach().coach(result: result, context: context);
}
