/// Calibration loss state machine (SDD Ch6 §17.1, Kör 16).
///
/// A kézzel kalibrált gitárgeometria (R10) rövid távú követésének
/// állapotgépe. Három állapota van:
///
///   - `tracking`  — a tracker és a manual anchor megegyezik a
///                  drift-bound alatt; a rendszer gitárspecifikus
///                  metrikákat adhat (ADR 0179 capability-aware
///                  feedback);
///   - `degraded`  — a drift a tolerancián belül van, de a
///                  `degradedDriftBound` felett; a rendszer MINDIG
///                  manual fallback üzemmódban van (a javasolt
///                  tracker-anchor nem bízható);
///   - `lost`      — a drift a `lostDriftBound` fölött; a rendszer
///                  `notObservable` + Recalibrate cue-t ad (ADR 0179,
///                  brief §5.2 — NEM ad gitárspecifikus negatív
///                  feedbacket).
///
/// **Hiszterézis.** A `tracking → degraded → lost` átmenet forward
/// küszöbe (`degradedDriftBound = 0.05`, `lostDriftBound = 0.10`)
/// és a visszatérés küszöbe (`recoveryDriftBound = 0.04`) között
/// 0.06-os ablak van — ez a gépi őr a drift-határ körüli
/// villogás ellen. A §6 acceptance második cellája méri: 17 elemes
/// oszcilláló sequence-re a state-váltások száma `≤ 2`.
///
/// **Source-nyilvántartás.** A `geometrySource` mező a manual anchor
/// és a tracker megbízhatóságát jelzi — `manual`, ha a tracker az
/// utolsó sikeres frissítés óta nem érte el a
/// [trackingConfidenceThreshold]-et, `tracked`, ha elérte. Ez a
/// `session summary` (későbbi R22) egyik kulcsmezője.
///
/// **Önálló állapotgép, NEM a R10-es enum bővítése.** A R10
/// `CalibrationInvalidationReason` öt értéke a `CalibrationValidity`
/// saját felelőssége; ez a gép külön, önálló contract (R4, brief
/// §0.0 — a fájl nincs az `allowed_paths`-on, szándékosan).
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../domain/calibration/guitar_calibration.dart';
import '../domain/geometry/geometry_confidence.dart';
import '../domain/geometry/geometry_tracker.dart';

/// A calibration-loss state machine state.
enum CalibrationLossState {
  /// A tracker driftje a `degradedDriftBound` alatt van.
  tracking,

  /// A tracker driftje `degradedDriftBound` felett, de `lostDriftBound`
  /// alatt. A rendszer manual fallback üzemmódban van.
  degraded,

  /// A tracker driftje `lostDriftBound` felett VAGY a tracker `null`-t
  /// adott vissza elégszer. A rendszer `notObservable` + Recalibrate
  /// cue-t ad (ADR 0179 capability-aware feedback).
  lost,
}

/// The source of the geometry the machine currently considers active.
enum GeometrySourceKind {
  /// A R10 manual anchor az igazság — a tracker nem ért el
  /// [trackingConfidenceThreshold]-et, vagy egyáltalán nem adott
  /// megbízható jelet. Ez a Kör 16 default értéke (ADR 0181: a
  /// gitárgeometria production útja a kézi kalibráció).
  manual,

  /// A tracker elérte a [trackingConfidenceThreshold]-et az utolsó
  /// sikeres frissítéskor. A downstream consumer (R22 session summary)
  /// ebből tudja, hogy a mért drift a tracked ágra jegyezhető.
  tracked,
}

/// Pure state machine — owns the drift and source history; downstream
/// consumers read the public accessors after each [update] call.
///
/// Construction is O(1). [update] is O(1) per frame. The machine is
/// stateless across sessions: a fresh instance starts at `tracking`
/// with the manual anchor — this matches the brief §13.4 "kalibráció
/// elmozdul a tolerancián túl" reset-szemantikáját.
final class CalibrationLossMachine {
  CalibrationLossMachine({required GuitarCalibration initialAnchor})
    : _initialAnchor = initialAnchor,
      _state = CalibrationLossState.tracking,
      _geometrySource = GeometrySourceKind.manual,
      _currentDrift = 0,
      _maxDrift = 0,
      _consecutiveLostFrames = 0;

  /// The manual anchor this machine guards. Kept for diagnostics and
  /// to construct the [CalibrationLossSummary.geometrySource].
  final GuitarCalibration _initialAnchor;

  CalibrationLossState _state;
  GeometrySourceKind _geometrySource;

  /// The drift the machine is currently evaluating against its
  /// thresholds. Held across frames so a missing observation does not
  /// "reset" the loss evaluation.
  double _currentDrift;

  /// Peak drift observed during this session — surfaced in the
  /// session summary (brief §5.4 — "a mért maximális drift" a machine
  /// saját exportja, ld. §0.0 R5).
  double _maxDrift;

  /// Number of consecutive frames with `lost` state. Used to
  /// disambiguate "tracker said `lost`" from "tracker said `null`
  /// (no features)": the brief §13.4 "session közben tracking
  /// confidence tartósan alacsony" a CONSECUTIVE formát kéri.
  int _consecutiveLostFrames;

  /// Number of consecutive frames before a `null` tracker result
  /// demotes the state to `lost`. Calibrated against the device
  /// matrix PENDING measurement (brief §7) — a conservative 5 frames
  /// (~0.2s @ 25 FPS hand-tracking cadence) is enough to swallow a
  /// transient feature-detector miss without false-positive loss.
  static const int noObservationLostThreshold = 5;

  // --- Public state accessors ------------------------------------------

  /// Current state of the loss machine.
  CalibrationLossState get state => _state;

  /// Source of the geometry the machine considers active right now.
  GeometrySourceKind get geometrySource => _geometrySource;

  /// Drift the machine evaluated in its last [update] call. Held across
  /// frames so a missing observation does not reset the loss
  /// evaluation.
  double get currentDrift => _currentDrift;

  /// Peak drift observed during this session. The session-summary
  /// field (brief §5.4 — "a mért maximális drift").
  double get maxDrift => _maxDrift;

  /// `true` when the state is `lost`. Downstream consumers MUST gate
  /// their negative guitar-relative insight path on this flag
  /// (ADR 0179 capability-aware feedback, brief §5.2 — feedback-tiltás).
  bool get feedbackSuppressed => _state == CalibrationLossState.lost;

  /// `true` when the state is `lost`. The Recalibrate cue (R24 UI)
  /// listens to this flag.
  bool get recalibrateRequested => _state == CalibrationLossState.lost;

  /// Snapshot of the summary fields the brief §5.4 + §6 utolsó cella
  /// elvár: a machine saját kimenete a `geometrySource` + a mért
  /// `maxDrift`. A `VisionSessionResult`-ba (R22) fordítás egy későbbi
  /// kör felelőssége.
  CalibrationLossSummary get summary => CalibrationLossSummary(
    geometrySource: _geometrySource,
    maxDrift: _maxDrift,
    state: _state,
  );

  // --- State transitions -----------------------------------------------

  /// Apply one frame's tracker output to the machine.
  ///
  /// Pass `null` for frames where the tracker had nothing to say (no
  /// features detected, or refused to produce an observation whose
  /// drift exceeded [lostDriftBound]). A streak of `null` results
  /// promotes the state to `lost` after
  /// [noObservationLostThreshold] consecutive frames.
  void update(GeometryObservation? observation) {
    if (observation == null) {
      _consecutiveLostFrames++;
      if (_consecutiveLostFrames >= noObservationLostThreshold &&
          _state != CalibrationLossState.lost) {
        _state = CalibrationLossState.lost;
      }
      return;
    }

    _consecutiveLostFrames = 0;
    _currentDrift = observation.confidence.drift;
    _maxDrift = math.max(_maxDrift, _currentDrift);

    // Geometry source attribution — manual until the tracker earns
    // `tracked` by hitting the confidence threshold.
    if (observation.confidence.isTracked) {
      _geometrySource = GeometrySourceKind.tracked;
    } else {
      _geometrySource = GeometrySourceKind.manual;
    }

    _state = _nextState(_currentDrift, _state);
  }

  /// Reset the machine to its initial state — used at the start of a
  /// new session or after the user manually re-calibrates.
  void reset() {
    _state = CalibrationLossState.tracking;
    _geometrySource = GeometrySourceKind.manual;
    _currentDrift = 0;
    _maxDrift = 0;
    _consecutiveLostFrames = 0;
  }

  /// The initial manual anchor the machine guards. Read-only — exposed
  /// for diagnostics and the session-summary provenance field.
  GuitarCalibration get initialAnchor => _initialAnchor;

  /// Pure-function state-transition table. Encoded as a method so the
  /// thresholds and the `prev → next` logic are testable in isolation.
  ///
  /// Forward path:
  ///   tracking → degraded when drift `>=` degradedDriftBound (0.05)
  ///   degraded → lost    when drift `>`  lostDriftBound (0.10)
  ///
  /// Reverse path (stricter, hysteresis):
  ///   lost     → tracking when drift `<=` recoveryDriftBound (0.04)
  ///   degraded → tracking when drift `<=` recoveryDriftBound (0.04)
  ///
  /// The `>=` on the `tracking → degraded` boundary keeps the
  /// "exactly on the drift-bound" matrix cell deterministic
  /// (brief §6 first cell: `tracking/degraded`).
  @visibleForTesting
  static CalibrationLossState stateTransition({
    required double drift,
    required CalibrationLossState previous,
  }) =>
      _nextState(drift, previous);

  static CalibrationLossState _nextState(
    double drift,
    CalibrationLossState previous,
  ) {
    if (previous == CalibrationLossState.lost) {
      return drift <= recoveryDriftBound
          ? CalibrationLossState.tracking
          : CalibrationLossState.lost;
    }
    if (drift > lostDriftBound) return CalibrationLossState.lost;
    if (drift >= degradedDriftBound) return CalibrationLossState.degraded;
    return CalibrationLossState.tracking;
  }
}

/// The brief §6 utolsó cella — "a summary tartalmazza a geometry-source-t
/// és a maximális driftet". This is the [CalibrationLossMachine] SAJÁT
/// kimenete (brief §0.0 R5 — a `VisionSessionResult` típust egy későbbi
/// R22-es kör fordítja majd a tényleges session-summary típusba).
final class CalibrationLossSummary {
  const CalibrationLossSummary({
    required this.geometrySource,
    required this.maxDrift,
    required this.state,
  });

  final GeometrySourceKind geometrySource;
  final double maxDrift;
  final CalibrationLossState state;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalibrationLossSummary &&
          other.geometrySource == geometrySource &&
          other.maxDrift == maxDrift &&
          other.state == state;

  @override
  int get hashCode => Object.hash(geometrySource, maxDrift, state);
}

/// Minimal `@visibleForTesting` annotation shim removed — using
/// `package:meta/meta.dart` directly (already imported at the top).
