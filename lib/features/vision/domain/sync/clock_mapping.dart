/// Immutable clock-mapping contract and calibration data models.
library;

import 'sync_quality.dart';
import 'vision_clock.dart';

/// The clock domains supported by the audio–vision boundary.
enum ClockDomain { vision, audio }

/// Separately measured contributors to observation latency.
final class LatencyComponents {
  LatencyComponents({
    required this.captureToInference,
    required this.inferenceToObservation,
  }) {
    if (captureToInference.isNegative || inferenceToObservation.isNegative) {
      throw ArgumentError('Latency components must not be negative.');
    }
  }

  final Duration captureToInference;
  final Duration inferenceToObservation;

  Duration get total => captureToInference + inferenceToObservation;
}

/// Maps a source timestamp onto a target clock on a shared session timeline.
///
/// The mapping contains no wall-clock object. Offset is expressed in
/// microseconds and drift in parts per million relative to the source time.
final class ClockMapping {
  ClockMapping({
    required this.source,
    required this.target,
    required this.offsetUs,
    required this.driftPpm,
    required this.confidence,
    this.maximumAbsoluteDriftPpm = defaultMaximumAbsoluteDriftPpm,
    this.syncQuality = SyncQuality.poor,
  }) {
    if (source == target) {
      throw ArgumentError.value(
        target,
        'target',
        'Source and target must differ.',
      );
    }
    if (!driftPpm.isFinite) {
      throw ArgumentError.value(driftPpm, 'driftPpm', 'Must be finite.');
    }
    if (confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence', 'Must be in [0, 1].');
    }
  }

  /// Maximum permitted drift before extrapolation becomes unsafe.
  static const double defaultMaximumAbsoluteDriftPpm = 500.0;

  final ClockDomain source;
  final ClockDomain target;
  final int offsetUs;
  final double driftPpm;
  final double confidence;
  final double maximumAbsoluteDriftPpm;
  final SyncQuality syncQuality;

  /// A drift beyond the configured bound is explicitly unusable.
  bool get isValid => driftPpm.abs() <= maximumAbsoluteDriftPpm;

  /// Applies offset and optional linear drift to [sourceTimestamp].
  SessionTimestamp map(SessionTimestamp sourceTimestamp) {
    if (!isValid) {
      throw ClockMappingException(
        'Drift $driftPpm ppm exceeds ±$maximumAbsoluteDriftPpm ppm.',
      );
    }
    final driftUs =
        (sourceTimestamp.microseconds *
                driftPpm /
                Duration.microsecondsPerSecond)
            .round();
    return SessionTimestamp(sourceTimestamp.microseconds + offsetUs + driftUs);
  }
}

/// One paired visual motion peak and audio onset used for calibration.
final class CalibrationSample {
  const CalibrationSample({
    required this.visionMotionPeak,
    required this.audioOnset,
    this.latency,
  });

  final SessionTimestamp visionMotionPeak;
  final SessionTimestamp audioOnset;
  final LatencyComponents? latency;

  /// Positive values mean the audio onset follows the vision motion peak.
  int get offsetUs => audioOnset.microseconds - visionMotionPeak.microseconds;
}

/// Deterministic policy used to reject bad calibration pairs.
final class CalibrationConfiguration {
  const CalibrationConfiguration({
    this.maximumOffsetDeviationUs = 20_000,
    this.minimumAcceptedSamples = 3,
    this.maximumAbsoluteDriftPpm = ClockMapping.defaultMaximumAbsoluteDriftPpm,
    this.qualityThresholds = const SyncQualityThresholds(),
  }) : assert(maximumOffsetDeviationUs > 0),
       assert(minimumAcceptedSamples >= 2),
       assert(maximumAbsoluteDriftPpm > 0);

  final int maximumOffsetDeviationUs;
  final int minimumAcceptedSamples;
  final double maximumAbsoluteDriftPpm;
  final SyncQualityThresholds qualityThresholds;
}

/// Audit data for a single calibration result.
final class CalibrationStatistics {
  const CalibrationStatistics({
    required this.totalSamples,
    required this.acceptedSamples,
    required this.rejectedSamples,
    required this.rootMeanSquareResidualUs,
    this.meanLatency,
  });

  final int totalSamples;
  final int acceptedSamples;
  final int rejectedSamples;
  final int rootMeanSquareResidualUs;
  final LatencyComponents? meanLatency;
}

/// A mapping plus the provenance needed to assess its quality.
final class CalibrationResult {
  const CalibrationResult({required this.mapping, required this.statistics});

  final ClockMapping mapping;
  final CalibrationStatistics statistics;
}
