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
    Map<String, Object?> details = const <String, Object?>{},
  }) : details = Map<String, Object?>.unmodifiable(details) {
    if (confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence', 'must be in [0, 1]');
    }
    if (status == CapabilityStatus.unavailable && reason == null) {
      throw ArgumentError('Unavailable capability requires an explanation.');
    }
  }

  final AnalysisCapability capability;
  final CapabilityStatus status;
  final double confidence;
  final CapabilityUnavailableReason? reason;
  final Map<String, Object?> details;
}
