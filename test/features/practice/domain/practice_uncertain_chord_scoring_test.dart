// E14-R38 (ADR 0551) — an unconfident chord reading is ABSENCE OF EVIDENCE,
// never a wrong chord.
//
// The defect this replaces: `live_practice_observation_gateway.dart` stamped
// every chord observation with `confidence: 1.0`, so a reading the recognizer
// had explicitly rejected arrived at the scorer looking certain. If it
// happened to carry the wrong label, the player was marked wrong for the
// app's own abstention.
//
// The property that matters — and the one the plan names as R38's acceptance
// criterion — is at the bottom: the SCORE does not move when abstention
// does. Coverage moves instead.
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
  group('ChordEvidence', () {
    test('only a measured reading is evidence', () {
      expect(ChordEvidence.measured.isEvidence, isTrue);
      expect(ChordEvidence.uncertain.isEvidence, isFalse);
      expect(ChordEvidence.rejected.isEvidence, isFalse);
    });

    test('an unmeasured confidence is neither out of range nor invalid — '
        '"not measured" is a legal state, not a broken number', () {
      const observation = ChordObservation(
        at: Duration.zero,
        label: 'C',
        confidence: null,
        evidence: ChordEvidence.measured,
      );
      expect(observation.validate(), isEmpty);
    });

    test('an out-of-range confidence is still rejected', () {
      const observation = ChordObservation(
        at: Duration.zero,
        label: 'C',
        confidence: 1.4,
      );
      expect(observation.validate(), isNotEmpty);
    });

    test('evidence and reject reason take part in value equality', () {
      const measured = ChordObservation(
        at: Duration.zero,
        label: 'C',
        confidence: null,
      );
      const uncertain = ChordObservation(
        at: Duration.zero,
        label: 'C',
        confidence: null,
        evidence: ChordEvidence.uncertain,
      );
      expect(measured, isNot(equals(uncertain)));
      expect(measured.hashCode, isNot(equals(uncertain.hashCode)));
    });
  });

  group('an unconfident wrong label is never scored as a wrong chord', () {
    test('the WRONG chord under an uncertain verdict scores nothing — it is '
        'insufficient data, with its own reason code', () {
      final score = _scoreSingle(
        chord: 'G',
        observations: const [
          ChordObservation(
            at: _targetAt,
            label: 'C',
            confidence: null,
            evidence: ChordEvidence.uncertain,
          ),
          ChordObservation(
            at: Duration(milliseconds: 1300),
            label: 'C',
            confidence: null,
            evidence: ChordEvidence.uncertain,
          ),
        ],
      );

      expect(score.events.single.outcome, ChordOutcome.insufficientData);
      expect(
        score.events.single.insufficientReasonCode,
        PracticeMetricReasonCode.chordUncertain,
      );
      expect(score.events.single.scorePerMille, isNull);
      expect(score.chordPerMille, isNull);
    });

    test('FALSIFICATION: the same wrong label under a MEASURED verdict IS '
        'scored wrong — without this the cell above proves nothing', () {
      final score = _scoreSingle(
        chord: 'G',
        observations: const [
          ChordObservation(at: _targetAt, label: 'C', confidence: null),
          ChordObservation(
            at: Duration(milliseconds: 1300),
            label: 'C',
            confidence: null,
          ),
        ],
      );

      expect(score.events.single.outcome, ChordOutcome.wrong);
      expect(score.events.single.scorePerMille, 0);
    });

    test('a rejected reading is not a "no chord detected" either — the app '
        'refusing to read is not the player playing nothing', () {
      final score = _scoreSingle(
        chord: 'G',
        observations: const [
          ChordObservation(
            at: _targetAt,
            label: null,
            confidence: null,
            evidence: ChordEvidence.rejected,
            rejectReasonCode: 'signalTooQuiet',
          ),
        ],
      );

      expect(score.events.single.outcome, ChordOutcome.insufficientData);
      expect(
        score.events.single.insufficientReasonCode,
        PracticeMetricReasonCode.chordUncertain,
      );
      expect(score.events.single.scorePerMille, isNull);
    });

    test('an abstained frame in the middle of a held chord does not break '
        'that chord\'s stable run', () {
      final score = _scoreSingle(
        chord: 'G',
        observations: const [
          ChordObservation(at: _targetAt, label: 'G', confidence: null),
          ChordObservation(
            at: Duration(milliseconds: 1100),
            label: 'C',
            confidence: null,
            evidence: ChordEvidence.uncertain,
          ),
          ChordObservation(
            at: Duration(milliseconds: 1300),
            label: 'G',
            confidence: null,
          ),
          ChordObservation(
            at: Duration(milliseconds: 1400),
            label: 'G',
            confidence: null,
          ),
        ],
      );

      expect(score.events.single.outcome, ChordOutcome.correct);
      expect(score.events.single.observedChord, 'G');
    });
  });

  group('coverage is reported SEPARATELY from the score', () {
    test('no observations at all → coverage is not applicable, never 0.0', () {
      final score = _scoreSingle(chord: 'G', observations: const []);
      expect(score.recognitionCoverage, isA<MetricNotApplicable>());
    });

    test('coverage is the measured share of what the recognizer said', () {
      final score = _scoreSingle(
        chord: 'G',
        observations: const [
          ChordObservation(at: _targetAt, label: 'G', confidence: null),
          ChordObservation(
            at: Duration(milliseconds: 1300),
            label: 'G',
            confidence: null,
          ),
          ChordObservation(
            at: Duration(milliseconds: 1400),
            label: 'G',
            confidence: null,
            evidence: ChordEvidence.uncertain,
          ),
          ChordObservation(
            at: Duration(milliseconds: 1500),
            label: null,
            confidence: null,
            evidence: ChordEvidence.rejected,
          ),
        ],
      );
      final coverage = score.recognitionCoverage;
      expect(coverage, isA<MetricAvailable>());
      expect((coverage as MetricAvailable).value, closeTo(0.5, 1e-9));
    });

    test('THE ACCEPTANCE PROPERTY: the same playing scores the same however '
        'much the recognizer abstains — only coverage moves', () {
      const measuredRun = <ChordObservation>[
        ChordObservation(at: _targetAt, label: 'G', confidence: null),
        ChordObservation(
          at: Duration(milliseconds: 1300),
          label: 'G',
          confidence: null,
        ),
      ];

      final clean = _scoreSingle(chord: 'G', observations: measuredRun);
      expect(clean.events.single.outcome, ChordOutcome.correct);
      final cleanScore = clean.chordPerMille;

      // Same playing; the recognizer merely abstains more and more often.
      for (final abstentions in const [1, 3, 10]) {
        final noisy = _scoreSingle(
          chord: 'G',
          observations: <ChordObservation>[
            ...measuredRun,
            for (var index = 0; index < abstentions; index++)
              ChordObservation(
                at: Duration(milliseconds: 1310 + index),
                label: 'C',
                confidence: null,
                evidence: ChordEvidence.uncertain,
                rejectReasonCode: 'lowConfidence',
              ),
          ],
        );
        expect(
          noisy.chordPerMille,
          cleanScore,
          reason:
              'the score moved because the MODEL got unsure, not because '
              'the player changed anything ($abstentions abstentions)',
        );
        expect(noisy.events.single.outcome, ChordOutcome.correct);

        final coverage = noisy.recognitionCoverage as MetricAvailable;
        expect(
          coverage.value,
          lessThan(1.0),
          reason: 'abstention has to show up SOMEWHERE — this is where',
        );
      }
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

PracticeEventMatcher _matcher({required List<String?> chords}) =>
    PracticeEventMatcher(
      target: _target(chords),
      scoringProfile: ScoringProfile.legacyLearnParity,
      inputLatency: Duration.zero,
    );

CompiledPracticeTarget _target(List<String?> chords) => CompiledPracticeTarget(
  definitionId: 'chord-uncertainty-test',
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
        optional: false,
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
