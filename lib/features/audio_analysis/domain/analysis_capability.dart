/// Analysis modules recognised by the V2 capability contract (SDD Ch7 §7.1).
enum AnalysisCapability {
  signalQuality,
  onsetTimeline,
  strumDirection,
  chordTimeline,
  beatGrid,
  tempoCurve,
  timingAccuracy,
  dynamicConsistency,
  monophonicPitch,
  intonation,
  noteStability,
  transitionSmoothness,
  targetAlignment,
  sectionComparison,
}

enum CapabilityStatus { available, degraded, unavailable, notApplicable }

/// Whether a published confidence originated in a real calibration table.
///
/// `identity` is intentionally explicit while E06-R29 has not yet produced a
/// measured calibration curve; a raw score must never masquerade as calibrated.
enum ConfidenceCalibrationSource { identity, calibrated }

enum CapabilityUnavailableReason {
  clipTooShort,
  insufficientEvents,
  inputTooNoisy,
  inputClipped,
  polyphonicInput,
  backingTrackDominant,
  confidenceTooLow,
  modelUnavailable,
  unsupportedFormat,
  unsupportedSampleRate,
  noReferenceTarget,
  cancelled,
  internalFailure,
}

/// Per-capability evidence and availability, never a document-wide boolean.
final class CapabilityReport {
  CapabilityReport({
    required this.capability,
    required this.status,
    required this.confidence,
    this.reason,
    this.calibrationVersion = 'identity.v1',
    this.calibrationSource = ConfidenceCalibrationSource.identity,
    Map<String, Object?> details = const <String, Object?>{},
  }) : details = Map<String, Object?>.unmodifiable(details) {
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw ArgumentError.value(
        confidence,
        'confidence',
        'must be finite and in [0, 1]',
      );
    }
    if (status == CapabilityStatus.unavailable && reason == null) {
      throw ArgumentError('Unavailable capability requires an explanation.');
    }
    if (calibrationVersion.isEmpty) {
      throw ArgumentError.value(
        calibrationVersion,
        'calibrationVersion',
        'must not be empty',
      );
    }
    if (calibrationSource == ConfidenceCalibrationSource.calibrated &&
        calibrationVersion == 'identity.v1') {
      throw ArgumentError(
        'The identity table cannot be labelled as calibrated.',
      );
    }
  }

  final AnalysisCapability capability;
  final CapabilityStatus status;
  final double confidence;
  final CapabilityUnavailableReason? reason;
  final String calibrationVersion;
  final ConfidenceCalibrationSource calibrationSource;
  final Map<String, Object?> details;
}
