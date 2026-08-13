import '../analysis_document.dart';
import 'analysis_export.dart';

/// Allowlist-based export redaction (ADR 0247, brief §5 Döntés 1).
///
/// [apply] only ever *reads* the fields it explicitly copies below — it
/// never iterates the source document's open-ended maps
/// ([CapabilityReport.details]) or forwards fields carrying an imported
/// filename, a content fingerprint, or the full provenance/diagnostics
/// block. A denylist would have to name every dangerous field and would
/// silently leak the next one added; this policy leaks nothing it does not
/// explicitly name.
final class RedactionPolicy {
  const RedactionPolicy();

  AnalysisExport apply(AnalysisDocument document) => AnalysisExport(
    exportSchemaVersion: analysisExportSchemaVersion,
    documentId: document.id,
    createdAt: document.createdAt,
    mode: document.mode,
    input: AnalysisExportInput(
      source: document.input.source,
      duration: document.input.duration,
      sampleRate: document.input.sampleRate,
      channelCount: document.input.channelCount,
    ),
    signalQuality: AnalysisExportSignalQuality(
      overall: document.signalQuality.overall,
      peakDbfs: document.signalQuality.peakDbfs,
      rmsDbfs: document.signalQuality.rmsDbfs,
      noiseFloorDbfs: document.signalQuality.noiseFloorDbfs,
      clippedSampleRatio: document.signalQuality.clippedSampleRatio,
      silentRatio: document.signalQuality.silentRatio,
      tonalness: document.signalQuality.tonalness,
      measured: document.signalQuality.measured,
    ),
    capabilities: <AnalysisExportCapability>[
      for (final capability in document.capabilities)
        AnalysisExportCapability(
          capability: capability.capability,
          status: capability.status,
          confidence: capability.confidence,
          reason: capability.reason,
        ),
    ],
    metrics: <AnalysisExportMetric>[
      for (final metric in document.metrics)
        AnalysisExportMetric(
          id: metric.id,
          version: metric.version,
          status: metric.status,
          confidence: metric.confidence,
          value: metric.value,
          unit: metric.unit,
          sampleCount: metric.sampleCount,
          unavailableReason: metric.unavailableReason,
        ),
    ],
    hotspots: <AnalysisExportHotspot>[
      for (final hotspot in document.hotspots)
        AnalysisExportHotspot(
          kind: hotspot.kind,
          start: hotspot.start,
          end: hotspot.end,
          severity: hotspot.severity,
          confidence: hotspot.confidence,
        ),
    ],
    insights: <AnalysisExportInsight>[
      for (final insight in document.insights)
        AnalysisExportInsight(
          id: insight.id,
          ruleId: insight.ruleId,
          ruleVersion: insight.ruleVersion,
          priority: insight.priority,
          kind: insight.kind,
          messageKey: insight.messageKey,
          messageArgs: insight.messageArgs,
          recommendedAction: insight.recommendedAction,
        ),
    ],
    warnings: <AnalysisExportWarning>[
      for (final warning in document.warnings)
        AnalysisExportWarning(
          kind: warning.kind,
          severity: warning.severity,
          messageKey: warning.messageKey,
          messageArgs: warning.messageArgs,
        ),
    ],
    completion: AnalysisExportCompletion(
      status: document.completion.status,
      failureCode: document.completion.failureCode,
    ),
  );
}
