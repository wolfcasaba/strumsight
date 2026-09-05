import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/data/evaluation/recognition_evaluation_runner.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_metrics.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_split.dart';

/// One hand-derivable case exercising every metric family at once: two
/// plain onsets, four strums (one direction-wrong, one entirely missed),
/// four chords (one wrong-label, one missed, one abstained), 10 confidence
/// observations (one per ECE bin), and 5 latency samples. The full
/// derivation for every literal below is in
/// `docs/rounds/e14-r08-grouped-evaluation-harness.md` §10, verified with
/// `python3 -c`.
RecognitionCase _fixtureCase() => RecognitionCase(
  caseId: 'case-1',
  durationMs: 120000,
  expectedEvents: [
    RecognitionExpectedEvent(timeMs: 1000, kind: RecognitionEventKind.onset),
    RecognitionExpectedEvent(timeMs: 4000, kind: RecognitionEventKind.onset),
    RecognitionExpectedEvent(
      timeMs: 2000,
      kind: RecognitionEventKind.strum,
      direction: StrumDirection.down,
    ),
    RecognitionExpectedEvent(
      timeMs: 3000,
      kind: RecognitionEventKind.strum,
      direction: StrumDirection.up,
    ),
    RecognitionExpectedEvent(
      timeMs: 5000,
      kind: RecognitionEventKind.strum,
      direction: StrumDirection.down,
    ),
    RecognitionExpectedEvent(
      timeMs: 7000,
      kind: RecognitionEventKind.strum,
      direction: StrumDirection.up,
    ),
    RecognitionExpectedEvent(
      timeMs: 1000,
      kind: RecognitionEventKind.chord,
      chordLabel: 'C',
    ),
    RecognitionExpectedEvent(
      timeMs: 2000,
      kind: RecognitionEventKind.chord,
      chordLabel: 'G',
    ),
    RecognitionExpectedEvent(
      timeMs: 3000,
      kind: RecognitionEventKind.chord,
      chordLabel: 'noChord',
    ),
    RecognitionExpectedEvent(
      timeMs: 4000,
      kind: RecognitionEventKind.chord,
      chordLabel: 'Am',
    ),
  ],
  detectedEvents: [
    // gap 20ms vs the 1000ms onset — matches at 25/50/100ms.
    RecognitionDetectedEvent(
      timeMs: 1020,
      kind: RecognitionEventKind.onset,
      accepted: true,
      confidence: 0.9,
    ),
    // no expected event within 1000ms of anywhere — always a false positive.
    RecognitionDetectedEvent(
      timeMs: 6000,
      kind: RecognitionEventKind.onset,
      accepted: true,
      confidence: 0.5,
    ),
    // gap 45ms vs the 2000ms down-strum — matches at 50/100ms, not 25ms.
    RecognitionDetectedEvent(
      timeMs: 2045,
      kind: RecognitionEventKind.strum,
      accepted: true,
      confidence: 0.8,
      direction: StrumDirection.down,
    ),
    // gap 90ms vs the 3000ms up-strum — matches only at 100ms.
    RecognitionDetectedEvent(
      timeMs: 3090,
      kind: RecognitionEventKind.strum,
      accepted: true,
      confidence: 0.6,
      direction: StrumDirection.up,
    ),
    // gap 10ms vs the 5000ms strum, but the WRONG direction (down expected).
    RecognitionDetectedEvent(
      timeMs: 5010,
      kind: RecognitionEventKind.strum,
      accepted: true,
      confidence: 0.7,
      direction: StrumDirection.up,
    ),
    // gap 30ms vs the 7000ms up-strum — matches at 50/100ms, correct direction.
    RecognitionDetectedEvent(
      timeMs: 7030,
      kind: RecognitionEventKind.strum,
      accepted: true,
      confidence: 0.85,
      direction: StrumDirection.up,
    ),
    // gap 50ms vs the 1000ms "C" chord, correct label.
    RecognitionDetectedEvent(
      timeMs: 1050,
      kind: RecognitionEventKind.chord,
      accepted: true,
      confidence: 0.9,
      chordLabel: 'C',
    ),
    // gap 100ms vs the 2000ms "G" chord, WRONG label.
    RecognitionDetectedEvent(
      timeMs: 2100,
      kind: RecognitionEventKind.chord,
      accepted: true,
      confidence: 0.5,
      chordLabel: 'unknown',
    ),
    // gap 80ms vs the 3000ms "noChord" chord, correct label.
    RecognitionDetectedEvent(
      timeMs: 3080,
      kind: RecognitionEventKind.chord,
      accepted: true,
      confidence: 0.8,
      chordLabel: 'noChord',
    ),
    // no expected chord within 250ms — always a false positive.
    RecognitionDetectedEvent(
      timeMs: 6500,
      kind: RecognitionEventKind.chord,
      accepted: true,
      confidence: 0.4,
      chordLabel: 'unknown',
    ),
    // ABSTAINED: never enters any match, but does count toward coverage's
    // denominator (ADR 0509 §9 risk: the fixture must cover abstention).
    RecognitionDetectedEvent(
      timeMs: 4010,
      kind: RecognitionEventKind.chord,
      accepted: false,
      confidence: 0.3,
      chordLabel: 'Am',
    ),
  ],
  confidenceObservations: [
    RecognitionConfidenceObservation(rawScore: 0.05, correct: false),
    RecognitionConfidenceObservation(rawScore: 0.15, correct: true),
    RecognitionConfidenceObservation(rawScore: 0.25, correct: false),
    RecognitionConfidenceObservation(rawScore: 0.35, correct: true),
    RecognitionConfidenceObservation(rawScore: 0.45, correct: true),
    RecognitionConfidenceObservation(rawScore: 0.55, correct: false),
    RecognitionConfidenceObservation(rawScore: 0.65, correct: true),
    RecognitionConfidenceObservation(rawScore: 0.75, correct: true),
    RecognitionConfidenceObservation(rawScore: 0.85, correct: true),
    RecognitionConfidenceObservation(rawScore: 0.95, correct: true),
  ],
  detectionLatenciesMs: [20, 40, 60, 80, 100],
);

void main() {
  final metrics = computeRecognitionMetrics([_fixtureCase()]);

  group('RecognitionMetrics — hand-verified literal values (acceptance 4/5, '
      'ADR 0509 D3)', () {
    test('onset P/R/F1 @ 25ms: 2 of 6 matched (TP=2,FP=4,FN=4)', () {
      final m = metrics.onsetTolerance25Ms;
      expect(m.truePositives, 2);
      expect(m.falsePositives, 4);
      expect(m.falseNegatives, 4);
      expect(m.precision, 1 / 3);
      expect(m.recall, 1 / 3);
      expect(m.f1, 1 / 3);
      expect(m.definition.toleranceMs, 25);
    });

    test('onset P/R/F1 @ 50ms: 4 of 6 matched (TP=4,FP=2,FN=2)', () {
      final m = metrics.onsetTolerance50Ms;
      expect(m.truePositives, 4);
      expect(m.falsePositives, 2);
      expect(m.falseNegatives, 2);
      expect(m.precision, 2 / 3);
      expect(m.recall, 2 / 3);
      expect(m.f1, 2 / 3);
    });

    test('onset P/R/F1 @ 100ms: 5 of 6 matched (TP=5,FP=1,FN=1)', () {
      final m = metrics.onsetTolerance100Ms;
      expect(m.truePositives, 5);
      expect(m.falsePositives, 1);
      expect(m.falseNegatives, 1);
      expect(m.precision, 5 / 6);
      expect(m.recall, 5 / 6);
      expect(m.f1, 5 / 6);
    });

    test('any-strum F1: 3 of 4 strums matched regardless of direction '
        '(TP=3,FP=1,FN=1)', () {
      final m = metrics.anyStrumF1;
      expect(m.truePositives, 3);
      expect(m.falsePositives, 1);
      expect(m.falseNegatives, 1);
      expect(m.precision, 0.75);
      expect(m.recall, 0.75);
      expect(m.f1, 0.75);
    });

    test('direction F1: macro((down: P1 R0.5 F1=2/3), (up: P1/3 R0.5 '
        'F1=0.4)) = 8/15', () {
      final down = metrics.directionF1.perLabel['down']!;
      expect(down.truePositives, 1);
      expect(down.falsePositives, 0);
      expect(down.falseNegatives, 1);
      expect(down.f1, closeTo(2 / 3, 1e-12));

      final up = metrics.directionF1.perLabel['up']!;
      expect(up.truePositives, 1);
      expect(up.falsePositives, 2);
      expect(up.falseNegatives, 1);
      expect(up.f1, closeTo(0.4, 1e-12));

      expect(metrics.directionF1.value, closeTo(8 / 15, 1e-12));
    });

    test('chord weighted accuracy: 2 correct of 4 expected (C, noChord '
        'correct; G wrong label; Am missed)', () {
      final m = metrics.chordWeightedAccuracy;
      expect(m.numerator, 2);
      expect(m.denominator, 4);
      expect(m.value, 0.5);
    });

    test('chord macro-F1: C=1, G=0(no accepted prediction), noChord=1, '
        'Am=0(no accepted prediction) -> 0.5', () {
      expect(metrics.chordMacroF1.perLabel['C']!.f1, 1.0);
      expect(metrics.chordMacroF1.perLabel['G']!.f1, isNull);
      expect(metrics.chordMacroF1.perLabel['G']!.falseNegatives, 1);
      expect(metrics.chordMacroF1.perLabel['noChord']!.f1, 1.0);
      expect(metrics.chordMacroF1.perLabel['Am']!.f1, isNull);
      expect(metrics.chordMacroF1.perLabel['Am']!.falseNegatives, 1);
      expect(metrics.chordMacroF1.value, 0.5);
    });

    test('no-chord F1 is the noChord entry of the chord macro breakdown: '
        'a clean 1.0, not null', () {
      expect(metrics.chordNoChordF1.truePositives, 1);
      expect(metrics.chordNoChordF1.f1, 1.0);
    });

    test('unknown false-accept: 2 of 4 accepted chord detections are '
        '"unknown"', () {
      final m = metrics.chordUnknownFalseAccept;
      expect(m.numerator, 2);
      expect(m.denominator, 4);
      expect(m.value, 0.5);
    });

    test('accepted accuracy: 5 of 10 accepted detections are correct '
        '(onset1, strum-down, strum-up#2, chord-C, chord-noChord)', () {
      final m = metrics.acceptedAccuracy;
      expect(m.numerator, 5);
      expect(m.denominator, 10);
      expect(m.value, 0.5);
    });

    test('coverage: 10 of 11 detections were surfaced (1 abstained)', () {
      final m = metrics.coverage;
      expect(m.numerator, 10);
      expect(m.denominator, 11);
      expect(m.value, closeTo(10 / 11, 1e-12));
    });

    test('false visible events/min: 5 wrong accepted detections over '
        '2 minutes of audio', () {
      final m = metrics.falseVisibleEventsPerMinute;
      expect(m.eventCount, 5);
      expect(m.durationMinutes, 2.0);
      expect(m.value, 2.5);
    });

    test('latency p50/p95: nearest-rank over [20,40,60,80,100]', () {
      expect(metrics.latencyP50Ms.value, 60.0);
      expect(metrics.latencyP95Ms.value, 100.0);
      expect(metrics.latencyP50Ms.sampleCount, 5);
    });

    test('ECE: weighted mean absolute gap across 10 one-observation bins '
        '(python3 -c verified: 0.37000000000000005)', () {
      expect(metrics.calibration.expectedCalibrationError, closeTo(0.37, 1e-9));
      expect(metrics.calibration.observationCount, 10);
      expect(metrics.calibration.bins, hasLength(10));
      expect(metrics.calibration.bins[0].observationCount, 1);
      expect(metrics.calibration.bins[0].lowerBound, 0.0);
      expect(metrics.calibration.bins[0].upperBound, 0.1);
    });

    test('Brier score: mean squared error over the 10 confidence '
        'observations (python3 -c verified: 0.20249999999999999)', () {
      expect(metrics.brierScore.value, closeTo(0.2025, 1e-9));
      expect(metrics.brierScore.sampleCount, 10);
    });
  });

  group('Partitioned false-visible-event rates (acceptance 3-6, ADR 0521 '
      'D1-D4)', () {
    RecognitionCase directionOnlyCase({required bool abstainThirdEvent}) =>
        RecognitionCase(
          caseId: 'direction-only',
          durationMs: 120000,
          detectedEvents: [
            RecognitionDetectedEvent(
              timeMs: 1000,
              kind: RecognitionEventKind.strum,
              accepted: true,
              confidence: 0.9,
              direction: StrumDirection.down,
            ),
            RecognitionDetectedEvent(
              timeMs: 2000,
              kind: RecognitionEventKind.strum,
              accepted: true,
              confidence: 0.9,
              direction: StrumDirection.up,
            ),
            RecognitionDetectedEvent(
              timeMs: 3000,
              kind: RecognitionEventKind.strum,
              accepted: !abstainThirdEvent,
              confidence: 0.9,
              direction: StrumDirection.down,
            ),
          ],
        );

    test('3 false-visible direction events over 120s of audio -> 1.5/min '
        '(acceptance 3)', () {
      final m = computeRecognitionMetrics([
        directionOnlyCase(abstainThirdEvent: false),
      ]);
      expect(m.falseVisibleDirectionEventsPerMinute.eventCount, 3);
      expect(m.falseVisibleDirectionEventsPerMinute.durationMinutes, 2.0);
      expect(m.falseVisibleDirectionEventsPerMinute.value, 1.5);
    });

    test('abstaining one of the three -> 1.0/min: an abstained (accepted == '
        'false) detection is never a false positive (acceptance 4)', () {
      final m = computeRecognitionMetrics([
        directionOnlyCase(abstainThirdEvent: true),
      ]);
      expect(m.falseVisibleDirectionEventsPerMinute.eventCount, 2);
      expect(m.falseVisibleDirectionEventsPerMinute.value, 1.0);
    });

    RecognitionCase mixedKindCase({required bool includeFalseOnset}) =>
        RecognitionCase(
          caseId: 'mixed-kind',
          durationMs: 60000,
          detectedEvents: [
            RecognitionDetectedEvent(
              timeMs: 1000,
              kind: RecognitionEventKind.strum,
              accepted: true,
              confidence: 0.9,
              direction: StrumDirection.down,
            ),
            RecognitionDetectedEvent(
              timeMs: 2000,
              kind: RecognitionEventKind.strum,
              accepted: true,
              confidence: 0.9,
              direction: StrumDirection.up,
            ),
            RecognitionDetectedEvent(
              timeMs: 3000,
              kind: RecognitionEventKind.chord,
              accepted: true,
              confidence: 0.9,
              chordLabel: 'C',
            ),
            RecognitionDetectedEvent(
              timeMs: 4000,
              kind: RecognitionEventKind.chord,
              accepted: true,
              confidence: 0.9,
              chordLabel: 'G',
            ),
            if (includeFalseOnset)
              RecognitionDetectedEvent(
                timeMs: 5000,
                kind: RecognitionEventKind.onset,
                accepted: true,
                confidence: 0.9,
              ),
          ],
        );

    test('closed partition: direction + chord counts equal the agnostic '
        'count when there is no false-visible onset (acceptance 5, ADR '
        '0521 D4a)', () {
      final m = computeRecognitionMetrics([
        mixedKindCase(includeFalseOnset: false),
      ]);
      expect(
        m.falseVisibleDirectionEventsPerMinute.eventCount +
            m.falseVisibleChordEventsPerMinute.eventCount,
        m.falseVisibleEventsPerMinute.eventCount,
      );
      expect(m.falseVisibleEventsPerMinute.eventCount, 4);
    });

    test(
      'anti-alias: adding a false-visible onset makes the partitioned sum '
      'strictly less than the agnostic count, proving the scoped rate is '
      'not a relabelled agnostic rate (acceptance 6, ADR 0521 D4b, L549)',
      () {
        final m = computeRecognitionMetrics([
          mixedKindCase(includeFalseOnset: true),
        ]);
        final partitionedSum =
            m.falseVisibleDirectionEventsPerMinute.eventCount +
            m.falseVisibleChordEventsPerMinute.eventCount;
        expect(
          partitionedSum,
          lessThan(m.falseVisibleEventsPerMinute.eventCount),
        );
        expect(
          m.falseVisibleDirectionEventsPerMinute.value,
          isNot(m.falseVisibleEventsPerMinute.value),
        );
      },
    );

    test('both scoped rates are lower-is-better, read from their own '
        'definition, not a shared constant (ADR 0521 D5)', () {
      final m = computeRecognitionMetrics([
        mixedKindCase(includeFalseOnset: false),
      ]);
      expect(
        m.falseVisibleDirectionEventsPerMinute.definition.higherIsBetter,
        isFalse,
      );
      expect(
        m.falseVisibleChordEventsPerMinute.definition.higherIsBetter,
        isFalse,
      );
    });
  });

  group('Onset-tolerance boundary is inclusive at 50ms (acceptance 3, ADR '
      '0509 D5)', () {
    RecognitionCase gapCase(int detectedTimeMs) => RecognitionCase(
      caseId: 'boundary',
      expectedEvents: [
        RecognitionExpectedEvent(timeMs: 0, kind: RecognitionEventKind.onset),
      ],
      detectedEvents: [
        RecognitionDetectedEvent(
          timeMs: detectedTimeMs,
          kind: RecognitionEventKind.onset,
          accepted: true,
          confidence: 1,
        ),
      ],
    );

    test('49ms (below the tolerance) is a hit', () {
      final m = computeRecognitionMetrics([gapCase(49)]);
      expect(m.onsetTolerance50Ms.truePositives, 1);
    });

    test('exactly 50ms (on the tolerance) is a hit — the boundary belongs '
        'to the accepting side', () {
      final m = computeRecognitionMetrics([gapCase(50)]);
      expect(m.onsetTolerance50Ms.truePositives, 1);
    });

    test('51ms (above the tolerance) is a miss', () {
      final m = computeRecognitionMetrics([gapCase(51)]);
      expect(m.onsetTolerance50Ms.truePositives, 0);
      expect(m.onsetTolerance50Ms.falseNegatives, 1);
      expect(m.onsetTolerance50Ms.falsePositives, 1);
    });
  });

  group('Matching is maximum-cardinality, not greedy (acceptance 8, ADR '
      '0509 D5, docs/LESSONS.md L269)', () {
    test('expected [50,90] vs detected [0,55] @ 50ms tolerance: 2 TP, not '
        '1 — a greedy nearest-pair matcher would take (50,55) first and '
        'strand both 0 and 90 outside tolerance of each other', () {
      final l269Case = RecognitionCase(
        caseId: 'l269',
        expectedEvents: [
          RecognitionExpectedEvent(
            timeMs: 50,
            kind: RecognitionEventKind.onset,
          ),
          RecognitionExpectedEvent(
            timeMs: 90,
            kind: RecognitionEventKind.onset,
          ),
        ],
        detectedEvents: [
          RecognitionDetectedEvent(
            timeMs: 0,
            kind: RecognitionEventKind.onset,
            accepted: true,
            confidence: 1,
          ),
          RecognitionDetectedEvent(
            timeMs: 55,
            kind: RecognitionEventKind.onset,
            accepted: true,
            confidence: 1,
          ),
        ],
      );

      final m = computeRecognitionMetrics([l269Case]);
      expect(m.onsetTolerance50Ms.truePositives, 2);
      expect(m.onsetTolerance50Ms.falsePositives, 0);
      expect(m.onsetTolerance50Ms.falseNegatives, 0);
    });
  });

  group('Every metric carries its direction (acceptance 9, ADR 0509 D4)', () {
    test('the F1 family, accepted accuracy and coverage are '
        'higher-is-better', () {
      expect(metrics.onsetTolerance25Ms.definition.higherIsBetter, isTrue);
      expect(metrics.onsetTolerance50Ms.definition.higherIsBetter, isTrue);
      expect(metrics.onsetTolerance100Ms.definition.higherIsBetter, isTrue);
      expect(metrics.anyStrumF1.definition.higherIsBetter, isTrue);
      expect(metrics.directionF1.definition.higherIsBetter, isTrue);
      expect(metrics.chordWeightedAccuracy.definition.higherIsBetter, isTrue);
      expect(metrics.chordMacroF1.definition.higherIsBetter, isTrue);
      expect(metrics.chordNoChordF1.definition.higherIsBetter, isTrue);
      expect(metrics.acceptedAccuracy.definition.higherIsBetter, isTrue);
      expect(metrics.coverage.definition.higherIsBetter, isTrue);
    });

    test('ECE, Brier, false-visible-events/min and latency p50/p95 are '
        'lower-is-better — all four error metrics measured explicitly', () {
      expect(metrics.calibration.definition.higherIsBetter, isFalse);
      expect(metrics.brierScore.definition.higherIsBetter, isFalse);
      expect(
        metrics.falseVisibleEventsPerMinute.definition.higherIsBetter,
        isFalse,
      );
      expect(metrics.latencyP50Ms.definition.higherIsBetter, isFalse);
      expect(metrics.latencyP95Ms.definition.higherIsBetter, isFalse);
    });
  });

  group('Determinism (acceptance 6, ADR 0509 D6)', () {
    test('the same manifest produces byte-identical JSON on repeat runs', () {
      final cases = [_fixtureCase()];
      final first = RecognitionEvaluationReport(
        manifestSchemaVersion: '1.0',
        caseCount: cases.length,
        overall: computeRecognitionMetrics(cases),
      );
      final second = RecognitionEvaluationReport(
        manifestSchemaVersion: '1.0',
        caseCount: cases.length,
        overall: computeRecognitionMetrics(cases),
      );
      expect(first.toDeterministicJson(), second.toDeterministicJson());
    });
  });

  group('directionF1/chordMacroF1 definition text matches the computed '
      'behaviour (review MAJOR-1 fix)', () {
    test('zero time-matched strum pairs still gives down FN=1 and macro '
        'F1=0.0 — the definition text says so, not "does not enter this '
        'metric"', () {
      final noMatchCase = RecognitionCase(
        caseId: 'no-match-strum',
        expectedEvents: [
          RecognitionExpectedEvent(
            timeMs: 1000,
            kind: RecognitionEventKind.strum,
            direction: StrumDirection.down,
          ),
        ],
      );
      final m = computeRecognitionMetrics([noMatchCase]);
      final down = m.directionF1.perLabel['down']!;
      expect(down.truePositives, 0);
      expect(down.falsePositives, 0);
      expect(down.falseNegatives, 1);
      expect(m.directionF1.value, 0.0);
      expect(
        m.directionF1.definition.description,
        isNot(contains('does not enter this metric')),
      );
      expect(
        m.directionF1.definition.description,
        contains('never time-matched at all'),
      );
      expect(
        m.directionF1.definition.denominatorDescription,
        contains('not restricted to the time-matched set'),
      );
    });

    test('zero time-matched chord pairs still gives label FN=1 and macro '
        'F1=0.0 — same rule on the chord side', () {
      final noMatchCase = RecognitionCase(
        caseId: 'no-match-chord',
        expectedEvents: [
          RecognitionExpectedEvent(
            timeMs: 1000,
            kind: RecognitionEventKind.chord,
            chordLabel: 'C',
          ),
        ],
      );
      final m = computeRecognitionMetrics([noMatchCase]);
      final c = m.chordMacroF1.perLabel['C']!;
      expect(c.truePositives, 0);
      expect(c.falsePositives, 0);
      expect(c.falseNegatives, 1);
      expect(m.chordMacroF1.value, 0.0);
      expect(
        m.chordMacroF1.definition.description,
        isNot(contains('does not enter this metric')),
      );
      expect(
        m.chordMacroF1.definition.description,
        contains('never time-matched at all'),
      );
    });
  });

  group('RecognitionEvaluationRunner on the committed CI fixture (review '
      'MAJOR-2 fix)', () {
    test('running the committed ci_manifest.json through '
        'runFromJsonString twice produces byte-identical JSON (acceptance '
        '6 on the real run path, not a hand-built report)', () async {
      final source = await File(
        'evaluation/recognition/fixtures/ci_manifest.json',
      ).readAsString();
      const runner = RecognitionEvaluationRunner();
      final first = runner.runFromJsonString(source);
      final second = runner.runFromJsonString(source);
      expect(first.toDeterministicJson(), second.toDeterministicJson());
      expect(first.caseCount, 3);
    });

    test('every split strategy folds the fixture-parsed cases into an '
        'eval union that is exactly the fixture case set (acceptance 1 '
        'on the fixture)', () async {
      final source = await File(
        'evaluation/recognition/fixtures/ci_manifest.json',
      ).readAsString();
      const runner = RecognitionEvaluationRunner();
      final manifest = runner.parseManifestJsonString(source);
      expect(manifest.cases.map((c) => c.caseId).toSet(), {
        'case-1',
        'case-2',
        'case-3',
      });

      for (final strategy in SplitStrategy.values) {
        final folds = const RecognitionSplitBuilder().buildFolds(
          manifest.cases,
          strategy,
        );
        final evalIdsAcrossFolds = <String>[
          for (final fold in folds) ...fold.evalCaseIds,
        ];
        expect(
          evalIdsAcrossFolds.toSet(),
          manifest.cases.map((c) => c.caseId).toSet(),
          reason:
              '${strategy.name}: fold union must equal the fixture '
              'case set',
        );
        expect(
          evalIdsAcrossFolds.length,
          manifest.cases.length,
          reason: '${strategy.name}: each case held out exactly once',
        );
      }

      // player-a (case-1, case-3) and room-2 (case-2, case-3) are the
      // non-trivial folds the fixture's third case was added to exercise
      // (review MAJOR-2, acceptance 1 "on the fixture" must not be trivial).
      final playerFolds = const RecognitionSplitBuilder().buildFolds(
        manifest.cases,
        SplitStrategy.leaveOnePlayerOut,
      );
      expect(
        playerFolds
            .firstWhere((f) => f.heldOutGroupValue == 'player-a')
            .evalCaseIds,
        ['case-1', 'case-3'],
      );
      final roomFolds = const RecognitionSplitBuilder().buildFolds(
        manifest.cases,
        SplitStrategy.roomHoldout,
      );
      expect(
        roomFolds
            .firstWhere((f) => f.heldOutGroupValue == 'room-2')
            .evalCaseIds,
        ['case-2', 'case-3'],
      );
    });

    test('an unknown top-level field is a typed unknownField rejection', () {
      const runner = RecognitionEvaluationRunner();
      expect(
        () => runner.parseManifestJsonString(
          '{"schemaVersion":"1.0","cases":[],"extra":true}',
        ),
        throwsA(
          isA<RecognitionManifestParseException>().having(
            (e) => e.kind,
            'kind',
            RecognitionManifestParseErrorKind.unknownField,
          ),
        ),
      );
    });

    test('an unsupported schemaVersion is a typed invalidSchemaVersion '
        'rejection', () {
      const runner = RecognitionEvaluationRunner();
      expect(
        () => runner.parseManifestJsonString(
          '{"schemaVersion":"2.0","cases":[]}',
        ),
        throwsA(
          isA<RecognitionManifestParseException>()
              .having(
                (e) => e.kind,
                'kind',
                RecognitionManifestParseErrorKind.invalidSchemaVersion,
              )
              .having((e) => e.path, 'path', 'manifest.schemaVersion'),
        ),
      );
    });

    test('a strum expected event without a direction is a typed '
        'missingField rejection', () {
      const runner = RecognitionEvaluationRunner();
      const source =
          '{"schemaVersion":"1.0","cases":[{"caseId":"c1","durationMs":0,'
          '"expectedEvents":[{"timeMs":0,"kind":"strum"}]}]}';
      expect(
        () => runner.parseManifestJsonString(source),
        throwsA(
          isA<RecognitionManifestParseException>()
              .having(
                (e) => e.kind,
                'kind',
                RecognitionManifestParseErrorKind.missingField,
              )
              .having(
                (e) => e.path,
                'path',
                'manifest.cases[0].expectedEvents[0].direction',
              ),
        ),
      );
    });
  });

  group('RecognitionExpectedEvent/RecognitionDetectedEvent enforce their '
      'own kind invariant (review MINOR-1 fix)', () {
    test(
      'a hand-built strum event without a direction throws '
      'ArgumentError, not a raw TypeError from computeRecognitionMetrics',
      () {
        expect(
          () => RecognitionExpectedEvent(
            timeMs: 0,
            kind: RecognitionEventKind.strum,
          ),
          throwsArgumentError,
        );
        expect(
          () => RecognitionDetectedEvent(
            timeMs: 0,
            kind: RecognitionEventKind.strum,
            accepted: true,
            confidence: 1,
          ),
          throwsArgumentError,
        );
      },
    );

    test('a hand-built chord event without a chordLabel throws '
        'ArgumentError', () {
      expect(
        () => RecognitionExpectedEvent(
          timeMs: 0,
          kind: RecognitionEventKind.chord,
        ),
        throwsArgumentError,
      );
      expect(
        () => RecognitionDetectedEvent(
          timeMs: 0,
          kind: RecognitionEventKind.chord,
          accepted: true,
          confidence: 1,
        ),
        throwsArgumentError,
      );
    });

    test('an onset event never requires direction or chordLabel', () {
      expect(
        () => RecognitionExpectedEvent(
          timeMs: 0,
          kind: RecognitionEventKind.onset,
        ),
        returnsNormally,
      );
    });
  });
}
