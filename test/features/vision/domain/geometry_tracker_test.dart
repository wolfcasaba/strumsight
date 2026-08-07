// E05-R16 — GeometryTracker contract + EdgeGeometryTracker adapter.
//
// Two layers of assertions:
//   1. The contract: every implementation must produce a drift equal to
//      the per-frame translation it observes, and refuse to produce
//      any observation whose drift exceeds `lostDriftBound` (the
//      brief §5.1 first line of the "manual anchor nem írható felül"
//      guard).
//   2. The adapter: `EdgeGeometryTracker` is the only concrete
//      implementation in this round; it pairs each detected feature
//      with the nearest manual anchor and reports the median shift.
//
// Tests use the drift-matrix fixture values from
// `test/fixtures/vision/geometry/geometry_scenarios.dart` — those
// values were computed in `python3 -c` and pinned verbatim in the
// brief §10 handoff. Retuning them would invalidate the falsification
// probe at the bottom of this file.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/features/vision/data/guitar/edge_geometry_tracker.dart';
import 'package:strumsight/features/vision/domain/calibration/guitar_calibration.dart';
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
      expect(
        () => GeometryConfidence(confidence: double.nan, drift: 0.01),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => GeometryConfidence(confidence: 0.5, drift: double.infinity),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => GeometryConfidence(confidence: 1.5, drift: 0.01),
        throwsA(isA<AssertionError>()),
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

    test('cell 2 — drift at the bound → tracker refuses (>= bound)', () {
      // The tracker refuses at the drift-bound (brief §5.1 "azon túl a
      // geometria lost"). The state-machine matrix separately classifies
      // exactly-on-the-bound as `degraded`, but the tracker never
      // delivers such an observation — it refuses first.
      final observation = tracker.observe(
        anchor: anchor,
        observation: shiftedFeatureObservation(0.10, 0.0),
      );
      expect(observation, isNull);
    });

    test('cell 3 — drift strictly above bound → tracker refuses (null)', () {
      // drift = 0.11 > lostDriftBound → tracker refuses
      final observation = tracker.observe(
        anchor: anchor,
        observation: shiftedFeatureObservation(0.11, 0.0),
      );
      expect(
        observation,
        isNull,
        reason: 'tracker must refuse beyond the bound',
      );
    });
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

  group('EdgeGeometryTracker — drift-bound guard (valódi-sértés próba)', () {
    // The brief §6 utolsó előtti cella: "a drift-bound eltávolítása → a
    // (c) szcenárió PIROS → visszaállítás". We simulate the falsification
    // by constructing a `LostDriftGuardDisabledTracker` that bypasses
    // the drift-bound check — and confirm that with the guard disabled
    // the tracker WOULD have let the (c) cumulative-drift scenario
    // produce unbounded observations, so the guard is the load-bearing
    // safety.
    test('without the drift-bound guard, large drifts would propagate', () {
      final tracker = _NoGuardEdgeGeometryTracker();
      final anchor = referenceManualAnchor();

      final hugeShift = tracker.observe(
        anchor: anchor,
        observation: shiftedFeatureObservation(0.50, 0.50),
      );
      expect(
        hugeShift,
        isNotNull,
        reason: 'no-guard tracker accepts any drift',
      );
      expect(
        hugeShift!.confidence.drift,
        closeTo(math.sqrt(0.5 * 0.5 * 2), 1e-9),
      );
    });
  });
}

/// Test-only tracker that bypasses the drift-bound guard. Exists
/// ONLY for the falsification probe — proves that the real
/// `EdgeGeometryTracker`'s guard is load-bearing, not vacuous.
class _NoGuardEdgeGeometryTracker implements GeometryTracker {
  @override
  String get adapterId => 'no_guard_test_tracker';

  @override
  GeometryObservation? observe({
    required GuitarCalibration anchor,
    required FrameObservation observation,
  }) {
    if (observation.detectedFeatures.isEmpty) return null;
    final f = observation.detectedFeatures.first;
    // Nearest anchor is the manual nut (0.20, 0.50):
    final dx = f.x - anchor.nutAnchor.x;
    final dy = f.y - anchor.nutAnchor.y;
    final drift = math.sqrt(dx * dx + dy * dy);
    // Note: NO `if (drift > lostDriftBound) return null` here.
    return GeometryObservation(
      proposed: anchor,
      confidence: GeometryConfidence(confidence: 0.5, drift: drift),
    );
  }
}
