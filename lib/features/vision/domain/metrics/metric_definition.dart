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
  const MetricDefinition({
    required this.id,
    required this.minimumVisibility,
    required this.window,
    required this.confidenceFormula,
    required this.requiredCapability,
  }) : assert(minimumVisibility >= 0 && minimumVisibility <= 1),
       assert(window > Duration.zero),
       assert(confidenceFormula != '');

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
