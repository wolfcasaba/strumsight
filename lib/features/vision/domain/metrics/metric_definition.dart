import 'package:meta/meta.dart';

/// Capability required before a metric can be interpreted.
enum FrettingCapability { handTracking, guitarRelativeTracking }

enum FrettingMetricId {
  wristDeviationProxy,
  handToNeckDistance,
  chordChangeTravel,
  readyPositionTime,
  positionStability,
  fingerSpreadProxy,
}

@immutable
final class MetricDefinition {
  MetricDefinition({
    required this.id,
    required this.minimumVisibility,
    required this.window,
    required this.confidenceFormula,
    required this.requiredCapability,
  }) {
    // F6 fix (review E05-R18 F6 MINOR): unconditional throws instead of
    // asserts — Dart strips asserts in release builds, and the
    // `geometry_confidence.dart` precedent (R16 fix-round F2 MINOR)
    // shows the contract is release-load-bearing. The catalog is
    // compile-time fixed today, but a future runtime-supplied list must
    // also fail loudly.
    if (!(minimumVisibility.isFinite &&
        minimumVisibility >= 0 &&
        minimumVisibility <= 1)) {
      throw ArgumentError.value(
        minimumVisibility,
        'minimumVisibility',
        'Must be finite and in [0, 1].',
      );
    }
    if (window <= Duration.zero) {
      throw ArgumentError.value(
        window,
        'window',
        'Must be a positive Duration.',
      );
    }
    if (confidenceFormula.trim().isEmpty) {
      throw ArgumentError.value(
        confidenceFormula,
        'confidenceFormula',
        'Must be a non-empty string.',
      );
    }
  }

  final FrettingMetricId id;
  final double minimumVisibility;
  final Duration window;
  final String confidenceFormula;
  final FrettingCapability requiredCapability;

  bool get isValid =>
      minimumVisibility.isFinite &&
      minimumVisibility >= 0 &&
      minimumVisibility <= 1 &&
      window > Duration.zero &&
      confidenceFormula.trim().isNotEmpty;
}
