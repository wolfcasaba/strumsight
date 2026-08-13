import '../analysis_capability.dart';
import '../analysis_document.dart';
import '../analysis_hotspot.dart';
import '../analysis_insight.dart';
import '../analysis_metric.dart';
import '../analysis_mode.dart';
import '../analysis_warning.dart';

/// Version of the export JSON boundary — distinct from
/// [analysisDocumentSchemaVersion]; a change to the internal V2 document
/// shape must never silently ripple into the exported contract.
const int analysisExportSchemaVersion = 1;

/// Privacy-safe subset of [AnalysisInputSummary] — deliberately excludes
/// [AnalysisInputSummary.sourceName] (an imported filename) and
/// [AnalysisInputSummary.fingerprint] (a content-derived identifier).
final class AnalysisExportInput {
  const AnalysisExportInput({
    required this.source,
    required this.duration,
    required this.sampleRate,
    required this.channelCount,
  });
  final AnalysisInputSource source;
  final Duration duration;
  final int sampleRate;
  final int channelCount;
}

/// Privacy-safe subset of [SignalQualityReport] — the numeric quality
/// facts carry no raw audio and are safe to leave the device.
final class AnalysisExportSignalQuality {
  const AnalysisExportSignalQuality({
    required this.overall,
    required this.peakDbfs,
    required this.rmsDbfs,
    required this.noiseFloorDbfs,
    required this.clippedSampleRatio,
    required this.silentRatio,
    required this.tonalness,
    required this.measured,
  });
  final double overall;
  final double peakDbfs;
  final double rmsDbfs;
  final double noiseFloorDbfs;
  final double clippedSampleRatio;
  final double silentRatio;
  final double tonalness;
  final bool measured;
}

/// Privacy-safe subset of [CapabilityReport] — deliberately excludes
/// [CapabilityReport.details], the open-ended internal diagnostics bag.
final class AnalysisExportCapability {
  const AnalysisExportCapability({
    required this.capability,
    required this.status,
    required this.confidence,
    this.reason,
  });
  final AnalysisCapability capability;
  final CapabilityStatus status;
  final double confidence;
  final CapabilityUnavailableReason? reason;
}

/// Privacy-safe subset of [AnalysisMetricResult] — deliberately excludes
/// [AnalysisMetricResult.evidence] (internal timeline evidence ids).
final class AnalysisExportMetric {
  const AnalysisExportMetric({
    required this.id,
    required this.version,
    required this.status,
    required this.confidence,
    required this.value,
    required this.unit,
    required this.sampleCount,
    this.unavailableReason,
  });
  final String id;
  final int version;
  final CapabilityStatus status;
  final double confidence;
  final AnalysisMetricValue? value;
  final String unit;
  final int sampleCount;
  final CapabilityUnavailableReason? unavailableReason;
}

/// Privacy-safe subset of [AnalysisHotspot] — deliberately excludes
/// [AnalysisHotspot.id]/`metricIds`/`evidenceIds`, internal cross-references.
final class AnalysisExportHotspot {
  const AnalysisExportHotspot({
    required this.kind,
    required this.start,
    required this.end,
    required this.severity,
    required this.confidence,
  });
  final AnalysisHotspotKind kind;
  final Duration start;
  final Duration end;
  final AnalysisHotspotSeverity severity;
  final double confidence;
}

/// Privacy-safe subset of [AnalysisInsight] — deliberately excludes
/// [AnalysisInsight.factIds], internal evidence cross-references.
final class AnalysisExportInsight {
  AnalysisExportInsight({
    required this.id,
    required this.ruleId,
    required this.ruleVersion,
    required this.priority,
    required this.kind,
    required this.messageKey,
    Map<String, String> messageArgs = const <String, String>{},
    required this.recommendedAction,
  }) : messageArgs = Map<String, String>.unmodifiable(messageArgs);
  final String id;
  final String ruleId;
  final String ruleVersion;
  final AnalysisInsightPriority priority;
  final AnalysisInsightKind kind;
  final String messageKey;
  final Map<String, String> messageArgs;
  final AnalysisRecommendedAction recommendedAction;
}

final class AnalysisExportWarning {
  AnalysisExportWarning({
    required this.kind,
    required this.severity,
    required this.messageKey,
    Map<String, String> messageArgs = const <String, String>{},
  }) : messageArgs = Map<String, String>.unmodifiable(messageArgs);
  final AnalysisWarningKind kind;
  final AnalysisWarningSeverity severity;
  final String messageKey;
  final Map<String, String> messageArgs;
}

final class AnalysisExportCompletion {
  const AnalysisExportCompletion({required this.status, this.failureCode});
  final AnalysisCompletionStatus status;
  final String? failureCode;
}

/// Allowlist-redacted, versioned export contract (ADR 0247). Every field on
/// this model is safe to leave the device: no raw audio, no imported
/// filename, no device identifier, no internal diagnostics.
final class AnalysisExport {
  AnalysisExport({
    required this.exportSchemaVersion,
    required this.documentId,
    required this.createdAt,
    required this.mode,
    required this.input,
    required this.signalQuality,
    required List<AnalysisExportCapability> capabilities,
    required List<AnalysisExportMetric> metrics,
    required List<AnalysisExportHotspot> hotspots,
    required List<AnalysisExportInsight> insights,
    required List<AnalysisExportWarning> warnings,
    required this.completion,
  }) : capabilities = List<AnalysisExportCapability>.unmodifiable(capabilities),
       metrics = List<AnalysisExportMetric>.unmodifiable(metrics),
       hotspots = List<AnalysisExportHotspot>.unmodifiable(hotspots),
       insights = List<AnalysisExportInsight>.unmodifiable(insights),
       warnings = List<AnalysisExportWarning>.unmodifiable(warnings);

  final int exportSchemaVersion;
  final String documentId;
  final DateTime createdAt;
  final AnalysisMode mode;
  final AnalysisExportInput input;
  final AnalysisExportSignalQuality signalQuality;
  final List<AnalysisExportCapability> capabilities;
  final List<AnalysisExportMetric> metrics;
  final List<AnalysisExportHotspot> hotspots;
  final List<AnalysisExportInsight> insights;
  final List<AnalysisExportWarning> warnings;
  final AnalysisExportCompletion completion;
}
