import '../analysis_document.dart';
import 'analysis_export.dart';

/// Every `messageKey` this build's insight/warning rules are known to emit,
/// mapped to the finite set of argument names that key's localised template
/// interpolates (E06-R27 review BLOCKER — `messageArgs` is an unrestricted
/// `Map<String, String>` on the source model, so without this allowlist an
/// attacker- or bug-controlled key could ride through the export unredacted
/// under any name). A `messageKey`/argument-name pair absent from this map
/// is dropped, not forwarded — closed, not open, by construction.
const Map<String, Set<String>> _allowedMessageArgKeys = <String, Set<String>>{
  'analysisInsightRushBias': <String>{'milliseconds'},
  'analysisInsightDragBias': <String>{'milliseconds'},
  'analysisInsightLargeTimingOutliers': <String>{'p90Milliseconds'},
  'analysisInsightSecondHalfDrift': <String>{'milliseconds'},
  'analysisInsightWeakUpstroke': <String>{'ratio'},
  'analysisInsightChordTransitionHotspot': <String>{'hotspotId'},
  'analysisInsightLowSignalQuality': <String>{'ratio'},
  'analysisInsightCompatibleImprovement': <String>{'metricId', 'delta'},
  'analysisInsightInsufficientData': <String>{},
  'analysis.stage_unavailable': <String>{'stageId', 'failureCode'},
  'analysis.migration.legacy_v1': <String>{'beatsPerBar'},
  'analysis.migration.legacy_v1.dropped_timeline_entries': <String>{
    'droppedChords',
    'droppedStrums',
  },
  'quality.recording_silent': <String>{},
  'quality.recording_low_level': <String>{},
  'quality.recording_clipped': <String>{},
  'quality.recording_short_clip': <String>{},
};

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

  /// Filters [args] down to the finite set [_allowedMessageArgKeys] declares
  /// for [messageKey]. An unrecognised `messageKey` — or an unrecognised
  /// argument name under a known one — yields no argument at all, never a
  /// forwarded value. This is what stops a filename, a device id, or any
  /// other unreviewed string from riding through `messageArgs`.
  static Map<String, String> _redactedMessageArgs(
    String messageKey,
    Map<String, String> args,
  ) {
    final allowed = _allowedMessageArgKeys[messageKey];
    if (allowed == null || allowed.isEmpty) return const <String, String>{};
    return <String, String>{
      for (final entry in args.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
    };
  }

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
          messageArgs: _redactedMessageArgs(
            insight.messageKey,
            insight.messageArgs,
          ),
          recommendedAction: insight.recommendedAction,
        ),
    ],
    warnings: <AnalysisExportWarning>[
      for (final warning in document.warnings)
        AnalysisExportWarning(
          kind: warning.kind,
          severity: warning.severity,
          messageKey: warning.messageKey,
          messageArgs: _redactedMessageArgs(
            warning.messageKey,
            warning.messageArgs,
          ),
        ),
    ],
    completion: AnalysisExportCompletion(
      status: document.completion.status,
      failureCode: document.completion.failureCode,
    ),
  );
}
