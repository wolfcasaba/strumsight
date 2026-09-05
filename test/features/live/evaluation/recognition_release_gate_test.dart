import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_metrics.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_release_gate.dart';

void main() {
  const gate = RecognitionReleaseGate();

  group('fail-closed: missing/null metric', () {
    test('a null-valued metric is FAIL and names the metric', () {
      final metrics = _metrics(
        acceptedAccuracy: _ratio(value: null, numerator: 0, denominator: 0),
      );
      final thresholds = gate.parseThresholds(
        _thresholdsJson([_entry('overall.acceptedAccuracy.value', 0.9)]),
      );

      final verdict = gate.evaluate(metrics, thresholds);

      expect(verdict.passed, isFalse);
      final finding = verdict.findings.single;
      expect(finding.value, isNull);
      expect(finding.passed, isFalse);
      expect(finding.reason, contains('overall.acceptedAccuracy.value'));
      expect(finding.reason, contains('missing'));
    });

    test('skipping the missing-metric branch would turn this cell green '
        '(§7.1 falsification is exercised by temporarily short-circuiting '
        '_evaluateEntry to `passed: true` — see round brief §10)', () {
      // This test documents the fixed-closed contract asserted above; the
      // actual falsification run (brief §7.1) is a manual, reverted local
      // edit recorded in the round handoff, not a permanent code path.
      final metrics = _metrics(
        coverage: _ratio(value: null, numerator: 0, denominator: 0),
      );
      final thresholds = gate.parseThresholds(
        _thresholdsJson([_entry('overall.coverage.value', 0.7)]),
      );
      final verdict = gate.evaluate(metrics, thresholds);
      expect(verdict.passed, isFalse);
    });
  });

  group('boundary belongs to the accepting side', () {
    test('higherIsBetter == true: below/on/above 0.9', () {
      final thresholds = gate.parseThresholds(
        _thresholdsJson([_entry('overall.acceptedAccuracy.value', 0.9)]),
      );

      bool passedFor(double value) => gate
          .evaluate(
            _metrics(acceptedAccuracy: _ratio(value: value)),
            thresholds,
          )
          .passed;

      expect(passedFor(0.899), isFalse);
      expect(passedFor(0.9), isTrue);
      expect(passedFor(0.901), isTrue);
    });

    test('higherIsBetter == false: below/on/above 2.0', () {
      final thresholds = gate.parseThresholds(
        _thresholdsJson([
          _entry('overall.falseVisibleEventsPerMinute.value', 2.0),
        ]),
      );

      bool passedFor(double value) => gate
          .evaluate(
            _metrics(falseVisibleEventsPerMinute: _rate(value: value)),
            thresholds,
          )
          .passed;

      expect(passedFor(2.001), isFalse);
      expect(passedFor(2.0), isTrue);
      expect(passedFor(1.999), isTrue);
    });

    test('the direction fixed at ">=" would wrongly pass 2.001 on a '
        'lower-is-better metric', () {
      final thresholds = gate.parseThresholds(
        _thresholdsJson([
          _entry('overall.falseVisibleEventsPerMinute.value', 2.0),
        ]),
      );
      final verdict = gate.evaluate(
        _metrics(falseVisibleEventsPerMinute: _rate(value: 2.001)),
        thresholds,
      );
      expect(verdict.findings.single.higherIsBetter, isFalse);
      expect(verdict.passed, isFalse);
    });
  });

  group('verdict aggregation', () {
    test('one failing finding among several fails the whole verdict', () {
      final thresholds = gate.parseThresholds(
        _thresholdsJson([
          _entry('overall.acceptedAccuracy.value', 0.9),
          _entry('overall.coverage.value', 0.7),
        ]),
      );
      final verdict = gate.evaluate(
        _metrics(
          acceptedAccuracy: _ratio(value: 0.95),
          coverage: _ratio(value: 0.5),
        ),
        thresholds,
      );
      expect(verdict.passed, isFalse);
      expect(verdict.findings.where((f) => f.passed).length, 1);
    });

    test('every finding passing passes the verdict', () {
      final thresholds = gate.parseThresholds(
        _thresholdsJson([
          _entry('overall.acceptedAccuracy.value', 0.9),
          _entry('overall.coverage.value', 0.7),
        ]),
      );
      final verdict = gate.evaluate(
        _metrics(
          acceptedAccuracy: _ratio(value: 0.95),
          coverage: _ratio(value: 0.75),
        ),
        thresholds,
      );
      expect(verdict.passed, isTrue);
    });
  });

  group('typed configuration errors', () {
    test('unknown schemaVersion is a typed error, never a default', () {
      expect(
        () => gate.parseThresholds({
          'schemaVersion': '99',
          'thresholdsVersion': 'x',
          'thresholds': <Object?>[],
        }),
        throwsA(
          isA<RecognitionGateConfigException>().having(
            (e) => e.kind,
            'kind',
            RecognitionGateConfigErrorKind.unknownSchemaVersion,
          ),
        ),
      );
    });

    test('a threshold entry declaring higherIsBetter is a typed error', () {
      expect(
        () => gate.parseThresholds(
          _thresholdsJson([
            {
              'metricPath': 'overall.acceptedAccuracy.value',
              'threshold': 0.9,
              'higherIsBetter': true,
            },
          ]),
        ),
        throwsA(
          isA<RecognitionGateConfigException>().having(
            (e) => e.kind,
            'kind',
            RecognitionGateConfigErrorKind.directionDeclared,
          ),
        ),
      );
    });

    test('a threshold entry declaring ">=" is a typed error', () {
      expect(
        () => gate.parseThresholds(
          _thresholdsJson([
            {
              'metricPath': 'overall.acceptedAccuracy.value',
              'threshold': 0.9,
              '>=': 0.9,
            },
          ]),
        ),
        throwsA(
          isA<RecognitionGateConfigException>().having(
            (e) => e.kind,
            'kind',
            RecognitionGateConfigErrorKind.directionDeclared,
          ),
        ),
      );
    });

    test('an unrecognised metricPath is a typed error, never silently '
        'skipped', () {
      final thresholds = gate.parseThresholds(
        _thresholdsJson([_entry('overall.doesNotExist.value', 1.0)]),
      );
      expect(
        () => gate.evaluate(_metrics(), thresholds),
        throwsA(isA<RecognitionGateConfigException>()),
      );
    });

    test('a metricPath outside the overall scope is a typed error', () {
      final thresholds = gate.parseThresholds(
        _thresholdsJson([_entry('group.player.acceptedAccuracy.value', 1.0)]),
      );
      expect(
        () => gate.evaluate(_metrics(), thresholds),
        throwsA(isA<RecognitionGateConfigException>()),
      );
    });
  });

  group('deterministic ordering', () {
    test('entries and findings are sorted by metricPath regardless of '
        'source order', () {
      final thresholds = gate.parseThresholds(
        _thresholdsJson([
          _entry('overall.onsetTolerance50Ms.f1', 0.82),
          _entry('overall.acceptedAccuracy.value', 0.9),
        ]),
      );
      expect(thresholds.entries.map((e) => e.metricPath).toList(), [
        'overall.acceptedAccuracy.value',
        'overall.onsetTolerance50Ms.f1',
      ]);

      final verdict = gate.evaluate(_metrics(), thresholds);
      expect(verdict.findings.map((f) => f.metricPath).toList(), [
        'overall.acceptedAccuracy.value',
        'overall.onsetTolerance50Ms.f1',
      ]);
    });
  });

  group('scoped false-visible-event metrics are nameable via the extractor '
      'map (acceptance 7, ADR 0521 D5)', () {
    test('both new metric paths exist in recognitionMetricExtractors', () {
      expect(
        recognitionMetricExtractors.containsKey(
          'falseVisibleDirectionEventsPerMinute.value',
        ),
        isTrue,
      );
      expect(
        recognitionMetricExtractors.containsKey(
          'falseVisibleChordEventsPerMinute.value',
        ),
        isTrue,
      );
    });

    test('the gate evaluates a threshold against the direction-scoped rate, '
        'direction read from its own definition (lower-is-better)', () {
      final thresholds = gate.parseThresholds(
        _thresholdsJson([
          _entry('overall.falseVisibleDirectionEventsPerMinute.value', 2.0),
        ]),
      );
      final verdict = gate.evaluate(
        _metrics(falseVisibleDirectionEventsPerMinute: _rate(value: 1.5)),
        thresholds,
      );
      expect(verdict.findings.single.higherIsBetter, isFalse);
      expect(verdict.passed, isTrue);
    });

    test('the gate evaluates a threshold against the chord-scoped rate and '
        'fails it above the boundary', () {
      final thresholds = gate.parseThresholds(
        _thresholdsJson([
          _entry('overall.falseVisibleChordEventsPerMinute.value', 1.0),
        ]),
      );
      final verdict = gate.evaluate(
        _metrics(falseVisibleChordEventsPerMinute: _rate(value: 2.0)),
        thresholds,
      );
      expect(verdict.findings.single.passed, isFalse);
    });
  });

  group('shipped v1 threshold file (ADR 0511 D9 — pinned, not remeasured)', () {
    test('carries exactly the Ch14 §7.2/§7.4 Alpha values this round maps', () {
      final source = File(
        '${_findProjectRoot().path}/evaluation/recognition/'
        'recognition_release_gate.json',
      ).readAsStringSync();
      final thresholds = gate.parseThresholdsJsonString(source);

      expect(thresholds.schemaVersion, '1');
      expect(thresholds.thresholdsVersion, 'ch14-alpha-v1');

      const expected = <String, double>{
        'overall.acceptedAccuracy.value': 0.9,
        'overall.chordMacroF1.value': 0.7,
        'overall.chordNoChordF1.f1': 0.88,
        'overall.chordWeightedAccuracy.value': 0.8,
        'overall.coverage.value': 0.7,
        'overall.directionF1.value': 0.8,
        'overall.falseVisibleEventsPerMinute.value': 2.0,
        'overall.latencyP50Ms.value': 180.0,
        'overall.latencyP95Ms.value': 280.0,
        'overall.onsetTolerance50Ms.f1': 0.82,
      };

      expect(
        thresholds.entries.map((e) => e.metricPath).toList(),
        expected.keys.toList()..sort(),
      );
      for (final entry in thresholds.entries) {
        expect(
          entry.threshold,
          expected[entry.metricPath],
          reason: entry.metricPath,
        );
      }
    });

    test('the shipped file evaluates FAIL against the current legacy-DSP '
        'baseline (docs/eval/recognition-release-guard.md) — this is the '
        'gate working as intended, not a bug', () {
      final source = File(
        '${_findProjectRoot().path}/evaluation/recognition/'
        'recognition_release_gate.json',
      ).readAsStringSync();
      final thresholds = gate.parseThresholdsJsonString(source);
      // Legacy baseline: chord accuracy 67.1%, onset F1 67.4%, direction
      // 80.7% — all below the pinned Alpha thresholds above.
      final verdict = gate.evaluate(
        _metrics(
          onset50: _prf1(f1: 0.674),
          directionF1: _macro(value: 0.807),
          acceptedAccuracy: _ratio(value: 0.671),
          chordWeightedAccuracy: _ratio(value: 0.671),
        ),
        thresholds,
      );
      expect(verdict.passed, isFalse);
    });
  });
}

// --- Threshold-JSON fixtures -------------------------------------------

Map<String, Object?> _thresholdsJson(List<Map<String, Object?>> thresholds) => {
  'schemaVersion': '1',
  'thresholdsVersion': 'test-v1',
  'thresholds': thresholds,
};

Map<String, Object?> _entry(String metricPath, double threshold) => {
  'metricPath': metricPath,
  'threshold': threshold,
};

Directory _findProjectRoot() {
  var candidate = Directory.current.absolute;
  while (true) {
    final pubspec = File('${candidate.path}/pubspec.yaml');
    final agents = File('${candidate.path}/AGENTS.md');
    if (pubspec.existsSync() && agents.existsSync()) {
      return candidate;
    }
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw StateError('Could not find the StrumSight repository root.');
    }
    candidate = parent;
  }
}

// --- RecognitionMetrics fixtures ----------------------------------------

RecognitionMetricDefinition _def({bool higherIsBetter = true}) =>
    RecognitionMetricDefinition(
      higherIsBetter: higherIsBetter,
      description: 'test definition',
      numeratorDescription: 'numerator',
      denominatorDescription: 'denominator',
    );

RecognitionPrecisionRecallF1 _prf1({
  double? f1 = 0.9,
  bool higherIsBetter = true,
}) => RecognitionPrecisionRecallF1(
  precision: f1,
  recall: f1,
  f1: f1,
  truePositives: 9,
  falsePositives: 1,
  falseNegatives: 1,
  definition: _def(higherIsBetter: higherIsBetter),
);

RecognitionMacroF1 _macro({double? value = 0.9, bool higherIsBetter = true}) =>
    RecognitionMacroF1(
      value: value,
      perLabel: const {},
      definition: _def(higherIsBetter: higherIsBetter),
    );

RecognitionCountRatioMetric _ratio({
  double? value = 0.9,
  int numerator = 9,
  int denominator = 10,
  bool higherIsBetter = true,
}) => RecognitionCountRatioMetric(
  value: value,
  numerator: numerator,
  denominator: denominator,
  definition: _def(higherIsBetter: higherIsBetter),
);

RecognitionRateMetric _rate({
  double? value = 1.0,
  int eventCount = 1,
  double durationMinutes = 1.0,
  bool higherIsBetter = false,
}) => RecognitionRateMetric(
  value: value,
  eventCount: eventCount,
  durationMinutes: durationMinutes,
  definition: _def(higherIsBetter: higherIsBetter),
);

RecognitionScalarMetric _scalar({
  double? value = 100.0,
  int sampleCount = 10,
  bool higherIsBetter = false,
}) => RecognitionScalarMetric(
  value: value,
  sampleCount: sampleCount,
  definition: _def(higherIsBetter: higherIsBetter),
);

RecognitionCalibrationMetrics _calib() => RecognitionCalibrationMetrics(
  expectedCalibrationError: 0.05,
  observationCount: 10,
  bins: const [],
  definition: _def(higherIsBetter: false),
);

RecognitionMetrics _metrics({
  RecognitionPrecisionRecallF1? onset50,
  RecognitionMacroF1? directionF1,
  RecognitionCountRatioMetric? acceptedAccuracy,
  RecognitionCountRatioMetric? coverage,
  RecognitionRateMetric? falseVisibleEventsPerMinute,
  RecognitionRateMetric? falseVisibleDirectionEventsPerMinute,
  RecognitionRateMetric? falseVisibleChordEventsPerMinute,
  RecognitionScalarMetric? latencyP50,
  RecognitionScalarMetric? latencyP95,
  RecognitionCountRatioMetric? chordWeightedAccuracy,
  RecognitionMacroF1? chordMacroF1,
  RecognitionPrecisionRecallF1? chordNoChordF1,
  RecognitionCountRatioMetric? chordUnknownFalseAccept,
}) => RecognitionMetrics(
  caseCount: 1,
  onsetTolerance25Ms: _prf1(),
  onsetTolerance50Ms: onset50 ?? _prf1(),
  onsetTolerance100Ms: _prf1(),
  anyStrumF1: _prf1(),
  directionF1: directionF1 ?? _macro(),
  acceptedAccuracy: acceptedAccuracy ?? _ratio(),
  coverage: coverage ?? _ratio(),
  falseVisibleEventsPerMinute: falseVisibleEventsPerMinute ?? _rate(),
  falseVisibleDirectionEventsPerMinute:
      falseVisibleDirectionEventsPerMinute ?? _rate(),
  falseVisibleChordEventsPerMinute: falseVisibleChordEventsPerMinute ?? _rate(),
  latencyP50Ms: latencyP50 ?? _scalar(),
  latencyP95Ms: latencyP95 ?? _scalar(),
  calibration: _calib(),
  brierScore: _scalar(higherIsBetter: false),
  chordWeightedAccuracy: chordWeightedAccuracy ?? _ratio(),
  chordMacroF1: chordMacroF1 ?? _macro(),
  chordNoChordF1: chordNoChordF1 ?? _prf1(),
  chordUnknownFalseAccept:
      chordUnknownFalseAccept ?? _ratio(higherIsBetter: false),
);
