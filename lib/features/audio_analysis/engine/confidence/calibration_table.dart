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

/// Versioned confidence mapping.
///
/// E06-R19 deliberately ships only [identityV1]. It makes the lack of a
/// measured calibration curve observable in Lab diagnostics instead of
/// mislabelling raw model output as a probability. E06-R29 will add a
/// measured, monotonic table under a new version.
final class CalibrationTable {
  const CalibrationTable.identityV1()
    : version = identityVersion,
      source = ConfidenceCalibrationSource.identity;

  static const String identityVersion = 'identity.v1';

  final String version;
  final ConfidenceCalibrationSource source;

  CalibrationResult calibrate(double rawScore) {
    if (!rawScore.isFinite || rawScore < 0 || rawScore > 1) {
      throw ArgumentError.value(
        rawScore,
        'rawScore',
        'must be finite and in [0, 1]',
      );
    }
    return CalibrationResult(
      confidence: rawScore,
      version: version,
      source: source,
    );
  }
}
