/// Deterministic audio–vision calibration flow.
library;

import 'dart:math' as math;

import '../domain/sync/clock_mapping.dart';
import '../domain/sync/vision_clock.dart';

/// Keeps the active mapping while preserving a snapshot for each emission.
final class SyncCalibrationController {
  SyncCalibrationController({
    this.configuration = const CalibrationConfiguration(),
  });

  final CalibrationConfiguration configuration;
  ClockMapping? _activeMapping;

  ClockMapping? get activeMapping => _activeMapping;

  /// Estimates and activates a new vision-to-audio mapping from [samples].
  ///
  /// Replacing the active mapping does not mutate any [MappedObservation]
  /// previously returned by [mapVisionObservation].
  CalibrationResult calibrate(
    Iterable<CalibrationSample> samples, {
    bool estimateDrift = false,
  }) {
    final allSamples = List<CalibrationSample>.unmodifiable(samples);
    if (allSamples.length < configuration.minimumAcceptedSamples) {
      throw ArgumentError.value(
        allSamples.length,
        'samples',
        'Needs at least ${configuration.minimumAcceptedSamples} samples.',
      );
    }

    final medianOffsetUs = _median(allSamples.map((sample) => sample.offsetUs));
    final accepted = <CalibrationSample>[
      for (final sample in allSamples)
        if ((sample.offsetUs - medianOffsetUs).abs() <=
            configuration.maximumOffsetDeviationUs)
          sample,
    ];
    if (accepted.length < configuration.minimumAcceptedSamples) {
      throw ClockMappingException(
        'Outlier rejection left ${accepted.length} accepted calibration samples.',
      );
    }

    final fit = estimateDrift
        ? _fitLinearDrift(accepted)
        : _LinearFit(
            offsetUs: _median(accepted.map((sample) => sample.offsetUs)),
          );
    final residuals = <int>[
      for (final sample in accepted)
        sample.offsetUs - _offsetAt(fit, sample.visionMotionPeak.microseconds),
    ];
    final rootMeanSquareResidualUs = _rootMeanSquare(residuals);
    final statistics = CalibrationStatistics(
      totalSamples: allSamples.length,
      acceptedSamples: accepted.length,
      rejectedSamples: allSamples.length - accepted.length,
      rootMeanSquareResidualUs: rootMeanSquareResidualUs,
      meanLatency: _meanLatency(accepted),
    );
    final result = CalibrationResult(
      mapping: ClockMapping(
        source: ClockDomain.vision,
        target: ClockDomain.audio,
        offsetUs: fit.offsetUs,
        driftPpm: fit.driftPpm,
        confidence: accepted.length / allSamples.length,
        maximumAbsoluteDriftPpm: configuration.maximumAbsoluteDriftPpm,
        syncQuality: configuration.qualityThresholds.forAbsoluteErrorUs(
          rootMeanSquareResidualUs,
        ),
      ),
      statistics: statistics,
    );
    _activeMapping = result.mapping;
    return result;
  }

  /// Maps one visual observation and retains the exact mapping provenance.
  MappedObservation mapVisionObservation(SessionTimestamp timestamp) {
    final mapping = _activeMapping;
    if (mapping == null) {
      throw StateError('A calibration mapping must be active before mapping.');
    }
    return MappedObservation(
      sourceTimestamp: timestamp,
      mappedTimestamp: mapping.map(timestamp),
      mapping: mapping,
    );
  }

  static _LinearFit _fitLinearDrift(List<CalibrationSample> samples) {
    final count = samples.length.toDouble();
    final meanX =
        samples.fold<double>(
          0,
          (sum, sample) => sum + sample.visionMotionPeak.microseconds,
        ) /
        count;
    final meanY =
        samples.fold<double>(0, (sum, sample) => sum + sample.offsetUs) / count;
    var covariance = 0.0;
    var variance = 0.0;
    for (final sample in samples) {
      final deltaX = sample.visionMotionPeak.microseconds - meanX;
      covariance += deltaX * (sample.offsetUs - meanY);
      variance += deltaX * deltaX;
    }
    if (variance == 0) {
      return _LinearFit(offsetUs: meanY.round());
    }
    final slope = covariance / variance;
    return _LinearFit(
      offsetUs: (meanY - slope * meanX).round(),
      driftPpm: slope * Duration.microsecondsPerSecond,
    );
  }

  static int _offsetAt(_LinearFit fit, int sourceUs) =>
      fit.offsetUs +
      (sourceUs * fit.driftPpm / Duration.microsecondsPerSecond).round();

  static int _median(Iterable<int> values) {
    final sorted = values.toList()..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return ((sorted[middle - 1] + sorted[middle]) / 2).round();
  }

  static int _rootMeanSquare(Iterable<int> values) {
    final list = values.toList(growable: false);
    final meanSquare =
        list.fold<double>(0, (sum, value) => sum + value * value) / list.length;
    return math.sqrt(meanSquare).round();
  }

  static LatencyComponents? _meanLatency(Iterable<CalibrationSample> samples) {
    final latencySamples = samples
        .map((sample) => sample.latency)
        .whereType<LatencyComponents>()
        .toList(growable: false);
    if (latencySamples.isEmpty) return null;
    Duration average(Iterable<Duration> values) {
      final totalUs = values.fold<int>(
        0,
        (sum, value) => sum + value.inMicroseconds,
      );
      return Duration(microseconds: totalUs ~/ latencySamples.length);
    }

    return LatencyComponents(
      captureToInference: average(
        latencySamples.map((latency) => latency.captureToInference),
      ),
      inferenceToObservation: average(
        latencySamples.map((latency) => latency.inferenceToObservation),
      ),
    );
  }
}

/// An already-issued observation with immutable mapping provenance.
final class MappedObservation {
  const MappedObservation({
    required this.sourceTimestamp,
    required this.mappedTimestamp,
    required this.mapping,
  });

  final SessionTimestamp sourceTimestamp;
  final SessionTimestamp mappedTimestamp;
  final ClockMapping mapping;
}

final class _LinearFit {
  const _LinearFit({required this.offsetUs, this.driftPpm = 0});

  final int offsetUs;
  final double driftPpm;
}
