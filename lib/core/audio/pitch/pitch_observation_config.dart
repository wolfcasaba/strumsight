import 'package:meta/meta.dart';

/// Validated thresholds used while converting frames into observations.
@immutable
final class PitchObservationConfig {
  const PitchObservationConfig({
    this.minimumRms = 0.014,
    this.minimumClarity = 0.85,
    this.minimumFrequencyHz = 70,
    this.maximumFrequencyHz = 1320,
    this.stabilityCents = 35,
    this.stableFrames = 2,
    this.maximumObservationLatency = const Duration(milliseconds: 100),
  });

  final double minimumRms;
  final double minimumClarity;
  final double minimumFrequencyHz;
  final double maximumFrequencyHz;
  final double stabilityCents;
  final int stableFrames;
  final Duration maximumObservationLatency;

  bool get isValid =>
      minimumRms.isFinite &&
      minimumRms >= 0 &&
      minimumClarity.isFinite &&
      minimumClarity >= 0 &&
      minimumClarity <= 1 &&
      minimumFrequencyHz.isFinite &&
      minimumFrequencyHz > 0 &&
      maximumFrequencyHz.isFinite &&
      maximumFrequencyHz >= minimumFrequencyHz &&
      stabilityCents.isFinite &&
      stabilityCents >= 0 &&
      stableFrames > 0 &&
      maximumObservationLatency > Duration.zero;
}
