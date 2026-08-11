import 'analysis_capability.dart';
import 'analysis_hotspot.dart';
import 'analysis_input_summary.dart';
import 'analysis_insight.dart';
import 'analysis_metric.dart';
import 'analysis_mode.dart';
import 'analysis_provenance.dart';
import 'analysis_timeline.dart';
import 'analysis_warning.dart';
import 'signal_quality_report.dart';

const int analysisDocumentSchemaVersion = 1;

enum AnalysisCompletionStatus { complete, degraded, cancelled, failed }

final class AnalysisCompletion {
  AnalysisCompletion({required this.status, this.failureCode}) {
    if (status == AnalysisCompletionStatus.failed &&
        (failureCode == null || failureCode!.trim().isEmpty)) {
      throw ArgumentError('A failed analysis requires a failure code.');
    }
  }
  final AnalysisCompletionStatus status;
  final String? failureCode;
}

/// Immutable, versioned V2 analysis document (ADR 0215).
final class AnalysisDocument {
  AnalysisDocument({
    required this.id,
    required this.schemaVersion,
    required this.createdAt,
    required this.mode,
    required this.input,
    required this.provenance,
    required this.signalQuality,
    required List<CapabilityReport> capabilities,
    required this.timeline,
    required List<AnalysisMetricResult> metrics,
    required List<AnalysisHotspot> hotspots,
    required List<AnalysisInsight> insights,
    required List<AnalysisWarning> warnings,
    required this.completion,
  }) : capabilities = List<CapabilityReport>.unmodifiable(capabilities),
       metrics = List<AnalysisMetricResult>.unmodifiable(metrics),
       hotspots = List<AnalysisHotspot>.unmodifiable(hotspots),
       insights = List<AnalysisInsight>.unmodifiable(insights),
       warnings = List<AnalysisWarning>.unmodifiable(warnings) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    if (schemaVersion < analysisDocumentSchemaVersion) {
      throw ArgumentError.value(schemaVersion, 'schemaVersion');
    }
    if (this.metrics.map((metric) => metric.id).toSet().length !=
        this.metrics.length) {
      throw ArgumentError('Metric IDs must be unique within a document.');
    }
  }
  final String id;
  final int schemaVersion;
  final DateTime createdAt;
  final AnalysisMode mode;
  final AnalysisInputSummary input;
  final AnalysisProvenance provenance;
  final SignalQualityReport signalQuality;
  final List<CapabilityReport> capabilities;
  final AnalysisTimeline timeline;
  final List<AnalysisMetricResult> metrics;
  final List<AnalysisHotspot> hotspots;
  final List<AnalysisInsight> insights;
  final List<AnalysisWarning> warnings;
  final AnalysisCompletion completion;
}
