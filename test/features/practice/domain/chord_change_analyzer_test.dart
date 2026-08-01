import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/chord_pair_stats.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/chord_change_analyzer.dart';

const _stability = Duration(milliseconds: 180);

void main() {
  group('ChordChangeAnalyzer outcome matrix', () {
    test('recognises the first stable target chord with signed delay', () {
      final result = _analyze(
        targetAt: const Duration(seconds: 1),
        verdicts: [_verdict(at: const Duration(seconds: 1))],
        observations: [
          _chord(at: const Duration(milliseconds: 1100), label: 'D'),
          _chord(at: const Duration(milliseconds: 1200), label: 'D'),
          _chord(at: const Duration(milliseconds: 1280), label: 'D'),
        ],
      );

      final change = result.changes.single;
      expect(change.outcome, ChordChangeOutcome.correct);
      expect(change.recognizedChangeDelay, const Duration(milliseconds: 100));
      expect(change.stableDuration, _stability);
    });

    test('reports a stable wrong chord separately', () {
      final result = _analyze(
        targetAt: const Duration(seconds: 1),
        verdicts: [_verdict(at: const Duration(seconds: 1))],
        observations: [
          _chord(at: const Duration(milliseconds: 1100), label: 'C'),
          _chord(at: const Duration(milliseconds: 1280), label: 'C'),
        ],
      );

      expect(result.changes.single.outcome, ChordChangeOutcome.wrongChord);
      expect(result.changes.single.recognizedChangeDelay, isNull);
    });

    test('keeps explicit null labels as no detection', () {
      final result = _analyze(
        targetAt: const Duration(seconds: 1),
        verdicts: [_verdict(at: const Duration(seconds: 1))],
        observations: [
          _chord(at: const Duration(milliseconds: 1100), label: null),
          _chord(at: const Duration(milliseconds: 1200), label: null),
        ],
      );

      expect(result.changes.single.outcome, ChordChangeOutcome.noDetection);
    });

    test('reports a target chord that never reaches stability', () {
      final result = _analyze(
        targetAt: const Duration(seconds: 1),
        verdicts: [_verdict(at: const Duration(seconds: 1))],
        observations: [
          _chord(at: const Duration(milliseconds: 1100), label: 'D'),
          _chord(at: const Duration(milliseconds: 1279999), label: 'D'),
        ],
      );

      expect(result.changes.single.outcome, ChordChangeOutcome.unstable);
    });

    test('separates an empty window and a window without a strum', () {
      final empty = _analyze(targetAt: const Duration(seconds: 1));
      expect(
        empty.changes.single.outcome,
        ChordChangeOutcome.insufficientSignal,
      );

      final noStrum = _analyze(
        targetAt: const Duration(seconds: 1),
        observations: [
          _chord(at: const Duration(milliseconds: 1100), label: 'D'),
          _chord(at: const Duration(milliseconds: 1280), label: 'D'),
        ],
      );
      expect(
        noStrum.changes.single.outcome,
        ChordChangeOutcome.insufficientSignal,
      );
    });
  });

  group('ChordChangeAnalyzer delay and aggregation', () {
    test('preserves early, on-time, late, and missing delay', () {
      final result = _analyzeTransitions([
        _transition(
          at: const Duration(seconds: 1),
          delay: -50,
          destination: 'D',
        ),
        _transition(at: const Duration(seconds: 3), delay: 0, destination: 'C'),
        _transition(
          at: const Duration(seconds: 5),
          delay: 250,
          destination: 'D',
        ),
        _transition(
          at: const Duration(seconds: 7),
          delay: null,
          destination: 'C',
        ),
      ]);

      expect(result.changes.map((change) => change.recognizedChangeDelay), [
        const Duration(milliseconds: -50),
        Duration.zero,
        const Duration(milliseconds: 250),
        isNull,
      ]);
    });

    test('uses a median only after three measured changes', () {
      final two = _analyzeTransitions([
        _transition(
          at: const Duration(seconds: 1),
          delay: 100,
          destination: 'D',
        ),
        _transition(
          at: const Duration(seconds: 3),
          delay: null,
          destination: 'C',
        ),
        _transition(
          at: const Duration(seconds: 5),
          delay: 300,
          destination: 'D',
        ),
      ]);
      final twoStats = two.pairStats.firstWhere(
        (stats) => stats.pair == const ChordPair(from: 'C', to: 'D'),
      );
      expect(twoStats.medianRecognizedChangeDelay, isNull);
      expect(twoStats.hasSufficientDelayData, isFalse);

      final three = _analyzeTransitions([
        _transition(
          at: const Duration(seconds: 1),
          delay: 100,
          destination: 'D',
        ),
        _transition(
          at: const Duration(seconds: 3),
          delay: null,
          destination: 'C',
        ),
        _transition(
          at: const Duration(seconds: 5),
          delay: 300,
          destination: 'D',
        ),
        _transition(
          at: const Duration(seconds: 7),
          delay: null,
          destination: 'C',
        ),
        _transition(
          at: const Duration(seconds: 9),
          delay: 200,
          destination: 'D',
        ),
      ]);
      final threeStats = three.pairStats.firstWhere(
        (stats) => stats.pair == const ChordPair(from: 'C', to: 'D'),
      );
      expect(
        threeStats.medianRecognizedChangeDelay,
        const Duration(milliseconds: 200),
      );

      final four = _analyzeTransitions([
        _transition(
          at: const Duration(seconds: 1),
          delay: 100,
          destination: 'D',
        ),
        _transition(
          at: const Duration(seconds: 3),
          delay: null,
          destination: 'C',
        ),
        _transition(
          at: const Duration(seconds: 5),
          delay: 200,
          destination: 'D',
        ),
        _transition(
          at: const Duration(seconds: 7),
          delay: null,
          destination: 'C',
        ),
        _transition(
          at: const Duration(seconds: 9),
          delay: 300,
          destination: 'D',
        ),
        _transition(
          at: const Duration(seconds: 11),
          delay: null,
          destination: 'C',
        ),
        _transition(
          at: const Duration(seconds: 13),
          delay: 400,
          destination: 'D',
        ),
      ]);
      final fourStats = four.pairStats.firstWhere(
        (stats) => stats.pair == const ChordPair(from: 'C', to: 'D'),
      );
      expect(
        fourStats.medianRecognizedChangeDelay,
        const Duration(milliseconds: 250),
      );
    });

    test('treats direction as part of a chord pair', () {
      final result = _analyzeSequence(const ['G', 'D', 'G']);

      expect(result.pairStats.map((stats) => stats.pair), [
        const ChordPair(from: 'D', to: 'G'),
        const ChordPair(from: 'G', to: 'D'),
      ]);
    });

    test('slowest pair tie-break is canonical and input-order independent', () {
      const chords = ['G', 'D', 'C', 'D', 'C', 'D', 'C', 'D'];
      final forward = _analyzeSequence(chords);
      final shuffled = _analyzeSequence(chords, reverseObservations: true);

      expect(forward.slowestPair?.pair, const ChordPair(from: 'C', to: 'D'));
      expect(shuffled.slowestPair?.pair, const ChordPair(from: 'C', to: 'D'));
    });
  });
}

ChordChangeAnalysis _analyze({
  required Duration targetAt,
  List<PracticeVerdict> verdicts = const [],
  List<ChordObservation> observations = const [],
}) => _analyzeTransitions([
  _transition(
    at: targetAt,
    delay: null,
    autoVerdict: verdicts.isNotEmpty,
    verdicts: verdicts,
    observations: observations,
  ),
]);

ChordChangeAnalysis _analyzeTransitions(
  List<
    ({
      Duration at,
      int? delay,
      String destination,
      List<PracticeVerdict> verdicts,
      List<ChordObservation> observations,
    })
  >
  transitions,
) {
  final segments = <ExpectedChordSegment>[];
  var previousStart = Duration.zero;
  var previousChord = 'C';
  for (var index = 0; index < transitions.length; index++) {
    final transition = transitions[index];
    segments.add(
      ExpectedChordSegment(
        chord: previousChord,
        start: previousStart,
        end: transition.at,
      ),
    );
    previousStart = transition.at;
    previousChord = transition.destination;
  }
  segments.add(
    ExpectedChordSegment(
      chord: previousChord,
      start: previousStart,
      end: const Duration(seconds: 30),
    ),
  );
  final allVerdicts = <PracticeVerdict>[];
  final allObservations = <ChordObservation>[];
  for (final transition in transitions) {
    allVerdicts.addAll(transition.verdicts);
    allObservations.addAll(transition.observations);
  }
  return ChordChangeAnalyzer().analyze(
    target: _target(segments),
    verdicts: allVerdicts,
    observations: allObservations,
  );
}

({
  Duration at,
  int? delay,
  String destination,
  List<PracticeVerdict> verdicts,
  List<ChordObservation> observations,
})
_transition({
  required Duration at,
  required int? delay,
  String destination = 'D',
  bool autoVerdict = true,
  List<PracticeVerdict> verdicts = const [],
  List<ChordObservation> observations = const [],
}) {
  final start = delay == null
      ? at + const Duration(milliseconds: 100)
      : at + Duration(milliseconds: delay);
  final actualVerdicts = verdicts.isEmpty && autoVerdict
      ? [_verdict(at: at)]
      : verdicts;
  final actualObservations = observations.isEmpty && delay != null
      ? [
          _chord(at: start, label: destination),
          _chord(at: start + _stability, label: destination),
        ]
      : observations;
  return (
    at: at,
    delay: delay,
    destination: destination,
    verdicts: actualVerdicts,
    observations: actualObservations,
  );
}

ChordChangeAnalysis _analyzeSequence(
  List<String> chords, {
  bool reverseObservations = false,
}) {
  final transitions =
      <
        ({
          Duration at,
          int? delay,
          String destination,
          List<PracticeVerdict> verdicts,
          List<ChordObservation> observations,
        })
      >[];
  for (var index = 1; index < chords.length; index++) {
    final at = Duration(seconds: index * 2);
    transitions.add(
      _transition(
        at: at,
        delay: 100,
        destination: chords[index],
        verdicts: [_verdict(at: at)],
        observations: [
          _chord(
            at: at + const Duration(milliseconds: 100),
            label: chords[index],
          ),
          _chord(
            at: at + const Duration(milliseconds: 280),
            label: chords[index],
          ),
        ],
      ),
    );
  }
  final segments = <ExpectedChordSegment>[
    for (var index = 0; index < chords.length; index++)
      ExpectedChordSegment(
        chord: chords[index],
        start: Duration(seconds: index * 2),
        end: index + 1 < chords.length
            ? Duration(seconds: (index + 1) * 2)
            : const Duration(seconds: 30),
      ),
  ];
  final observations = [
    for (final transition in transitions) ...transition.observations,
  ];
  final orderedObservations = reverseObservations
      ? observations.reversed.toList()
      : observations;
  final result = ChordChangeAnalyzer().analyze(
    target: _target(segments),
    verdicts: [for (final transition in transitions) ...transition.verdicts],
    observations: orderedObservations,
  );
  return result;
}

PracticeVerdict _verdict({required Duration at}) => PracticeVerdict(
  targetEventId: 'strum-${at.inMicroseconds}',
  matchedObservationSequence: at.inMicroseconds,
  targetAt: at,
  observedAt: at,
  timingOffset: Duration.zero,
  timingGrade: TimingGrade.perfect,
  expectedDirection: StrumDirection.down,
  observedDirection: StrumDirection.down,
  directionOutcome: DirectionOutcome.correct,
  expectedChord: 'D',
  observedChord: 'D',
  chordOutcome: ChordOutcome.correct,
  eventScore: 1,
  missReasonCode: null,
  coachingCode: null,
);

ChordObservation _chord({required Duration at, required String? label}) =>
    ChordObservation(at: at, label: label, confidence: 1);

CompiledPracticeTarget _target(List<ExpectedChordSegment> segments) =>
    CompiledPracticeTarget(
      definitionId: 'chord-change-test',
      definitionSnapshotVersion: 1,
      tempo: const Tempo(60),
      meter: const Meter(beatsPerBar: 4),
      countInBars: 0,
      countInDuration: Duration.zero,
      events: const [],
      musicalDuration: const Duration(seconds: 30),
      ringOutDuration: Duration.zero,
      totalDuration: const Duration(seconds: 30),
      barBoundaries: const [],
      loopCount: 1,
      loopRange: null,
      expectedChordSegments: segments,
      scoringApplicable: true,
    );
