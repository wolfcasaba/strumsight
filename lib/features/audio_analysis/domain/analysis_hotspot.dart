import 'analysis_metric_catalog.dart';

enum AnalysisHotspotKind { timing, rhythm, dynamics, harmony, pitch }

enum AnalysisHotspotSeverity { low, medium, high }

final class AnalysisHotspot {
  AnalysisHotspot({
    required this.id,
    required this.kind,
    required this.start,
    required this.end,
    required this.severity,
    required this.confidence,
    required List<String> metricIds,
    required List<String> evidenceIds,
  }) : metricIds = List<String>.unmodifiable(metricIds),
       evidenceIds = List<String>.unmodifiable(evidenceIds) {
    if (id.trim().isEmpty || start.isNegative || end < start) {
      throw ArgumentError('Invalid hotspot range.');
    }
    if (confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence');
    }
    if (this.metricIds.any((id) => !AnalysisMetricId.contains(id))) {
      throw ArgumentError('Hotspot metric IDs must be catalogued.');
    }
  }
  final String id;
  final AnalysisHotspotKind kind;
  final Duration start;
  final Duration end;
  final AnalysisHotspotSeverity severity;
  final double confidence;
  final List<String> metricIds;
  final List<String> evidenceIds;
}
