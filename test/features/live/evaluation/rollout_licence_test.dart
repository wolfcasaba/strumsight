// E14-R24/R33 (ADR 0537/0541): the rollout stage can never exceed the gate.
//
// What these cells prove:
//   * a user-visible stage is licensed only by ENABLED, PASSING gate rows;
//   * a DISABLED (informational) row licenses nothing — so today's Beta
//     rows, shipped disabled, make `beta` unreachable whatever the
//     configuration says;
//   * `shadow` is NOT gated by accuracy (it is never user-visible) — it is
//     gated by PKG-D's shadow master switch instead;
//   * an unknown stage name resolves to `off`, never to a near match;
//   * the clamp only ever REDUCES exposure and names the limiting metrics;
//   * this file's ladder mirrors PKG-D's `RecognitionRolloutStage` value for
//     value, and the required-threshold mapping matches its own
//     `requiresBetaThresholds`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/recognition_rollout_stage.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_metrics.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_release_gate.dart';
import 'package:strumsight/features/live/domain/evaluation/rollout_licence.dart';

void main() {
  const gate = RecognitionReleaseGate();

  group('the mirror of PKG-D\'s ladder', () {
    test('the flag names match the ones FeatureFlags declares', () {
      expect(
        recognitionRolloutFlagNames[RecognitionGateBand.strum],
        'strumModelRolloutStage',
      );
      expect(
        recognitionRolloutFlagNames[RecognitionGateBand.chord],
        'chordModelRolloutStage',
      );
    });

    test('every RecognitionRolloutStage value has a same-named licence '
        'stage, in the same order', () {
      expect(
        LicensedRolloutStage.values.map((stage) => stage.name).toList(),
        RecognitionRolloutStage.values.map((stage) => stage.name).toList(),
      );
    });

    test('the required gate stage matches the ladder\'s own '
        'requiresBetaThresholds', () {
      for (final stage in RecognitionRolloutStage.values) {
        final mirrored = LicensedRolloutStage.tryParseName(stage.name)!;
        final required = requiredGateStageFor(mirrored);
        if (!stage.isUserVisible) {
          expect(required, isNull, reason: stage.name);
          continue;
        }
        expect(
          required,
          stage.requiresBetaThresholds
              ? RecognitionGateStage.beta
              : RecognitionGateStage.alpha,
          reason: stage.name,
        );
      }
    });
  });

  group('licensing', () {
    final thresholds = gate.parseThresholds(_thresholdsJson());

    test('passing Alpha rows license alpha, and the DISABLED Beta rows stop '
        'the ladder there even when the configuration asks for ga', () {
      final verdict = gate.evaluate(_passingMetrics(), thresholds);
      expect(verdict.passed, isTrue);

      final decision = clampRolloutStage(
        band: RecognitionGateBand.strum,
        stageName: 'ga',
        verdict: verdict,
      );

      expect(decision.effective, LicensedRolloutStage.alpha);
      expect(decision.requested, LicensedRolloutStage.ga);
      expect(decision.wasClamped, isTrue);
      expect(decision.reason, RolloutClampReason.gateRowDisabled);
      expect(
        decision.limitingMetricPaths,
        contains('overall.onsetTolerance50Ms.f1'),
      );
    });

    test('a failing Alpha row drops the effective stage to shadow (which '
        'accuracy never licenses anyway) and names the failing metric', () {
      final verdict = gate.evaluate(
        _passingMetrics(onset50F1: 0.4),
        thresholds,
      );

      final decision = clampRolloutStage(
        band: RecognitionGateBand.strum,
        stageName: 'alpha',
        verdict: verdict,
      );

      expect(decision.effective, LicensedRolloutStage.shadow);
      expect(
        decision.effective.rank,
        lessThan(LicensedRolloutStage.alpha.rank),
      );
      expect(decision.reason, RolloutClampReason.gateRowFailing);
      expect(decision.limitingMetricPaths, <String>[
        'overall.onsetTolerance50Ms.f1',
      ]);
    });

    test('a MISSING metric fails closed exactly like a failing one', () {
      final verdict = gate.evaluate(
        _passingMetrics(onset50F1: null),
        thresholds,
      );

      final decision = clampRolloutStage(
        band: RecognitionGateBand.strum,
        stageName: 'alpha',
        verdict: verdict,
      );

      expect(decision.effective, LicensedRolloutStage.shadow);
      expect(decision.wasClamped, isTrue);
    });

    test('shadow is licensed even by a red gate — it is never user-visible, '
        'and PKG-D\'s master switch is what gates it', () {
      final verdict = gate.evaluate(
        _passingMetrics(onset50F1: 0.1, coverage: 0.1),
        thresholds,
      );

      final decision = clampRolloutStage(
        band: RecognitionGateBand.strum,
        stageName: 'shadow',
        verdict: verdict,
      );

      expect(decision.effective, LicensedRolloutStage.shadow);
      expect(decision.wasClamped, isFalse);
    });

    test('the chord band is not held by a strum-band failure, but IS held '
        'by a shared-band failure', () {
      final strumFailure = gate.evaluate(
        _passingMetrics(onset50F1: 0.4),
        thresholds,
      );
      final sharedFailure = gate.evaluate(
        _passingMetrics(coverage: 0.1),
        thresholds,
      );

      expect(
        clampRolloutStage(
          band: RecognitionGateBand.chord,
          stageName: 'alpha',
          verdict: strumFailure,
        ).effective,
        LicensedRolloutStage.alpha,
      );
      expect(
        clampRolloutStage(
          band: RecognitionGateBand.chord,
          stageName: 'alpha',
          verdict: sharedFailure,
        ).effective,
        LicensedRolloutStage.shadow,
      );
    });

    test('asking for less than the gate licenses is honoured — the clamp '
        'only ever reduces exposure', () {
      final verdict = gate.evaluate(_passingMetrics(), thresholds);

      final decision = clampRolloutStage(
        band: RecognitionGateBand.strum,
        stageName: 'off',
        verdict: verdict,
      );

      expect(decision.effective, LicensedRolloutStage.off);
      expect(decision.wasClamped, isFalse);
    });

    test('an unknown stage name resolves to off, never to a near match', () {
      final verdict = gate.evaluate(_passingMetrics(), thresholds);

      for (final value in <String?>[null, '', 'ALPHA', 'internalAlpha', '2']) {
        final decision = clampRolloutStage(
          band: RecognitionGateBand.strum,
          stageName: value,
          verdict: verdict,
        );
        expect(decision.effective, LicensedRolloutStage.off, reason: value);
        expect(
          decision.reason,
          RolloutClampReason.unrecognisedStageName,
          reason: value,
        );
      }
    });

    test('a gate with no row for a stage licenses nothing for it — an '
        'empty requirement is not a met requirement', () {
      final alphaOnly = gate.parseThresholds({
        'schemaVersion': '1',
        'thresholdsVersion': 'alpha-only',
        'thresholds': <Object?>[
          <String, Object?>{
            'metricPath': 'overall.coverage.value',
            'threshold': 0.7,
            'stage': 'alpha',
            'band': 'shared',
          },
        ],
      });
      final verdict = gate.evaluate(_passingMetrics(), alphaOnly);

      final decision = clampRolloutStage(
        band: RecognitionGateBand.strum,
        stageName: 'beta',
        verdict: verdict,
      );

      expect(decision.effective, LicensedRolloutStage.alpha);
      expect(decision.reason, RolloutClampReason.noGateRowForStage);
    });
  });

  group('the shipped threshold file', () {
    RecognitionGateThresholds shippedThresholds() {
      final source = File(
        '${_findProjectRoot().path}/evaluation/recognition/'
        'recognition_release_gate.json',
      ).readAsStringSync();
      return gate.parseThresholdsJsonString(source);
    }

    test('carries the Ch14 §7.3/§7.5 Beta rows, every one of them '
        'DISABLED — they are visible targets, not live gates', () {
      final thresholds = shippedThresholds();

      final beta = thresholds.entries
          .where((entry) => entry.stage == RecognitionGateStage.beta)
          .toList();

      expect(beta, isNotEmpty);
      for (final entry in beta) {
        expect(entry.enabled, isFalse, reason: entry.metricPath);
      }
      expect(
        beta.map((entry) => entry.metricPath),
        containsAll(<String>[
          'overall.directionF1.perLabel.down.f1',
          'overall.directionF1.perLabel.up.f1',
          'overall.chordMacroF1.weakestSupportedRecall',
        ]),
      );
    });

    test('every Alpha row is enabled — the Alpha gate is live', () {
      final thresholds = shippedThresholds();

      final alpha = thresholds.entries
          .where((entry) => entry.stage == RecognitionGateStage.alpha)
          .toList();

      expect(alpha, hasLength(10));
      for (final entry in alpha) {
        expect(entry.enabled, isTrue, reason: entry.metricPath);
      }
    });

    test('with the shipped file, no metric set can reach beta while the '
        'Beta rows are disabled', () {
      final verdict = gate.evaluate(_passingMetrics(), shippedThresholds());

      for (final band in <RecognitionGateBand>[
        RecognitionGateBand.strum,
        RecognitionGateBand.chord,
      ]) {
        final decision = clampRolloutStage(
          band: band,
          stageName: 'beta',
          verdict: verdict,
        );
        expect(
          decision.effective,
          LicensedRolloutStage.alpha,
          reason: band.name,
        );
      }
    });
  });
}

Map<String, Object?> _thresholdsJson() => <String, Object?>{
  'schemaVersion': '1',
  'thresholdsVersion': 'test-stages-v1',
  'thresholds': <Object?>[
    <String, Object?>{
      'metricPath': 'overall.onsetTolerance50Ms.f1',
      'threshold': 0.82,
      'stage': 'alpha',
      'band': 'strum',
    },
    <String, Object?>{
      'metricPath': 'overall.coverage.value',
      'threshold': 0.7,
      'stage': 'alpha',
      'band': 'shared',
    },
    <String, Object?>{
      'metricPath': 'overall.onsetTolerance50Ms.f1',
      'threshold': 0.87,
      'stage': 'beta',
      'band': 'strum',
      'enabled': false,
    },
    <String, Object?>{
      'metricPath': 'overall.coverage.value',
      'threshold': 0.8,
      'stage': 'beta',
      'band': 'shared',
      'enabled': false,
    },
  ],
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

RecognitionMetricDefinition _def({bool higherIsBetter = true}) =>
    RecognitionMetricDefinition(
      higherIsBetter: higherIsBetter,
      description: 'test definition',
      numeratorDescription: 'numerator',
      denominatorDescription: 'denominator',
    );

RecognitionPrecisionRecallF1 _prf1({double? f1 = 0.95}) =>
    RecognitionPrecisionRecallF1(
      precision: f1,
      recall: f1,
      f1: f1,
      truePositives: 19,
      falsePositives: 1,
      falseNegatives: 1,
      definition: _def(),
    );

RecognitionMacroF1 _macro({double? value = 0.95}) => RecognitionMacroF1(
  value: value,
  perLabel: <String, RecognitionPrecisionRecallF1>{
    'down': _prf1(),
    'up': _prf1(),
  },
  definition: _def(),
);

RecognitionCountRatioMetric _ratio({
  double? value = 0.95,
  bool higherIsBetter = true,
}) => RecognitionCountRatioMetric(
  value: value,
  numerator: 19,
  denominator: 20,
  definition: _def(higherIsBetter: higherIsBetter),
);

RecognitionRateMetric _rate({double? value = 0.5}) => RecognitionRateMetric(
  value: value,
  eventCount: 1,
  durationMinutes: 2,
  definition: _def(higherIsBetter: false),
);

RecognitionScalarMetric _scalar({double? value = 100}) =>
    RecognitionScalarMetric(
      value: value,
      sampleCount: 20,
      definition: _def(higherIsBetter: false),
    );

RecognitionCalibrationMetrics _calibration() => RecognitionCalibrationMetrics(
  expectedCalibrationError: 0.05,
  observationCount: 20,
  bins: const <RecognitionCalibrationBin>[],
  definition: _def(higherIsBetter: false),
);

/// A metric set that clears every Alpha threshold in the shipped file.
RecognitionMetrics _passingMetrics({
  double? onset50F1 = 0.95,
  double? coverage = 0.95,
}) => RecognitionMetrics(
  caseCount: 1,
  onsetTolerance25Ms: _prf1(),
  onsetTolerance50Ms: _prf1(f1: onset50F1),
  onsetTolerance100Ms: _prf1(),
  anyStrumF1: _prf1(),
  directionF1: _macro(),
  acceptedAccuracy: _ratio(),
  coverage: _ratio(value: coverage),
  falseVisibleEventsPerMinute: _rate(),
  falseVisibleDirectionEventsPerMinute: _rate(),
  falseVisibleChordEventsPerMinute: _rate(),
  latencyP50Ms: _scalar(),
  latencyP95Ms: _scalar(),
  calibration: _calibration(),
  brierScore: _scalar(value: 0.05),
  chordWeightedAccuracy: _ratio(),
  chordMacroF1: _macro(),
  chordNoChordF1: _prf1(),
  chordUnknownFalseAccept: _ratio(value: 0.01, higherIsBetter: false),
);
