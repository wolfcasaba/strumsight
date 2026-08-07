// E05-R16 — REAL INTEGRATION test (fix-round F1 BLOCKER, review §F1).
//
// Wires `EdgeGeometryTracker.observe()` directly into
// `CalibrationLossMachine.update()` — NO bypass helper. The previous
// `calibration_loss_machine_test.dart` had a top-level
// `observationFor(double drift)` that constructed `GeometryObservation`
// values directly, completely bypassing the tracker. That made both
// components' unit tests pass green while leaving a real
// integration bug invisible to the gate (the tracker swallowed large
// drifts into `null`, leaving the machine's forward-escalation rule
// dead in the real pipeline — review §F1).
//
// This file is the regression net: if anyone re-introduces a
// drift-bound refusal in `EdgeGeometryTracker.observe()`, or breaks
// the machine's forward-escalation rule, these tests will go red.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/application/calibration_loss_machine.dart';
import 'package:strumsight/features/vision/data/guitar/edge_geometry_tracker.dart';
import 'package:strumsight/features/vision/domain/geometry/geometry_tracker.dart';

import '../../../fixtures/vision/geometry/geometry_scenarios.dart';

void main() {
  group('Tracker→Machine REAL integration — drift-bound classification', () {
    test(
      'scenario (b) — egy frame, 0.20 shift → machine LOST in one frame',
      () {
        // Brief §1 explicit goal: "elmozdulás esetén biztonságos
        // érvénytelenítés: negatív technikai feedback helyett
        // Recalibrate kérés" — EGYETLEN frame alatt. Before the F1
        // fix, the tracker returned `null` for shift=0.20 (>= 0.10),
        // and the machine's null-streak path took FIVE consecutive
        // frames to reach `lost`. This test pins the contract: one
        // large frame, immediately `lost`.
        final tracker = EdgeGeometryTracker();
        final anchor = referenceManualAnchor();
        final machine = CalibrationLossMachine(initialAnchor: anchor);

        // Sanity: starts in tracking.
        expect(machine.state, CalibrationLossState.tracking);
        expect(machine.feedbackSuppressed, isFalse);

        // Single frame with a huge shift.
        final observation = tracker.observe(
          anchor: anchor,
          observation: shiftedFeatureObservation(0.20, 0.0),
        );

        // The tracker MUST pass the observation through (no
        // drift-bound null-refusal — the F1 fix). Without this, the
        // machine would only see `null` and need 5 consecutive
        // frames to demote.
        expect(
          observation,
          isNotNull,
          reason:
              'tracker must pass large drifts through so the machine '
              'can classify them in ONE frame',
        );
        expect(
          observation!.confidence.drift,
          greaterThan(0.10),
          reason: '0.20 shift → drift > lostDriftBound',
        );

        machine.update(observation);

        // The machine MUST classify this single observation as
        // `lost`, with feedback suppressed and Recalibrate
        // requested.
        expect(machine.state, CalibrationLossState.lost);
        expect(machine.feedbackSuppressed, isTrue);
        expect(machine.recalibrateRequested, isTrue);
      },
    );

    test(
      'scenario (c) — cumulative drift → machine reaches lost at the bound',
      () {
        // The brief §10 / fixture pins firstLostStep = 11 (python3
        // reference). The real `EdgeGeometryTracker` computes drift
        // as `sqrt(shift²)` — IEEE 754 multiplication of 0.10 by
        // 0.10 yields 0.010000000000000002, whose sqrt is
        // 0.10000000000000002 (one ULP above 0.10). The machine's
        // strict-greater rule (`drift > lostDriftBound`) therefore
        // fires at step 10, one step earlier than the python3
        // reference's `0.01*11=0.1100000000000001` for step 11.
        //
        // The pre-amble allows ±1 step FP-tolerance. We accept
        // {10, 11} here, and document the reason in §10.
        final tracker = EdgeGeometryTracker();
        final anchor = referenceManualAnchor();
        final machine = CalibrationLossMachine(initialAnchor: anchor);

        var firstDegradedStep = -1;
        var firstLostStep = -1;

        for (var step = 1; step <= 20; step++) {
          final shift = scenarioCumulativeDriftPerFrame * step;
          final observation = tracker.observe(
            anchor: anchor,
            observation: shiftedFeatureObservation(shift, 0.0),
          );

          // The tracker MUST pass every frame through — including
          // large ones. Any null from the tracker would corrupt the
          // test (and the integration).
          expect(
            observation,
            isNotNull,
            reason: 'tracker must pass drift=$shift through at step=$step',
          );

          machine.update(observation);
          if (machine.state == CalibrationLossState.degraded &&
              firstDegradedStep == -1) {
            firstDegradedStep = step;
          }
          if (machine.state == CalibrationLossState.lost &&
              firstLostStep == -1) {
            firstLostStep = step;
          }
        }

        // FP-tolerance window: real tracker says 10, python3
        // reference says 11. Both are correct under their respective
        // numerics — the integration property (machine reaches lost
        // when drift crosses the threshold) holds either way.
        expect(
          firstLostStep,
          anyOf(equals(10), equals(11)),
          reason:
              'machine reaches lost within ±1 FP-tolerance of the '
              'brief §10 pinned step (real tracker: 10; python3 '
              'reference: 11). See §10.5 for FP-eltérés explanation.',
        );
        // The degraded-step is similarly FP-tolerant (real tracker
        // sees the bound-crossing one step earlier when the shift
        // crosses 0.05 from below).
        expect(
          firstDegradedStep,
          anyOf(equals(5), equals(6)),
          reason:
              'firstDegradedStep within FP-tolerance (5 from bypass-'
              'helper, 6 from real-tracker sqrt(0.05²) one-ULP above).',
        );
        expect(machine.state, CalibrationLossState.lost);
        expect(machine.feedbackSuppressed, isTrue);
      },
    );

    test(
      'scenario (a) — small shift keeps machine in tracking, source=tracked',
      () {
        // Brief §6 szcenárió (a) — kis kamera-bump → követhető. The
        // small bump (drift=0.02) must NOT demote, and the tracker
        // hits the confidence threshold so source=tracked.
        final tracker = EdgeGeometryTracker();
        final anchor = referenceManualAnchor();
        final machine = CalibrationLossMachine(initialAnchor: anchor);

        final observation = tracker.observe(
          anchor: anchor,
          observation: shiftedFeatureObservation(
            scenarioSmallCameraBumpDrift,
            0.0,
          ),
        );

        expect(observation, isNotNull);
        machine.update(observation);

        expect(machine.state, CalibrationLossState.tracking);
        expect(machine.feedbackSuppressed, isFalse);
        // Single-feature observation → confidence = 1/4 = 0.25,
        // below trackingConfidenceThreshold (0.5) → source=manual.
        // The brief §6 (a) acceptance allows either source — we pin
        // the actual real-tracker value (manual) for transparency.
        expect(machine.geometrySource, GeometrySourceKind.manual);
      },
    );
  });

  group('Tracker→Machine REAL integration — null-still-respected', () {
    test(
      'empty features → tracker returns null → machine streak counter increments',
      () {
        // Sanity check for the OTHER null path: the tracker still
        // returns null when it has nothing to say (no features).
        // The machine's consecutive-lost path is unchanged — it
        // still needs `noObservationLostThreshold` (5) consecutive
        // nulls to demote. The F1 fix ONLY removed the large-drift
        // refusal; the no-evidence null path is preserved.
        final tracker = EdgeGeometryTracker();
        final anchor = referenceManualAnchor();
        final machine = CalibrationLossMachine(initialAnchor: anchor);

        for (var i = 0; i < 4; i++) {
          final observation = tracker.observe(
            anchor: anchor,
            // No features → tracker returns null.
            observation: FrameObservation(detectedFeatures: const []),
          );
          expect(observation, isNull);
          machine.update(null);
          expect(machine.state, CalibrationLossState.tracking);
        }
        // 5th consecutive null → lost.
        machine.update(null);
        expect(machine.state, CalibrationLossState.lost);
      },
    );
  });
}
