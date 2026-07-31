import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_chord_scorer.dart';
import 'package:strumsight/features/practice/domain/service/practice_event_matcher.dart';

const _targetAt = Duration(seconds: 1);
const _stableDuration = Duration(milliseconds: 180);

void main() {
  group('PracticeChordScorer A3 inclusive asymmetric window', () {
    const cells = <({int deltaMicroseconds, bool inside})>[
      (deltaMicroseconds: -120001, inside: false),
      (deltaMicroseconds: -120000, inside: true),
      (deltaMicroseconds: -119999, inside: true),
      (deltaMicroseconds: 419999, inside: true),
      (deltaMicroseconds: 420000, inside: true),
      (deltaMicroseconds: 420001, inside: false),
    ];

    for (final cell in cells) {
      test('${cell.deltaMicroseconds} us is '
          '${cell.inside ? 'inside' : 'outside'} the chord window', () {
        final score = _scoreSingle(
          chord: 'G',
          observations: [
            _chord(
              at: _targetAt + Duration(microseconds: cell.deltaMicroseconds),
              label: 'G',
            ),
          ],
        );

        expect(score.events.single.outcome, ChordOutcome.insufficientData);
        expect(score.events.single.observedChord, cell.inside ? 'G' : isNull);
      });
    }
  });

  group('PracticeChordScorer A3 outcome branches', () {
    test('stable expected label is correct', () {
      final score = _scoreSingle(
        chord: 'G',
        observations: const [
          ChordObservation(at: _targetAt, label: 'G', confidence: 1),
          ChordObservation(
            at: Duration(milliseconds: 1180),
            label: 'G',
            confidence: 1,
          ),
        ],
      );

      expect(score.events.single.outcome, ChordOutcome.correct);
      expect(score.events.single.observedChord, 'G');
      expect(score.events.single.scorePerMille, 1000);
      expect(score.chordPerMille, 1000);
      expect(score.chord, const MetricAvailable(1));
    });

    test('stable different label is wrong', () {
      final score = _scoreSingle(
        chord: 'G',
        observations: const [
          ChordObservation(at: _targetAt, label: 'C', confidence: 1),
          ChordObservation(
            at: Duration(milliseconds: 1180),
            label: 'C',
            confidence: 1,
          ),
        ],
      );

      expect(score.events.single.outcome, ChordOutcome.wrong);
      expect(score.events.single.observedChord, 'C');
      expect(score.events.single.scorePerMille, 0);
      expect(score.chord, const MetricAvailable(0));
    });

    test('only null labels are noDetection, not wrong or insufficient', () {
      final score = _scoreSingle(
        chord: 'G',
        observations: const [
          ChordObservation(at: _targetAt, label: null, confidence: 1),
        ],
      );

      expect(score.events.single.outcome, ChordOutcome.noDetection);
      expect(score.events.single.observedChord, isNull);
      expect(score.events.single.scorePerMille, 0);
      expect(score.chordPerMille, 0);
      expect(score.chord, const MetricAvailable(0));
    });

    test('an empty target window is insufficient data', () {
      final score = _scoreSingle(chord: 'G', observations: const []);

      expect(score.events.single.outcome, ChordOutcome.insufficientData);
      expect(score.events.single.observedChord, isNull);
      expect(score.events.single.scorePerMille, isNull);
      expect(score.chordPerMille, isNull);
      expect(
        score.chord,
        const MetricInsufficientData(PracticeMetricReasonCode.noSignal),
      );
    });

    test('a label below the stability threshold is insufficient data', () {
      final score = _scoreSingle(
        chord: 'G',
        observations: const [
          ChordObservation(at: _targetAt, label: 'G', confidence: 1),
          ChordObservation(
            at: Duration(microseconds: 1179999),
            label: 'G',
            confidence: 1,
          ),
        ],
      );

      expect(score.events.single.outcome, ChordOutcome.insufficientData);
      expect(score.events.single.observedChord, 'G');
      expect(score.events.single.scorePerMille, isNull);
      expect(
        score.chord,
        const MetricInsufficientData(PracticeMetricReasonCode.chordUnstable),
      );
    });

    test('a target without an expected chord is not applicable', () {
      final score = _scoreSingle(
        chord: null,
        observations: const [
          ChordObservation(at: _targetAt, label: 'G', confidence: 1),
          ChordObservation(
            at: Duration(milliseconds: 1180),
            label: 'G',
            confidence: 1,
          ),
        ],
      );

      expect(score.events.single.outcome, ChordOutcome.notApplicable);
      expect(score.events.single.scorePerMille, isNull);
      expect(score.chordPerMille, isNull);
      expect(score.chord, const MetricNotApplicable());
    });
  });

  group('PracticeChordScorer stability and aggregation', () {
    test('the longest stable segment wins even when it is the wrong chord', () {
      final score = _scoreSingle(
        chord: 'G',
        observations: const [
          ChordObservation(
            at: Duration(milliseconds: 900),
            label: 'G',
            confidence: 1,
          ),
          ChordObservation(
            at: Duration(milliseconds: 1100),
            label: 'G',
            confidence: 1,
          ),
          ChordObservation(
            at: Duration(milliseconds: 1101),
            label: 'C',
            confidence: 1,
          ),
          ChordObservation(
            at: Duration(milliseconds: 1350),
            label: 'C',
            confidence: 1,
          ),
        ],
      );

      expect(score.events.single.observedChord, 'C');
      expect(score.events.single.outcome, ChordOutcome.wrong);
    });

    test('nonconsecutive runs of the same label are not merged', () {
      final score = _scoreSingle(
        chord: 'G',
        observations: const [
          ChordObservation(
            at: Duration(milliseconds: 900),
            label: 'G',
            confidence: 1,
          ),
          ChordObservation(
            at: Duration(milliseconds: 1050),
            label: 'C',
            confidence: 1,
          ),
          ChordObservation(
            at: Duration(milliseconds: 1250),
            label: 'G',
            confidence: 1,
          ),
          ChordObservation(
            at: Duration(milliseconds: 1420),
            label: 'G',
            confidence: 1,
          ),
        ],
      );

      expect(score.events.single.observedChord, 'C');
      expect(score.events.single.outcome, ChordOutcome.wrong);
    });

    test('unordered observations produce the same deterministic result', () {
      const ordered = <ChordObservation>[
        ChordObservation(at: _targetAt, label: 'G', confidence: 1),
        ChordObservation(
          at: Duration(milliseconds: 1180),
          label: 'G',
          confidence: 1,
        ),
      ];

      final forward = _scoreSingle(chord: 'G', observations: ordered);
      final reverse = _scoreSingle(
        chord: 'G',
        observations: ordered.reversed.toList(),
      );

      expect(reverse.events.single.outcome, forward.events.single.outcome);
      expect(
        reverse.events.single.observedChord,
        forward.events.single.observedChord,
      );
    });

    test('available outcomes use one integer truncating division', () {
      final matcher = _matcher(chords: const ['G', 'G', 'G']);
      final score = const PracticeChordScorer().score(
        matches: matcher.results,
        observations: const [
          ChordObservation(
            at: Duration(milliseconds: 1000),
            label: 'G',
            confidence: 1,
          ),
          ChordObservation(
            at: Duration(milliseconds: 1180),
            label: 'G',
            confidence: 1,
          ),
          ChordObservation(
            at: Duration(milliseconds: 2000),
            label: 'C',
            confidence: 1,
          ),
          ChordObservation(
            at: Duration(milliseconds: 2180),
            label: 'C',
            confidence: 1,
          ),
          ChordObservation(
            at: Duration(milliseconds: 3000),
            label: null,
            confidence: 1,
          ),
        ],
      );

      expect(score.events.map((event) => event.outcome), [
        ChordOutcome.correct,
        ChordOutcome.wrong,
        ChordOutcome.noDetection,
      ]);
      expect(score.chordPerMille, 333);
      expect(score.chord, const MetricAvailable(0.333));
    });

    test('samples outside every window report insufficient samples', () {
      final score = _scoreSingle(
        chord: 'G',
        observations: const [
          ChordObservation(
            at: Duration(milliseconds: 1421),
            label: 'G',
            confidence: 1,
          ),
        ],
      );

      expect(
        score.chord,
        const MetricInsufficientData(
          PracticeMetricReasonCode.insufficientSamples,
        ),
      );
    });

    test('unmatched optional chord target does not dilute the metric', () {
      final matcher = _matcher(
        chords: const ['G', 'G'],
        optionalIndices: const {1},
      )..finalize();
      final score = const PracticeChordScorer().score(
        matches: matcher.results,
        observations: const [
          ChordObservation(at: _targetAt, label: 'G', confidence: 1),
          ChordObservation(
            at: Duration(milliseconds: 1180),
            label: 'G',
            confidence: 1,
          ),
        ],
      );

      expect(score.events[1].outcome, ChordOutcome.notApplicable);
      expect(score.chordPerMille, 1000);
    });

    test('the event-score view rejects mutation', () {
      final score = _scoreSingle(chord: null, observations: const []);

      expect(
        () => score.events.add(score.events.single),
        throwsUnsupportedError,
      );
    });
  });
}

PracticeChordScore _scoreSingle({
  required String? chord,
  required List<ChordObservation> observations,
}) => const PracticeChordScorer().score(
  matches: _matcher(chords: [chord]).results,
  observations: observations,
  chordStableDuration: _stableDuration,
);

ChordObservation _chord({required Duration at, required String? label}) =>
    ChordObservation(at: at, label: label, confidence: 1);

PracticeEventMatcher _matcher({
  required List<String?> chords,
  Set<int> optionalIndices = const {},
}) => PracticeEventMatcher(
  target: _target(chords, optionalIndices),
  scoringProfile: ScoringProfile.legacyLearnParity,
  inputLatency: Duration.zero,
);

CompiledPracticeTarget _target(
  List<String?> chords,
  Set<int> optionalIndices,
) => CompiledPracticeTarget(
  definitionId: 'chord-test',
  definitionSnapshotVersion: 1,
  tempo: const Tempo(120),
  meter: const Meter(beatsPerBar: 4),
  countInBars: 0,
  countInDuration: Duration.zero,
  events: [
    for (var index = 0; index < chords.length; index++)
      CompiledTargetEvent(
        sourceEventId: 'event-$index',
        loopIndex: 0,
        position: BeatPosition.fromTicks(index),
        time: Duration(seconds: index + 1),
        barIndex: 0,
        chord: chords[index],
        direction: StrumDirection.down,
        accent: false,
        optional: optionalIndices.contains(index),
      ),
  ],
  musicalDuration: Duration(seconds: chords.length + 1),
  ringOutDuration: Duration.zero,
  totalDuration: Duration(seconds: chords.length + 1),
  barBoundaries: const [],
  loopCount: 1,
  loopRange: null,
  expectedChordSegments: const [],
  scoringApplicable: chords.isNotEmpty,
);
