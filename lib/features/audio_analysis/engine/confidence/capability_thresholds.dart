/// Versioned provisional policy for Audio Analysis V2 confidence publication.
///
/// The values are deliberately named and live in one place until E06-R29
/// replaces them with thresholds measured against a calibration dataset.
final class CapabilityThresholds {
  CapabilityThresholds({
    this.version = provisionalVersion,
    this.minimumEventCount = 8,
    this.minimumDegradedConfidence = 0.4,
    this.minimumAvailableConfidence = 0.7,
    this.maximumClippedSampleRatio = 0.05,
    this.maximumNoiseFloorDbfs = -25,
    this.maximumSilentRatio = 0.95,
  }) {
    if (version.isEmpty ||
        minimumEventCount <= 0 ||
        !minimumDegradedConfidence.isFinite ||
        !minimumAvailableConfidence.isFinite ||
        minimumDegradedConfidence < 0 ||
        minimumAvailableConfidence > 1 ||
        minimumDegradedConfidence >= minimumAvailableConfidence ||
        !maximumClippedSampleRatio.isFinite ||
        maximumClippedSampleRatio < 0 ||
        maximumClippedSampleRatio > 1 ||
        !maximumNoiseFloorDbfs.isFinite ||
        !maximumSilentRatio.isFinite ||
        maximumSilentRatio < 0 ||
        maximumSilentRatio > 1) {
      throw ArgumentError('Capability thresholds must be finite and valid.');
    }
  }

  static const String provisionalVersion = 'provisional.v1';

  final String version;
  final int minimumEventCount;
  final double minimumDegradedConfidence;
  final double minimumAvailableConfidence;
  final double maximumClippedSampleRatio;
  final double maximumNoiseFloorDbfs;
  final double maximumSilentRatio;
}
