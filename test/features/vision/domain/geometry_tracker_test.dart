// E05-R16 — GeometryTracker contract + EdgeGeometryTracker adapter.
//
// Two layers of assertions:
//   1. The contract: every implementation produces a drift equal to
//      the per-frame translation it observes. The tracker does NOT
//      refuse large drifts (E05-R16 fix-round F1) — `null` is reserved
//      for the true "no evidence" case. The drift-bound classification
//      is owned by `CalibrationLossMachine`, covered by the
//      integration test in
//      `calibration_loss_machine_integration_test.dart`.
//   2. The adapter: `EdgeGeometryTracker` is the only concrete
//      implementation in this round; it pairs each detected feature
//      with the nearest manual anchor and reports the median shift.
//
// Tests use the drift-matrix fixture values from
// `test/fixtures/vision/geometry/geometry_scenarios.dart` — those
// values were computed in `python3 -c` and pinned verbatim in the
// brief §10 handoff.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/features/vision/data/guitar/edge_geometry_tracker.dart';
import 'package:strumsight/features/vision/domain/geometry/geometry_confidence.dart';
import 'package:strumsight/features/vision/domain/geometry/geometry_tracker.dart';

import '../../../fixtures/vision/geometry/geometry_scenarios.dart';

void main() {
  group('GeometryConfidence — drift thresholding', () {
    test('isLost is false at the boundary and true strictly above', () {
      final atBound = GeometryConfidence(
        confidence: 0.9,
        drift: lostDriftBound,
      );
      final above = GeometryConfidence(
        confidence: 0.9,
        drift: lostDriftBound + 1e-6,
      );
      expect(atBound.isLost, isFalse, reason: 'at the bound is not lost');
      expect(above.isLost, isTrue, reason: 'strictly above the bound is lost');
    });

    test('isTracked uses trackingConfidenceThreshold', () {
      final below = GeometryConfidence(
        confidence: trackingConfidenceThreshold - 0.01,
        drift: 0.01,
      );
      final at = GeometryConfidence(
        confidence: trackingConfidenceThreshold,
        drift: 0.01,
      );
      final above = GeometryConfidence(
        confidence: trackingConfidenceThreshold + 0.01,
        drift: 0.01,
      );
      expect(below.isTracked, isFalse);
      expect(at.isTracked, isTrue);
      expect(above.isTracked, isTrue);
    });

    test('rejects non-finite inputs (silent-garbage prohibition)', () {
      // Validates in EVERY build mode (release too) via `ArgumentError`,
      // not the debug-only `AssertionError` — see geometry_confidence.dart
      // doc-comment (E05-R16 fix-round F2 MINOR).
      expect(
        () => GeometryConfidence(confidence: double.nan, drift: 0.01),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => GeometryConfidence(confidence: 0.5, drift: double.infinity),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => GeometryConfidence(confidence: 1.5, drift: 0.01),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('EdgeGeometryTracker — drift-matrix (3 cellák)', () {
    final tracker = EdgeGeometryTracker();
    final anchor = referenceManualAnchor();

    test('cell 1 — drift below bound → tracking (low drift)', () {
      // shift (0.04, 0.0) → drift = sqrt(0.04² + 0²) = 0.04 < 0.05 → tracking
      final observation = tracker.observe(
        anchor: anchor,
        observation: shiftedFeatureObservation(0.04, 0.0),
      );
      expect(
        observation,
        isNotNull,
        reason: 'tracker must produce an observation',
      );
      expect(observation!.confidence.drift, closeTo(0.04, 1e-9));
      expect(observation.confidence.isLost, isFalse);
    });

    test(
      'cell 2 — drift at the bound → tracker passes through; machine classifies as degraded',
      () {
        // (E05-R16 fix-round F1): the tracker no longer swallows large
        // drifts into `null` — that path left the machine's own
        // forward-escalation rule (`drift > lostDriftBound` → `lost`)
        // dead in the real integration. The tracker now passes the
        // observation through with the actual drift value; the
        // downstream `CalibrationLossMachine` classifies drift == 0.10
        // as `degraded` (brief §6 matrix "rajta" cell).
        final observation = tracker.observe(
          anchor: anchor,
          observation: shiftedFeatureObservation(0.10, 0.0),
        );
        expect(
          observation,
          isNotNull,
          reason: 'tracker must pass the observation through to the machine',
        );
        expect(
          observation!.confidence.drift,
          closeTo(0.10, 1e-9),
          reason: 'actual computed drift, not swallowed',
        );
      },
    );

    test(
      'cell 3 — drift strictly above bound → tracker passes through; machine classifies as lost',
      () {
        // (E05-R16 fix-round F1): drift = 0.11 > lostDriftBound. The
        // tracker passes it through; `CalibrationLossMachine._nextState`
        // classifies it as `lost` (forward-escalation priority in EVERY
        // branch) in a SINGLE frame. The real integration is asserted
        // by `calibration_loss_machine_integration_test.dart`.
        final observation = tracker.observe(
          anchor: anchor,
          observation: shiftedFeatureObservation(0.11, 0.0),
        );
        expect(
          observation,
          isNotNull,
          reason:
              'tracker must pass the observation through to the machine '
              '— the machine owns the drift-bound classification',
        );
        expect(observation!.confidence.drift, closeTo(0.11, 1e-9));
      },
    );
  });

  group('EdgeGeometryTracker — proposed calibration shift', () {
    final tracker = EdgeGeometryTracker();
    final anchor = referenceManualAnchor();

    test('proposed calibration translates every anchor by the shift', () {
      final observation = tracker.observe(
        anchor: anchor,
        observation: shiftedFeatureObservation(0.03, 0.04),
      );
      expect(observation, isNotNull);
      // shift = (0.03, 0.04) → nutAnchor = (0.23, 0.54)
      expect(
        observation!.proposed.nutAnchor.x,
        closeTo(anchor.nutAnchor.x + 0.03, 1e-9),
      );
      expect(
        observation.proposed.nutAnchor.y,
        closeTo(anchor.nutAnchor.y + 0.04, 1e-9),
      );
      expect(
        observation.proposed.bridgeAnchor.x,
        closeTo(anchor.bridgeAnchor.x + 0.03, 1e-9),
      );
    });

    test('drift is the Euclidean magnitude of the shift', () {
      final observation = tracker.observe(
        anchor: anchor,
        observation: shiftedFeatureObservation(0.03, 0.04),
      );
      // sqrt(3² + 4²) = 5 — using normalized units, so 0.05
      final expectedDrift = math.sqrt(0.03 * 0.03 + 0.04 * 0.04);
      expect(observation!.confidence.drift, closeTo(expectedDrift, 1e-9));
    });

    test('confidence scales with feature count', () {
      // Single feature → 1/4 = 0.25 (below trackingConfidenceThreshold)
      final single = tracker.observe(
        anchor: anchor,
        observation: shiftedFeatureObservation(0.02, 0.0),
      );
      expect(single!.confidence.confidence, closeTo(0.25, 1e-9));

      // Four features at the same shift → confidence = 1.0
      final four = tracker.observe(
        anchor: anchor,
        observation: FrameObservation(
          detectedFeatures: [
            NormalizedPoint(0.20 + 0.02, 0.50),
            NormalizedPoint(0.80 + 0.02, 0.50),
            NormalizedPoint(0.85 + 0.02, 0.35),
            NormalizedPoint(0.85 + 0.02, 0.65),
          ],
        ),
      );
      expect(four!.confidence.confidence, closeTo(1.0, 1e-9));
    });
  });

  // The previous "drift-bound guard falsification probe" (with the
  // `_NoGuardEdgeGeometryTracker` parallel implementation) became
  // tautological after the F1 fix-round: the real tracker no longer
  // has a guard, by design — the load-bearing safety is the
  // `CalibrationLossMachine`'s forward-escalation rule, which is
  // now covered end-to-end by
  // `test/features/vision/application/calibration_loss_machine_integration_test.dart`.
}
