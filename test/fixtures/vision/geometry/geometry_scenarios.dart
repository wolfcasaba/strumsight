// E05-R16 — Fixture scenarios for the geometry-tracking acceptance matrix.
//
// Each scenario is a pure-data helper that constructs:
//   - the manual anchor (`GuitarCalibration`),
//   - the frame observations (`List<FrameObservation>`) with known
//     per-frame translation shifts,
//
// so the tracker + loss-machine tests can assert exact drift values
// without re-deriving them inside each test case. The drift values
// were computed in the brief §10 handoff via `python3 -c` and pinned
// here verbatim — DO NOT retune these thresholds to "make the tests
// pass" (brief §6 "Valódi-sértés próba": a drift-bound eltávolítása
// → a (c) szcenárió PIROS).
library;

import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/features/vision/domain/calibration/guitar_calibration.dart';
import 'package:strumsight/features/vision/domain/geometry/geometry_tracker.dart';

/// Reference manual calibration shared by every scenario. The polygon
/// is a simple rectangular neck (`0.15..0.85 × 0.35..0.65`) — wide
/// enough that a small feature-detector jitter produces a non-zero
/// shift, narrow enough that a large shift can push the polygon out
/// of the visible frame.
GuitarCalibration referenceManualAnchor({DateTime? createdAt}) {
  return GuitarCalibration(
    nutAnchor: const NormalizedPoint(0.20, 0.50),
    bridgeAnchor: const NormalizedPoint(0.80, 0.50),
    neckPolygon: const [
      NormalizedPoint(0.15, 0.35),
      NormalizedPoint(0.85, 0.35),
      NormalizedPoint(0.85, 0.65),
      NormalizedPoint(0.15, 0.65),
    ],
    createdAt: createdAt ?? DateTime.utc(2026, 8, 7),
  );
}

/// Frame observation carrying a single feature point shifted from the
/// manual nut anchor by `dx, dy`. The shift is the only signal the
/// EdgeGeometryTracker reads — for a single-feature observation, the
/// nearest anchor is the nut and the shift is the median (and only)
/// translation.
FrameObservation shiftedFeatureObservation(double dx, double dy) {
  return FrameObservation(
    detectedFeatures: [NormalizedPoint(0.20 + dx, 0.50 + dy)],
  );
}

/// Drift-matrix fixture: three single-frame drift values picked so the
/// `python3` computation in brief §10 is reproducible.
///
///   - drift=0.04 — well below `lostDriftBound` (0.10) AND below
///                  `degradedDriftBound` (0.05). The matrix's "below"
///                  cell → `tracking`.
///   - drift=0.10 — exactly on `lostDriftBound`. The matrix's "on the
///                  bound" cell → `degraded`.
///   - drift=0.11 — just above `lostDriftBound`. The matrix's "above"
///                  cell → `lost`.
const double driftMatrixBelow = 0.04;
const double driftMatrixOnBound = 0.10;
const double driftMatrixAbove = 0.11;

/// Hysteresis-fixture: a 17-element oscillating sequence in the
/// `(degradedDriftBound, lostDriftBound)` band. The brief §6 second
/// acceptance cell asserts the loss machine takes `≤ 2` state
/// transitions on this input — a no-hysteresis reference would take
/// the same 1 transition here, but a sequence AROUND the lost-bound
/// would oscillate freely without hysteresis.
const List<double> hysteresisOscillatingSequence = [
  0.07, 0.08, 0.06, 0.09, 0.07, 0.08, 0.06, 0.09,
  0.07, 0.08, 0.06, 0.09, 0.07, 0.08, 0.06, 0.09,
  0.07,
];

/// Scenario (a) — small camera bump: a single-frame drift well below
/// the degraded threshold. The expected state is `tracking`; the
/// expected source is `tracked` if the tracker is confident enough,
/// otherwise `manual`.
const double scenarioSmallCameraBumpDrift = 0.02;

/// Scenario (b) — large movement: a single-frame drift well above
/// the lost threshold. The expected state is `lost`; the source is
/// `tracked` if the tracker still produced an observation (i.e. the
/// tracker refused to produce one and the machine sees `null`).
const double scenarioLargeMovementDrift = 0.20;

/// Scenario (c) — slow cumulative drift: per-frame increments of
/// `0.01` that walk across the degraded → lost boundary. The first
/// frame where the drift exceeds `lostDriftBound` (0.10) is the 11th
/// (drift = 0.11). The cumulative-drift test asserts the state is
/// `tracking` until step 5 (drift = 0.05 → degraded), then `degraded`
/// until step 11 (drift = 0.11 → lost), then `lost`.
///
/// Why `0.01` and not `0.005` — the `python3` reference sweep showed
/// that `0.005` accumulates to `0.10000000000000002` at step 20,
/// which is `> 0.10` only by floating-point noise. `0.01` is exact
/// at the boundary so the test reads as the brief intends.
const double scenarioCumulativeDriftPerFrame = 0.01;
const int scenarioCumulativeDriftFirstLostStep = 11;
const int scenarioCumulativeDriftFirstDegradedStep = 5;
