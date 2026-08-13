/// Reliability-diagram binning, Expected Calibration Error, and the
/// data-sufficiency gate for the V2 [CalibrationTable] (E06-R29, ADR 0249).
library;

import '../../domain/evaluation/evaluation_report.dart';
import '../../domain/evaluation/ground_truth.dart';
import '../../engine/confidence/calibration_table.dart';

/// One reliability-diagram bin: every [ConfidenceObservation] whose
/// `rawScore` falls in `[lowerBound, upperBound)` (the last bin is closed on
/// both ends, at `rawScore == 1.0`).
final class CalibrationBin {
  CalibrationBin({
    required this.lowerBound,
    required this.upperBound,
    required List<ConfidenceObservation> observations,
  }) : observations = List<ConfidenceObservation>.unmodifiable(observations);

  final double lowerBound;
  final double upperBound;
  final List<ConfidenceObservation> observations;

  int get count => observations.length;

  double? get meanConfidence {
    if (observations.isEmpty) return null;
    final sum = observations.fold<double>(0, (acc, o) => acc + o.rawScore);
    return sum / observations.length;
  }

  double? get empiricalAccuracy {
    if (observations.isEmpty) return null;
    final correct = observations.where((o) => o.correct).length;
    return correct / observations.length;
  }

  CalibrationBinReport toReport() => CalibrationBinReport(
    lowerBound: lowerBound,
    upperBound: upperBound,
    observationCount: count,
    meanConfidence: meanConfidence,
    empiricalAccuracy: empiricalAccuracy,
  );
}

/// The result of fitting a calibration curve to a set of labelled
/// confidence observations.
final class CalibrationFitResult {
  const CalibrationFitResult({
    required this.table,
    required this.expectedCalibrationError,
    required this.insufficientData,
    required this.bins,
    required this.totalObservations,
  });

  final CalibrationTable table;
  final double? expectedCalibrationError;
  final bool insufficientData;
  final List<CalibrationBin> bins;
  final int totalObservations;

  ConfidenceCalibrationMetrics toMetrics() => ConfidenceCalibrationMetrics(
    expectedCalibrationError: expectedCalibrationError,
    insufficientData: insufficientData,
    observationCount: totalObservations,
    tableVersion: table.version,
    bins: <CalibrationBinReport>[for (final bin in bins) bin.toReport()],
  );
}

/// Bins labelled confidence observations, computes their Expected
/// Calibration Error, and decides — per ADR 0249 §Döntés 4 — whether there
/// is enough data to ship a measured [CalibrationTable].
///
/// The minimums are both inclusive: a bin with exactly
/// [minimumBinObservations] observations, in a manifest with exactly
/// [minimumTotalObservations] observations overall, still fits. One fewer of
/// either and the fitter returns [CalibrationTable.identityV1] and marks the
/// result `insufficientData`.
final class CalibrationFitter {
  const CalibrationFitter({
    this.binCount = 10,
    this.minimumBinObservations = 30,
    this.minimumTotalObservations = 300,
    this.measuredVersion = 'measured.v1',
  });

  final int binCount;
  final int minimumBinObservations;
  final int minimumTotalObservations;
  final String measuredVersion;

  CalibrationFitResult fit(List<ConfidenceObservation> observations) {
    final bins = _bucket(observations);
    final total = observations.length;
    final ece = _computeEce(bins, total);

    final sufficientTotal = total >= minimumTotalObservations;
    final nonEmptyBins = bins.where((bin) => bin.count > 0);
    final sufficientBins =
        nonEmptyBins.isNotEmpty &&
        nonEmptyBins.every((bin) => bin.count >= minimumBinObservations);
    final insufficientData = !(sufficientTotal && sufficientBins);

    final table = insufficientData
        ? const CalibrationTable.identityV1()
        : CalibrationTable.measured(
            version: measuredVersion,
            points: _monotonicPoints(bins),
          );

    return CalibrationFitResult(
      table: table,
      expectedCalibrationError: ece,
      insufficientData: insufficientData,
      bins: bins,
      totalObservations: total,
    );
  }

  List<CalibrationBin> _bucket(List<ConfidenceObservation> observations) {
    final buckets = List<List<ConfidenceObservation>>.generate(
      binCount,
      (_) => <ConfidenceObservation>[],
    );
    for (final observation in observations) {
      final index = _binIndexFor(observation.rawScore);
      buckets[index].add(observation);
    }
    return <CalibrationBin>[
      for (var i = 0; i < binCount; i++)
        CalibrationBin(
          lowerBound: i / binCount,
          upperBound: (i + 1) / binCount,
          observations: buckets[i],
        ),
    ];
  }

  int _binIndexFor(double rawScore) {
    final index = (rawScore * binCount).floor();
    if (index >= binCount) return binCount - 1;
    if (index < 0) return 0;
    return index;
  }

  /// Weighted mean absolute gap between each non-empty bin's mean predicted
  /// confidence and its empirical accuracy: `sum(|bin| / n * |conf - acc|)`.
  double? _computeEce(List<CalibrationBin> bins, int total) {
    if (total == 0) return null;
    var ece = 0.0;
    for (final bin in bins) {
      if (bin.count == 0) continue;
      final weight = bin.count / total;
      ece += weight * (bin.meanConfidence! - bin.empiricalAccuracy!).abs();
    }
    return ece;
  }

  /// Turns non-empty bins into a monotonic curve: each bin's mean predicted
  /// confidence maps to its empirical accuracy, with a running maximum
  /// enforcing non-decreasing output (pool-adjacent-violators-style clamp).
  List<CalibrationPoint> _monotonicPoints(List<CalibrationBin> bins) {
    final raw = <CalibrationPoint>[
      for (final bin in bins)
        if (bin.count > 0)
          CalibrationPoint(
            rawScore: bin.meanConfidence!,
            calibratedConfidence: bin.empiricalAccuracy!,
          ),
    ]..sort((a, b) => a.rawScore.compareTo(b.rawScore));

    final points = <CalibrationPoint>[];
    var runningMax = 0.0;
    for (final point in raw) {
      final calibrated = point.calibratedConfidence < runningMax
          ? runningMax
          : point.calibratedConfidence;
      runningMax = calibrated;
      if (points.isNotEmpty && points.last.rawScore == point.rawScore) {
        points.removeLast();
      }
      points.add(
        CalibrationPoint(
          rawScore: point.rawScore,
          calibratedConfidence: calibrated,
        ),
      );
    }
    if (points.length < 2) {
      // Degenerate spread (e.g. every bin shares one mean confidence): pad
      // with the domain endpoints so CalibrationTable.measured's two-point
      // minimum is met without breaking monotonicity.
      final only = points.isEmpty
          ? CalibrationPoint(rawScore: 0.5, calibratedConfidence: 0.5)
          : points.single;
      final padded = <CalibrationPoint>[];
      if (only.rawScore > 0.0) {
        padded.add(
          CalibrationPoint(
            rawScore: 0.0,
            calibratedConfidence: only.calibratedConfidence,
          ),
        );
      }
      padded.add(only);
      if (only.rawScore < 1.0) {
        padded.add(
          CalibrationPoint(
            rawScore: 1.0,
            calibratedConfidence: only.calibratedConfidence,
          ),
        );
      }
      return padded;
    }
    return points;
  }
}
