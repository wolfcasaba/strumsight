import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/practice_attempt_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';

void main() {
  group('PracticeAttemptResult validation', () {
    test('accepts a valid attempt and aggregates nested values', () {
      expect(_attempt().validate(), isEmpty);

      final codes = _attempt(
        tempo: const Tempo(301),
        metrics: _metrics(overall: const MetricAvailable(double.infinity)),
        verdicts: [_verdict('target', coachingCode: 'unknown')],
      ).validate().map((failure) => failure.code);

      expect(
        codes,
        containsAll({
          'tempo.bpm.outOfRange',
          'metric.value.notFinite',
          'verdict.coachingCode.unknown',
        }),
      );
    });

    test('rejects a negative attempt index', () {
      expect(
        _attempt(index: -1).validate().map((failure) => failure.code),
        contains('attempt.index.negative'),
      );
    });

    test('rejects duplicate verdict target IDs', () {
      expect(
        _attempt(
          verdicts: [_verdict('duplicate'), _verdict('duplicate')],
        ).validate().map((failure) => failure.code),
        contains('attempt.verdicts.targetDuplicate'),
      );
    });

    test('compares the verdict list and all other fields structurally', () {
      final attempt = _attempt();
      final sameValue = _attempt();
      final different = _attempt(outcome: PracticeAttemptOutcome.failed);

      expect(attempt, sameValue);
      expect(attempt.hashCode, sameValue.hashCode);
      expect(attempt, isNot(different));
      expect({attempt}, contains(sameValue));
    });
  });

  group('PracticeSessionResult validation', () {
    test('accepts a valid session with canonical coaching codes', () {
      expect(
        _session(
          coachingSummary: const [
            PracticeCoachingCode.early,
            PracticeCoachingCode.noSignal,
          ],
        ).validate(),
        isEmpty,
      );
    });

    test('rejects an empty session ID and attempt list', () {
      final codes = _session(
        id: '',
        attempts: const [],
      ).validate().map((failure) => failure.code);

      expect(
        codes,
        containsAll({'session.id.empty', 'session.attempts.empty'}),
      );
    });

    test('requires attempt indexes to be strictly increasing', () {
      for (final attempts in [
        [_attempt(index: 2), _attempt(index: 1)],
        [_attempt(index: 1), _attempt(index: 1)],
      ]) {
        expect(
          _session(
            attempts: attempts,
          ).validate().map((failure) => failure.code),
          contains('session.attempts.unordered'),
        );
      }
    });

    test('continues nested validation after an attempt ordering failure', () {
      final codes = _session(
        attempts: [_attempt(index: 1), _attempt(index: 0), _attempt(index: -1)],
      ).validate().map((failure) => failure.code);

      expect(
        codes,
        containsAll({'session.attempts.unordered', 'attempt.index.negative'}),
      );
    });

    test('rejects negative active and paused durations', () {
      expect(
        _session(
          activeDuration: const Duration(microseconds: -1),
        ).validate().map((failure) => failure.code),
        contains('session.duration.negative'),
      );
      expect(
        _session(
          pausedDuration: const Duration(microseconds: -1),
        ).validate().map((failure) => failure.code),
        contains('session.duration.negative'),
      );
    });

    test('rejects an unknown coaching-summary code', () {
      expect(
        _session(
          coachingSummary: const ['practice.coach.unknown'],
        ).validate().map((failure) => failure.code),
        contains('session.coachingSummary.unknownCode'),
      );
    });

    test('aggregates attempt and highest-stable-tempo failures', () {
      final codes = _session(
        attempts: [_attempt(index: -1)],
        highestStableTempo: const Tempo(301),
      ).validate().map((failure) => failure.code);

      expect(
        codes,
        containsAll({'attempt.index.negative', 'tempo.bpm.outOfRange'}),
      );
    });

    test('compares attempt and coaching lists structurally', () {
      final session = _session(
        coachingSummary: const [PracticeCoachingCode.late],
      );
      final sameValue = _session(
        coachingSummary: const [PracticeCoachingCode.late],
      );
      final different = _session(
        finishReason: PracticeFinishReason.cancelled,
        coachingSummary: const [PracticeCoachingCode.late],
      );

      expect(session, sameValue);
      expect(session.hashCode, sameValue.hashCode);
      expect(session, isNot(different));
      expect({session}, contains(sameValue));
    });
  });

  group('PracticeSessionResult derived attempts', () {
    test(
      'finalAttempt selects the greatest index independent of list order',
      () {
        final expected = _attempt(index: 7);
        final result = _session(
          attempts: [_attempt(index: 3), expected, _attempt(index: 1)],
        );

        expect(result.finalAttempt, same(expected));
      },
    );

    test('bestAttempt selects the greatest available overall score', () {
      final expected = _attempt(
        index: 3,
        metrics: _metrics(overall: const MetricAvailable(0.9)),
      );
      final result = _session(
        attempts: [
          _attempt(
            index: 0,
            metrics: _metrics(overall: const MetricAvailable(0.8)),
          ),
          _attempt(
            index: 1,
            metrics: _metrics(overall: const MetricNotApplicable()),
          ),
          expected,
          _attempt(
            index: 4,
            metrics: _metrics(
              overall: const MetricInsufficientData('tooFewTargets'),
            ),
          ),
        ],
      );

      expect(result.bestAttempt, same(expected));
    });

    test('bestAttempt breaks score ties with the smaller index', () {
      final expected = _attempt(
        index: 1,
        metrics: _metrics(overall: const MetricAvailable(0.9)),
      );
      final result = _session(
        attempts: [
          _attempt(
            index: 4,
            metrics: _metrics(overall: const MetricAvailable(0.9)),
          ),
          expected,
        ],
      );

      expect(result.bestAttempt, same(expected));
    });

    test('derived getters return null when no attempt is comparable', () {
      final empty = _session(attempts: const []);
      final unavailable = _session(
        attempts: [
          _attempt(metrics: _metrics(overall: const MetricNotApplicable())),
          _attempt(
            index: 1,
            metrics: _metrics(
              overall: const MetricInsufficientData('tooFewTargets'),
            ),
          ),
        ],
      );

      expect(empty.finalAttempt, isNull);
      expect(empty.bestAttempt, isNull);
      expect(unavailable.bestAttempt, isNull);
    });
  });
}

PracticeAttemptResult _attempt({
  int index = 0,
  Tempo tempo = const Tempo(120),
  PracticeMetrics? metrics,
  List<PracticeVerdict>? verdicts,
  PracticeAttemptOutcome outcome = PracticeAttemptOutcome.passed,
}) => PracticeAttemptResult(
  index: index,
  tempo: tempo,
  metrics: metrics ?? _metrics(),
  verdicts: verdicts ?? [_verdict('target')],
  outcome: outcome,
);

PracticeSessionResult _session({
  String id = 'session',
  Duration activeDuration = const Duration(minutes: 2),
  Duration pausedDuration = const Duration(seconds: 10),
  List<PracticeAttemptResult>? attempts,
  PracticeFinishReason finishReason = PracticeFinishReason.completedAllTargets,
  Tempo? highestStableTempo = const Tempo(120),
  List<String> coachingSummary = const [],
}) => PracticeSessionResult(
  id: id,
  activeDuration: activeDuration,
  pausedDuration: pausedDuration,
  attempts: attempts ?? [_attempt()],
  finishReason: finishReason,
  highestStableTempo: highestStableTempo,
  coachingSummary: coachingSummary,
);

PracticeMetrics _metrics({MetricValue overall = const MetricAvailable(0.8)}) =>
    PracticeMetrics(
      completion: const MetricAvailable(1),
      rhythm: const MetricAvailable(0.8),
      direction: const MetricAvailable(0.8),
      chord: const MetricNotApplicable(),
      overall: overall,
      totalTargets: 1,
      resolvedTargets: 1,
      maxCombo: 1,
      scorePoints: 100,
      meanAbsoluteOffset: const Duration(milliseconds: 10),
      timingBias: Duration.zero,
    );

PracticeVerdict _verdict(String targetEventId, {String? coachingCode}) =>
    PracticeVerdict(
      targetEventId: targetEventId,
      matchedObservationSequence: 0,
      targetAt: const Duration(seconds: 1),
      observedAt: const Duration(seconds: 1),
      timingOffset: Duration.zero,
      timingGrade: TimingGrade.perfect,
      expectedDirection: StrumDirection.down,
      observedDirection: StrumDirection.down,
      directionOutcome: DirectionOutcome.correct,
      expectedChord: null,
      observedChord: null,
      chordOutcome: ChordOutcome.notApplicable,
      eventScore: 1,
      missReasonCode: null,
      coachingCode: coachingCode,
    );
