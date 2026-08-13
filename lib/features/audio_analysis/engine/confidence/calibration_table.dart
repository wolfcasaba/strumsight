import '../../domain/analysis_capability.dart';

/// Result of mapping a raw model score into publishable confidence.
final class CalibrationResult {
  const CalibrationResult({
    required this.confidence,
    required this.version,
    required this.source,
  });

  final double confidence;
  final String version;
  final ConfidenceCalibrationSource source;
}

/// One point of a monotonic, piecewise-linear measured calibration curve.
final class CalibrationPoint {
  CalibrationPoint({
    required this.rawScore,
    required this.calibratedConfidence,
  }) {
    if (!rawScore.isFinite || rawScore < 0 || rawScore > 1) {
      throw ArgumentError.value(
        rawScore,
        'rawScore',
        'must be finite and in [0, 1]',
      );
    }
    if (!calibratedConfidence.isFinite ||
        calibratedConfidence < 0 ||
        calibratedConfidence > 1) {
      throw ArgumentError.value(
        calibratedConfidence,
        'calibratedConfidence',
        'must be finite and in [0, 1]',
      );
    }
  }

  final double rawScore;
  final double calibratedConfidence;
}

/// Versioned confidence mapping.
///
/// E06-R19 deliberately shipped only [identityV1]: it makes the lack of a
/// measured calibration curve observable in Lab diagnostics instead of
/// mislabelling raw model output as a probability. E06-R29 adds
/// [CalibrationTable.measured] — a monotonic, piecewise-linear curve fitted
/// by `CalibrationFitter` — but only `CalibrationFitter` may construct one,
/// and only when the underlying data clears ADR 0249's 30-per-bin /
/// 300-total minimum; below that minimum the fitter itself returns
/// [identityV1] rather than a table built from too few observations.
final class CalibrationTable {
  const CalibrationTable.identityV1()
    : version = identityVersion,
      source = ConfidenceCalibrationSource.identity,
      _points = null;

  /// A measured, monotonic calibration curve. [points] must be sorted by
  /// ascending [CalibrationPoint.rawScore] with non-decreasing
  /// [CalibrationPoint.calibratedConfidence] — the contract a real,
  /// data-fitted curve always satisfies, and the identity table can never
  /// violate because it never takes this path.
  CalibrationTable.measured({
    required String version,
    required List<CalibrationPoint> points,
  }) : version = version,
       source = ConfidenceCalibrationSource.calibrated,
       _points = List<CalibrationPoint>.unmodifiable(points) {
    if (version == identityVersion) {
      throw ArgumentError.value(
        version,
        'version',
        'a measured table cannot claim the identity version',
      );
    }
    if (version.isEmpty) {
      throw ArgumentError.value(version, 'version', 'must not be empty');
    }
    if (points.length < 2) {
      throw ArgumentError.value(
        points,
        'points',
        'a measured curve needs at least two points',
      );
    }
    for (var i = 1; i < points.length; i++) {
      if (points[i].rawScore <= points[i - 1].rawScore) {
        throw ArgumentError.value(
          points,
          'points',
          'rawScore must be strictly increasing',
        );
      }
      if (points[i].calibratedConfidence < points[i - 1].calibratedConfidence) {
        throw ArgumentError.value(
          points,
          'points',
          'calibratedConfidence must be non-decreasing (monotonic)',
        );
      }
    }
  }

  static const String identityVersion = 'identity.v1';

  final String version;
  final ConfidenceCalibrationSource source;
  final List<CalibrationPoint>? _points;

  CalibrationResult calibrate(double rawScore) {
    if (!rawScore.isFinite || rawScore < 0 || rawScore > 1) {
      throw ArgumentError.value(
        rawScore,
        'rawScore',
        'must be finite and in [0, 1]',
      );
    }
    final points = _points;
    final confidence = points == null
        ? rawScore
        : _interpolate(points, rawScore);
    return CalibrationResult(
      confidence: confidence,
      version: version,
      source: source,
    );
  }

  double _interpolate(List<CalibrationPoint> points, double rawScore) {
    if (rawScore <= points.first.rawScore) {
      return points.first.calibratedConfidence;
    }
    if (rawScore >= points.last.rawScore) {
      return points.last.calibratedConfidence;
    }
    for (var i = 1; i < points.length; i++) {
      final upper = points[i];
      if (rawScore > upper.rawScore) continue;
      final lower = points[i - 1];
      final span = upper.rawScore - lower.rawScore;
      final t = span == 0 ? 0.0 : (rawScore - lower.rawScore) / span;
      return lower.calibratedConfidence +
          t * (upper.calibratedConfidence - lower.calibratedConfidence);
    }
    return points.last.calibratedConfidence;
  }
}
