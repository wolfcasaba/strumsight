/// Geometry tracker contract (SDD Ch6 §17.1, Kör 16).
///
/// A tracker a manual kalibrált gitárgeometria FAME-TO-FRAME frissítését
/// végzi (R10 anchorok + R15 homográfia kiegészítéséül). A contract
/// domain-szintű, pure Dart — nem függ Fluttertől, platform plugintől
/// vagy ML modelltől. A production adapterek (`edge_geometry_tracker.dart`)
/// adapter mintát követnek: a domain csak ezt a contractot ismeri, így a
/// R17 esetleges automatikus detektora (flag mögött) ugyanide
/// illeszkedhet, anélkül, hogy a CalibrationLossMachine bármit változna.
///
/// **Mit NEM csinál a tracker:**
///   - nem írja felül korlátlanul a manual anchorokat (ADR 0181 — a
///     drift-bound őr a `GeometryConfidence.isLost` + a
///     `CalibrationLossMachine` oldalán él, NEM itt; ez a contract a
///     trackertől FÜGGETLEN);
///   - nem ad gitárspecifikus negatív feedbacket (ADR 0179);
///   - nem dolgoz fel raw frame pixelt (az az adatréteghez tartozik).
///
/// **Mit csinál:** minden frame-re egy javasolt új `GuitarCalibration`-t
/// és egy `GeometryConfidence`-et ad (vagy `null`-t, ha nincs elég
/// evidencia). A downstream állapotgép ezt a párost olvassa.
library;

import '../../../../core/camera/camera_coordinate_space.dart';
import '../calibration/guitar_calibration.dart';
import 'geometry_confidence.dart';

/// A single frame's worth of feature observations feeding the tracker.
///
/// Pure data: a feature detector (edge, landmark, etc.) provides a list
/// of normalized points. The tracker pairs each with the closest manual
/// anchor point to estimate a per-frame translation.
///
/// The list MAY be empty — that signals "no features detected" and the
/// tracker is expected to return `null` from [GeometryTracker.observe].
final class FrameObservation {
  FrameObservation({required List<NormalizedPoint> detectedFeatures})
    : _detectedFeatures = List<NormalizedPoint>.unmodifiable(detectedFeatures);

  /// Normalized `[0, 1]×[0, 1]` feature points detected this frame.
  /// Order is irrelevant — the tracker uses a nearest-anchor pairing.
  List<NormalizedPoint> get detectedFeatures => _detectedFeatures;
  final List<NormalizedPoint> _detectedFeatures;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FrameObservation) return false;
    if (_detectedFeatures.length != other._detectedFeatures.length) {
      return false;
    }
    for (var i = 0; i < _detectedFeatures.length; i++) {
      if (_detectedFeatures[i] != other._detectedFeatures[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_detectedFeatures);
}

/// One tracker's output for a single frame: a proposed calibration +
/// the confidence that proposal earned.
///
/// The [proposed] calibration is built by applying the per-frame shift
/// to the manual anchor — it is NOT a replacement of the manual ground
/// truth, just a tracked refinement. Downstream the
/// [CalibrationLossMachine] decides whether the proposal is good enough
/// to attribute [GeometrySourceKind.tracked] or fall back to
/// [GeometrySourceKind.manual].
final class GeometryObservation {
  const GeometryObservation({required this.proposed, required this.confidence});

  /// The tracker-estimated calibration, derived from the manual anchor
  /// plus the per-frame shift.
  final GuitarCalibration proposed;

  /// Drift + confidence pair — see [GeometryConfidence].
  final GeometryConfidence confidence;
}

/// Contract every geometry tracker must satisfy.
///
/// The domain only knows this interface; concrete adapters live in
/// `data/`. The R17 automatic-detector would implement this same
/// interface, hidden behind a feature flag.
abstract interface class GeometryTracker {
  /// A short, human-readable identifier — surfaced in diagnostics and
  /// logged in [CalibrationLossMachine] summaries, NOT in user-visible
  /// UI.
  String get adapterId;

  /// Observe a single frame and produce a [GeometryObservation] (or
  /// `null` if the frame had insufficient evidence).
  ///
  /// The tracker MUST NOT mutate the [anchor]; the proposed calibration
  /// is a fresh value derived from the anchor + the per-frame shift.
  /// `null` return means "I have nothing to say this frame" — the loss
  /// machine treats that as a `manual` observation, NOT a failure
  /// (brief §5.4 capability-aware feedback: tracker absence ≠ negative).
  GeometryObservation? observe({
    required GuitarCalibration anchor,
    required FrameObservation observation,
  });
}
