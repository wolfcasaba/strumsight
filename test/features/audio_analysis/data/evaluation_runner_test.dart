import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/data/evaluation/calibration_fitter.dart';
import 'package:strumsight/features/audio_analysis/data/evaluation/evaluation_runner.dart';
import 'package:strumsight/features/audio_analysis/domain/evaluation/ground_truth.dart';

EvalEvent _onset(String id, int timeMs) =>
    EvalEvent(id: id, timeMs: timeMs, type: EvalEventType.onset);

List<EvalEvent> _onsetsAt(String prefix, List<int> times) => [
  for (var i = 0; i < times.length; i++) _onset('$prefix$i', times[i]),
];

void main() {
  final runner = const EvaluationRunner();

  group('EvaluationRunner.matchEvents — known-answer cells', () {
    // python3 -c "p=3/3; r=3/3; print(2*p*r/(p+r))" -> 1.0
    test('(a) perfect detection -> F1 == 1.0', () {
      final expected = _onsetsAt('e', [0, 100, 200]);
      final detected = _onsetsAt('d', [0, 100, 200]);
      final result = runner.matchEvents(expected, detected, 50);
      expect(result.precisionRecallF1.precision, 1.0);
      expect(result.precisionRecallF1.recall, 1.0);
      expect(result.precisionRecallF1.f1, 1.0);
    });

    // python3 -c "r=0/3; print(r)" -> 0.0; precision is undefined (0/0).
    test(
      '(b) every expected event is missed -> recall == 0.0, '
      'precision is undefined (null), not 0',
      () {
        final expected = _onsetsAt('e', [0, 100, 200]);
        final result = runner.matchEvents(expected, const <EvalEvent>[], 50);
        expect(result.precisionRecallF1.precision, isNull);
        expect(result.precisionRecallF1.recall, 0.0);
        expect(result.precisionRecallF1.f1, isNull);
      },
    );

    // python3 -c "
    // p=2/2; r=2/4; print(p, r, 2*p*r/(p+r))" -> 1.0 0.5 0.6666666666666666
    test(
      '(c) half of the expected events are missing, nothing extra '
      '-> precision 1.0, recall 0.5, F1 0.666...',
      () {
        final expected = _onsetsAt('e', [0, 100, 200, 300]);
        final detected = _onsetsAt('d', [0, 100]);
        final result = runner.matchEvents(expected, detected, 50);
        expect(result.precisionRecallF1.precision, 1.0);
        expect(result.precisionRecallF1.recall, 0.5);
        expect(result.precisionRecallF1.f1, closeTo(0.6666666666666666, 1e-12));
      },
    );

    // python3 -c "
    // p=5/10; r=5/6; print(p, r, 2*p*r/(p+r))" -> 0.5 0.8333333333333334 0.625
    test(
      '(d) 10 detected, 5 correct, 6 expected '
      '-> precision 0.5, recall 0.8333..., F1 0.625',
      () {
        final expected = _onsetsAt('e', [0, 100, 200, 300, 400, 500]);
        final detected = [
          ..._onsetsAt('d', [0, 100, 200, 300, 400]),
          ..._onsetsAt('x', [10000, 10100, 10200, 10300, 10400]),
        ];
        final result = runner.matchEvents(expected, detected, 50);
        expect(result.precisionRecallF1.truePositives, 5);
        expect(result.precisionRecallF1.falsePositives, 5);
        expect(result.precisionRecallF1.falseNegatives, 1);
        expect(result.precisionRecallF1.precision, 0.5);
        expect(
          result.precisionRecallF1.recall,
          closeTo(0.8333333333333334, 1e-12),
        );
        expect(result.precisionRecallF1.f1, 0.625);
      },
    );
  });

  group('CalibrationFitter — 30-per-bin / 300-total minimums (inclusive)', () {
    List<ConfidenceObservation> observationsWithNarrowestBin(int narrowCount) {
      final observations = <ConfidenceObservation>[];
      for (var bin = 0; bin < 9; bin++) {
        final rawScore = bin / 10 + 0.05;
        for (var i = 0; i < 40; i++) {
          observations.add(
            ConfidenceObservation(rawScore: rawScore, correct: i.isEven),
          );
        }
      }
      for (var i = 0; i < narrowCount; i++) {
        observations.add(
          ConfidenceObservation(rawScore: 0.95, correct: true),
        );
      }
      return observations;
    }

    test('29 observations in the narrowest bin -> stays identity.v1', () {
      final fit = const CalibrationFitter().fit(
        observationsWithNarrowestBin(29),
      );
      expect(fit.insufficientData, isTrue);
      expect(fit.table.version, 'identity.v1');
    });

    test('exactly 30 observations in the narrowest bin -> fits (inclusive)', () {
      final fit = const CalibrationFitter().fit(
        observationsWithNarrowestBin(30),
      );
      expect(fit.insufficientData, isFalse);
      expect(fit.table.version, isNot('identity.v1'));
    });

    test('31 observations in the narrowest bin -> fits', () {
      final fit = const CalibrationFitter().fit(
        observationsWithNarrowestBin(31),
      );
      expect(fit.insufficientData, isFalse);
    });

    List<ConfidenceObservation> singleBinObservations(int total) => [
      for (var i = 0; i < total; i++)
        ConfidenceObservation(rawScore: 0.5, correct: i.isEven),
    ];

    test('299 total observations -> stays identity.v1', () {
      final fit = const CalibrationFitter().fit(singleBinObservations(299));
      expect(fit.insufficientData, isTrue);
      expect(fit.table.version, 'identity.v1');
    });

    test('exactly 300 total observations -> fits (inclusive)', () {
      final fit = const CalibrationFitter().fit(singleBinObservations(300));
      expect(fit.insufficientData, isFalse);
      expect(fit.table.version, isNot('identity.v1'));
    });

    test('301 total observations -> fits', () {
      final fit = const CalibrationFitter().fit(singleBinObservations(301));
      expect(fit.insufficientData, isFalse);
    });
  });

  test(
    'CalibrationFitter.fit computes a hand-verified Expected Calibration '
    'Error',
    () {
      // python3 -c "
      // n=100; w=50/n
      // ece = w*abs(0.2-0.1) + w*abs(0.8-0.9)
      // print(ece)" -> 0.1
      final observations = <ConfidenceObservation>[
        for (var i = 0; i < 50; i++)
          ConfidenceObservation(rawScore: 0.2, correct: i < 5),
        for (var i = 0; i < 50; i++)
          ConfidenceObservation(rawScore: 0.8, correct: i < 45),
      ];
      final fit = const CalibrationFitter().fit(observations);
      expect(fit.expectedCalibrationError, closeTo(0.1, 1e-9));
    },
  );

  group('EvaluationRunner.run', () {
    test('reports the nine metrics and a slice breakdown for the CI fixture', () {
      final ground = GroundTruthCase(
        id: 'case-1',
        tempoBand: TempoBand.medium,
        signalQualityTier: SignalQualityTier.clean,
        mode: EvalMode.chord,
        expected: AnnotationSet(
          events: [
            EvalEvent(
              id: 'e1',
              timeMs: 0,
              type: EvalEventType.strum,
              direction: StrumDirectionLabel.down,
            ),
            EvalEvent(
              id: 'e2',
              timeMs: 500,
              type: EvalEventType.strum,
              direction: StrumDirectionLabel.up,
            ),
          ],
          chordSegments: [
            ChordSegment(label: 'C', startMs: 0, endMs: 1000),
          ],
          tempoBpm: 120,
          beatsMs: const [0, 500],
          pitchPoints: const [],
        ),
        detected: AnnotationSet(
          events: [
            EvalEvent(
              id: 'd1',
              timeMs: 0,
              type: EvalEventType.strum,
              direction: StrumDirectionLabel.down,
            ),
            EvalEvent(
              id: 'd2',
              timeMs: 505,
              type: EvalEventType.strum,
              direction: StrumDirectionLabel.up,
            ),
          ],
          chordSegments: [
            ChordSegment(label: 'C', startMs: 0, endMs: 1000),
          ],
          tempoBpm: 121,
          beatsMs: const [0, 500],
          pitchPoints: const [],
        ),
      );
      final manifest = GroundTruthManifest(
        schemaVersion: '1.0',
        cases: [ground],
      );

      final report = runner.run(manifest);

      expect(report.overall.onset.precision, 1.0);
      expect(report.overall.onset.recall, 1.0);
      expect(report.overall.onset.f1, 1.0);
      expect(report.overall.timestampMaeMs, closeTo(2.5, 1e-9));
      expect(report.overall.chordSegmentAccuracy, 1.0);
      expect(report.overall.chordFrameAccuracy, 1.0);
      expect(report.overall.strumDirectionAccuracy, 1.0);
      expect(report.overall.beatAlignmentAccuracy, 1.0);
      expect(report.overall.bpmErrorPercent, closeTo(0.8333333333333334, 1e-9));
      expect(report.overall.confidenceCalibration.insufficientData, isTrue);
      expect(
        report.slices.map((s) => s.key),
        containsAll(<String>[
          'tempoBand:medium',
          'signalQualityTier:clean',
          'mode:chord',
        ]),
      );
    });
  });
}
