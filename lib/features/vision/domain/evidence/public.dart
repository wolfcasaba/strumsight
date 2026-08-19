/// Narrow Vision evidence contract for the Practice Generator integration
/// (E07-R25, ADR 0193/[[L193]], ADR 0319, brief §0.0.1).
///
/// This nested `public.dart` deliberately exposes ONLY derived, raw-media-
/// free value objects — the cross-feature boundary Practice Generator may
/// import. The full `lib/features/vision/public.dart` barrel carries
/// landmark, geometry, provider, presentation and frame-level types that
/// must NEVER cross into practice-planning (ADR 0260 §1, ADR 0319 §Döntés,
/// §5.7, L190). Per ADR 0176 / `_isFeaturePublicBarrel`, any
/// `lib/features/<f>/.../public.dart` file is already a legal cross-feature
/// public surface — this file is that surface for derived vision evidence.
///
/// The shape:
///   * [VisionEvidence] / [ObservationState] — the fusion-window output.
///   * [EvidenceMetric] / [EvidenceMetricFamily] — the metric catalog
///     normalised for the fusion boundary; needed to key / dedupe the
///     evidence record.
///   * [EvidenceProvenance] / [EvidenceWindow] / [GeometrySource] —
///     versioned provenance + the half-open time-window tied to each
///     evidence record (no raw frames, no landmark coordinates).
///
/// What this contract DOES NOT export on purpose:
///   * `VisionObservation` — references `MetricObservation`,
///     `VisionFrameQuality`, `GeometryConfidence`, and `SyncQuality`, all of
///     which can carry (or index into) raw frame data.
///   * `ConfidenceComponents` / `ConfidenceModel` — implementation details
///     of how a vision record's confidence was assembled; the
///     `VisionEvidence.confidence` field is the only value Practice needs.
///   * landmark, pose, `camera_coordinate_space`/`NormalizedPoint`/
///     `NormalizedRect`, hand/pose provider, calibration or presentation
///     types — out of scope by intent.
///
/// The narrow contract is also the only path the E07-R25 vision adapter may
/// use to import from this feature. The well-formed-leak guard (the §6.1
/// A1 cell of the brief) asserts that no evidence record this file makes
/// available can carry `pcm`, `audio`, `wav`, `clip`, `samples`,
/// `filePath`, `frame`, `Uint8List`, `CameraImage`, `HandLandmarks`,
/// `PoseLandmarks`, `NormalizedPoint` or equivalent raw-media markers.
library;

export 'vision_evidence.dart' show VisionEvidence, ObservationState;
export 'vision_observation.dart' show EvidenceMetric, EvidenceMetricFamily;
export 'evidence_provenance.dart'
    show EvidenceProvenance, EvidenceWindow, GeometrySource;
