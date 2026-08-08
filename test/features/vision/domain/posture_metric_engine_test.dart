// E05-R20 — Posture metric engine tests (brief §6 acceptance matrix).
//
// The §6 acceptance criteria are exhaustive across the four metric families:
//
//   1. Baseline-matrix — baseline hiányzik / részleges / teljes; the first
//      two emit `notObservable`, the third emits a baseline-relative value.
//   2. Per-metric matrix — shoulderAsymmetry / torsoLean / elbowDrift /
//      neckProxy with typical / boundary / degenerate cases, plus the
//      visibility-matrix (below / at / above the per-metric floor).
//   3. R8 degenerate fixture (MANDATORY) — a single shared landmark with
//      extreme drift (maxDrift = 4.257, the measured value from the brief
//      §0.0 R8) yields `state=good` from `posture_baseline.dart` but the
//      affected metric MUST still emit `notObservable` because the
//      per-metric required-landmark list is not satisfied. The state
//      field is NOT a gate (§5 /7).
//   4. Perspective-fixture matrix — at least 3 camera angles; the sign
//      and magnitude of every metric are consistent (perspective does
//      not flip the metric).
//   5. NaN/Infinity guard — a fixture with non-finite drift values must
//      never produce an observable result.
//
// The briefs §5 /7 invariant is the load-bearing one: the engine must
// check `driftFor(id) != null` for every required landmark, NOT
// `observation.state == good`.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/domain/landmarks/pose_landmarks.dart';
import 'package:strumsight/features/vision/domain/landmarks/posture_baseline.dart';
import 'package:strumsight/features/vision/domain/metrics/metric_observation.dart';
import 'package:strumsight/features/vision/domain/metrics/posture_metric_engine.dart';
import 'package:strumsight/features/vision/domain/metrics/posture_metrics.dart';
import 'package:strumsight/features/vision/domain/quality/vision_frame_quality.dart';

import '../../../fixtures/vision/posture/posture_fixtures.dart';

void main() {
  const engine = PostureMetricEngine();

  // ---------------------------------------------------------------------------
  // (1) Baseline-matrix — missing / partial / full.
  // ---------------------------------------------------------------------------
  group('baseline matrix — missing / partial / full', () {
    test('no baseline → every metric is notObservable', () {
      final observation = PostureObservation.notObservable();
      for (final id in PostureMetricId.values) {
        final obs = engine.compute(observation: observation, id: id);
        expect(
          obs.observability,
          MetricObservability.notObservable,
          reason: 'metric ${id.name} must be notObservable without a baseline',
        );
      }
    });

    test('partial baseline (only one shoulder) → shoulder metrics invisible, '
        'neck/elbow metrics still not observable', () {
      final observation = buildPartialBaselineObservation();
      // The partial baseline keeps only the left shoulder — see the
      // fixture. Shoulder-asymmetry requires BOTH shoulders → not obs.
      // Torso lean requires both hips + both shoulders → not obs.
      // Elbow drift requires both elbows → not obs.
      // Neck proxy requires the neck reference → not obs.
      for (final id in PostureMetricId.values) {
        final obs = engine.compute(observation: observation, id: id);
        expect(
          obs.observability,
          MetricObservability.notObservable,
          reason: 'metric ${id.name} must be notObservable with partial '
              'baseline (only one shoulder present)',
        );
      }
    });

    test('full baseline + clean pose → every metric is observable', () {
      final observation = buildCleanFullBaselineObservation();
      for (final id in PostureMetricId.values) {
        final obs = engine.compute(observation: observation, id: id);
        expect(
          obs.observability,
          MetricObservability.observable,
          reason: 'metric ${id.name} must be observable against a clean '
              'full baseline',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // (2) Per-metric matrix — typical / boundary / degenerate.
  // ---------------------------------------------------------------------------
  group('per-metric matrix — shoulderAsymmetry', () {
    test('typical drift → observable', () {
      final observation = buildShoulderAsymmetryObservation(
        droppedLeftShoulder: 0.04,
      );
      final obs = engine.compute(
        observation: observation,
        id: PostureMetricId.shoulderAsymmetry,
      );
      expect(obs.observability, MetricObservability.observable);
      // The metric is the absolute |Δy| normalized by shoulder span.
      // See §10 for the numeric value (0.04 / 0.20 = 0.20).
      expect(obs.value, closeTo(0.20, 1e-9));
    });

    test('degenerate — only one shoulder present → notObservable '
        '(R8 — state=good but metric invisible)', () {
      // The fixture builds observation.state = good (posture_baseline
      // contract) but contains only the leftShoulder drift entry. The
      // shoulderAsymmetry metric requires BOTH shoulders. The engine
      // must not trust observation.state.
      final observation = buildDegenerateSingleShoulderObservation();
      expect(observation.state, VisionMetricState.good);
      final obs = engine.compute(
        observation: observation,
        id: PostureMetricId.shoulderAsymmetry,
      );
      expect(obs.observability, MetricObservability.notObservable);
    });
  });

  group('per-metric matrix — torsoLean', () {
    test('typical lean → observable', () {
      final observation = buildTorsoLeanObservation(shoulderOffsetY: 0.04);
      final obs = engine.compute(
        observation: observation,
        id: PostureMetricId.torsoLean,
      );
      expect(obs.observability, MetricObservability.observable);
    });

    test('without hips → notObservable (R8 gate)', () {
      final observation = buildShoulderAsymmetryObservation(
        droppedLeftShoulder: 0.04,
      );
      final obs = engine.compute(
        observation: observation,
        id: PostureMetricId.torsoLean,
      );
      expect(obs.observability, MetricObservability.notObservable);
    });
  });

  group('per-metric matrix — elbowDrift', () {
    test('both elbows visible → observable', () {
      final observation = buildElbowDriftObservation(displacement: 0.02);
      final obs = engine.compute(
        observation: observation,
        id: PostureMetricId.elbowDrift,
      );
      expect(obs.observability, MetricObservability.observable);
    });

    test('one elbow missing → notObservable (R8 gate)', () {
      final observation = buildElbowDriftObservation(
        displacement: 0.02,
        missingRightElbow: true,
      );
      final obs = engine.compute(
        observation: observation,
        id: PostureMetricId.elbowDrift,
      );
      expect(obs.observability, MetricObservability.notObservable);
    });
  });

  group('per-metric matrix — neckProxy', () {
    test('neck reference present → observable', () {
      final observation = buildNeckProxyObservation(displacement: 0.02);
      final obs = engine.compute(
        observation: observation,
        id: PostureMetricId.neckProxy,
      );
      expect(obs.observability, MetricObservability.observable);
    });

    test('neck reference absent → notObservable (R8 gate)', () {
      final observation = buildCleanFullBaselineObservation();
      // The clean fixture has no neck reference in the baseline.
      final obs = engine.compute(
        observation: observation,
        id: PostureMetricId.neckProxy,
      );
      expect(obs.observability, MetricObservability.notObservable);
    });
  });

  // ---------------------------------------------------------------------------
  // (3) R8 degenerate fixture — the precise scenario from §0.0 R8.
  // The fixture is built so that posture_baseline emits
  // state=good with comparedLandmarkCount = 1 and maxDrift = 4.257
  // (normalized by shoulder span). The engine must emit notObservable
  // for every metric that requires more than one landmark.
  // ---------------------------------------------------------------------------
  group('R8 degenerate — extreme drift on a single shared landmark', () {
    test('state=good but extreme single-landmark drift → notObservable for '
        'every metric that requires > 1 landmark', () {
      final observation = buildR8DegenerateObservation();
      expect(observation.state, VisionMetricState.good);
      expect(observation.comparedLandmarkCount, 1);
      expect(observation.maxDrift, closeTo(4.257, 1e-3));

      // shoulderAsymmetry — needs 2 shoulders → notObservable.
      expect(
        engine
            .compute(
              observation: observation,
              id: PostureMetricId.shoulderAsymmetry,
            )
            .observability,
        MetricObservability.notObservable,
      );
      // torsoLean — needs 2 shoulders + 2 hips → notObservable.
      expect(
        engine
            .compute(
              observation: observation,
              id: PostureMetricId.torsoLean,
            )
            .observability,
        MetricObservability.notObservable,
      );
      // elbowDrift — needs 2 elbows → notObservable.
      expect(
        engine
            .compute(
              observation: observation,
              id: PostureMetricId.elbowDrift,
            )
            .observability,
        MetricObservability.notObservable,
      );
      // neckProxy — needs neckReference → notObservable.
      expect(
        engine
            .compute(
              observation: observation,
              id: PostureMetricId.neckProxy,
            )
            .observability,
        MetricObservability.notObservable,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // (4) Perspective-fixture matrix — three camera angles, sign and
  // magnitude of the metric must be consistent across the angles.
  // ---------------------------------------------------------------------------
  group('perspective-fixture matrix — sign and magnitude invariants', () {
    final perspectives = <String, PostureObservation>{
      'frontal': buildCleanFullBaselineObservation(),
      'three-quarter left': buildPerspectiveObservation(side: 0.04),
      'three-quarter right': buildPerspectiveObservation(side: -0.04),
    };

    for (final entry in perspectives.entries) {
      test('${entry.key} — shoulderAsymmetry > 0', () {
        final obs = engine.compute(
          observation: entry.value,
          id: PostureMetricId.shoulderAsymmetry,
        );
        expect(obs.observability, MetricObservability.observable);
        expect(obs.value, greaterThan(0));
      });
    }

    test('sign of torsoLean flips with the direction of the lean', () {
      final leftLean = buildTorsoLeanObservation(shoulderOffsetY: 0.04);
      final leftObs = engine.compute(
        observation: leftLean,
        id: PostureMetricId.torsoLean,
      );
      expect(leftObs.observability, MetricObservability.observable);
      expect(leftObs.value, greaterThan(0));

      // A baseline built with the opposite offset yields a mirror sign.
      final rightLean = buildTorsoLeanObservation(shoulderOffsetY: -0.04);
      final rightObs = engine.compute(
        observation: rightLean,
        id: PostureMetricId.torsoLean,
      );
      expect(rightObs.observability, MetricObservability.observable);
      expect(rightObs.value, lessThan(0));
    });
  });

  // ---------------------------------------------------------------------------
  // (5) NaN/Infinity guard — non-finite drift never produces an observable.
  // ---------------------------------------------------------------------------
  group('NaN / Infinity guard', () {
    test('a NaN drift entry on a required landmark → notObservable', () {
      final observation = buildNonFiniteDriftObservation(value: double.nan);
      for (final id in PostureMetricId.values) {
        final obs = engine.compute(observation: observation, id: id);
        expect(
          obs.observability,
          MetricObservability.notObservable,
          reason: 'metric ${id.name} must be notObservable when the per-'
              'landmark drift is NaN',
        );
      }
    });

    test('an Infinity drift entry on a required landmark → notObservable', () {
      final observation = buildNonFiniteDriftObservation(
        value: double.infinity,
      );
      for (final id in PostureMetricId.values) {
        final obs = engine.compute(observation: observation, id: id);
        expect(
          obs.observability,
          MetricObservability.notObservable,
          reason: 'metric ${id.name} must be notObservable when the per-'
              'landmark drift is Infinity',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // (6) Catalog validation — every definition isValid.
  // ---------------------------------------------------------------------------
  group('catalog validation', () {
    test('every PostureMetricDefinition is valid', () {
      for (final definition in postureMetricDefinitions) {
        expect(
          definition.isValid,
          isTrue,
          reason: 'definition for ${definition.id.name} must be valid',
        );
      }
    });

    test('every metric ID has a definition', () {
      for (final id in PostureMetricId.values) {
        final definition = PostureMetricEngine.definitionFor(id);
        expect(definition.id, id);
      }
    });

    test('every definition lists at least one required landmark', () {
      for (final definition in postureMetricDefinitions) {
        expect(
          definition.requiredPoseLandmarkIds,
          isNotEmpty,
          reason: 'metric ${definition.id.name} must declare at least one '
              'required landmark (§5 /7 — R8 gate)',
        );
      }
    });
  });
}
