import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';

import '../../domain/analysis_capability.dart';
import '../../domain/analysis_document.dart';
import '../../domain/analysis_event.dart';
import '../../domain/analysis_hotspot.dart';
import '../../domain/analysis_input_summary.dart';
import '../../domain/analysis_insight.dart';
import '../../domain/analysis_metric_catalog.dart';
import '../../domain/analysis_provenance.dart';
import '../../domain/analysis_timeline.dart';
import '../../domain/insights/insight_rule.dart';
import '../../domain/insights/recommended_action.dart';
import '../../domain/analysis_segment.dart';
import '../../domain/rhythm/beat_point.dart';
import '../../domain/rhythm/tempo_curve_point.dart';
import '../analysis_context.dart';
import '../analysis_stage.dart';
import '../analysis_work_state.dart';
import '../insights/hotspot_ranker.dart';
import '../insights/insight_ranker.dart';
import '../insights/insight_registry.dart';
import '../insights/insight_rules.dart';
import '../metrics/timing_hotspots.dart';

/// IDs contributed by the document assembly and insight stages (ADR 0253).
abstract final class DocumentStageIds {
  static const String assembly = 'document-assembly';
  static const String insights = 'insights';
}

/// Test seam around the deterministic hotspot derivation from work-state
/// evidence. It does not accept caller-supplied document data.
typedef AnalysisHotspotBuilder =
    List<AnalysisHotspot> Function(AnalysisWorkState input);

/// Assembles the publishable document skeleton before any insight rule runs.
/// Only insight and hotspot output is intentionally absent at this point.
final class DocumentAssemblyStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  DocumentAssemblyStage({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const String _appVersion = 'strumsight';
  static const String _analyzerVersion = 'audio-analysis-v2';
  static const String _pipelineVersion = 'gov-30c.v1';
  static const String _platform = 'on-device';

  final DateTime Function() _clock;

  @override
  String get id => DocumentStageIds.assembly;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) async {
    try {
      context.cancellationToken.throwIfCancelled();
      final document = _assemble(input, context);
      context.cancellationToken.throwIfCancelled();
      return Success<AnalysisWorkState>(input.copyWith(document: document));
    } catch (error, stackTrace) {
      return Failure<AnalysisWorkState>(
        UnknownFailure(cause: error, stackTrace: stackTrace),
      );
    }
  }

  AnalysisDocument _assemble(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) {
    final quality = input.signalQuality?.report;
    if (quality == null) {
      throw StateError('Document assembly requires measured signal quality.');
    }
    final fingerprint = _fingerprint(input);
    return AnalysisDocument(
      id: 'document-${context.runId}',
      schemaVersion: analysisDocumentSchemaVersion,
      createdAt: _clock().toUtc(),
      mode: input.mode,
      input: AnalysisInputSummary(
        source: input.input.input.source,
        duration: _duration(input),
        sampleRate: input.input.input.sampleRate,
        channelCount: input.input.input.channelCount,
        fingerprint: fingerprint,
      ),
      provenance: AnalysisProvenance(
        appVersion: _appVersion,
        analyzerVersion: _analyzerVersion,
        pipelineVersion: _pipelineVersion,
        stageVersions: <String, String>{id: '$version'},
        dspConfigHash:
            'preprocessing:${input.preprocessedAudio?.preprocessingVersion ?? 'unavailable'}',
        modelManifestIds:
            input.legacyEvidence?.call.modelManifestIds ?? const <String>[],
        inputFingerprint: fingerprint,
        platform: _platform,
        featureFlagSnapshot: const <String, bool>{},
      ),
      signalQuality: quality,
      capabilities: _capabilities(input),
      timeline: _timeline(input),
      metrics: input.metrics,
      hotspots: const <AnalysisHotspot>[],
      insights: const <AnalysisInsight>[],
      warnings: input.warnings,
      completion: AnalysisCompletion(
        status: _unavailableCapabilities(input).isEmpty
            ? AnalysisCompletionStatus.complete
            : AnalysisCompletionStatus.degraded,
      ),
    );
  }
}

/// Evaluates the immutable preliminary document, then returns a final document
/// with ranked insights and hotspots while preserving every other field.
final class InsightsStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  InsightsStage({
    InsightRegistry? registry,
    InsightRanker? insightRanker,
    HotspotRanker? hotspotRanker,
    AnalysisHotspotBuilder? hotspotBuilder,
  }) : _registry = registry ?? InsightRegistry(buildInitialInsightRules()),
       _insightRanker = insightRanker ?? const InsightRanker(),
       _hotspotRanker = hotspotRanker ?? const HotspotRanker(),
       _hotspotBuilder = hotspotBuilder ?? _buildTimingHotspots;

  final InsightRegistry _registry;
  final InsightRanker _insightRanker;
  final HotspotRanker _hotspotRanker;
  final AnalysisHotspotBuilder _hotspotBuilder;

  @override
  String get id => DocumentStageIds.insights;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) async {
    try {
      context.cancellationToken.throwIfCancelled();
      final preliminary = input.document;
      if (preliminary == null) {
        throw StateError('Insights require an assembled analysis document.');
      }
      final contextDocument = AnalysisInsightContext(document: preliminary);
      final rankedInsights = _insightRanker.rank(
        _registry.evaluate(contextDocument),
      );
      final hotspots = _hotspotRanker.rank(_hotspotBuilder(input));
      final finalDocument = _withInsightOutputs(
        preliminary,
        insights: <AnalysisInsight>[
          for (final insight in rankedInsights.visibleInsights)
            _toDocumentInsight(insight),
          for (final insight in rankedInsights.additionalInsights)
            _toDocumentInsight(insight),
        ],
        hotspots: hotspots,
      );
      context.cancellationToken.throwIfCancelled();
      return Success<AnalysisWorkState>(
        input.copyWith(document: finalDocument),
      );
    } catch (error, stackTrace) {
      return Failure<AnalysisWorkState>(
        UnknownFailure(cause: error, stackTrace: stackTrace),
      );
    }
  }
}

List<CapabilityReport> _capabilities(AnalysisWorkState input) =>
    <CapabilityReport>[
      for (final capability in AnalysisCapability.values)
        _capabilityFor(input, capability),
    ];

const _pitchCapabilities = <AnalysisCapability>{
  AnalysisCapability.monophonicPitch,
  AnalysisCapability.intonation,
  AnalysisCapability.noteStability,
};

Set<AnalysisCapability> _unavailableCapabilities(AnalysisWorkState input) =>
    <AnalysisCapability>{
      ...input.unavailableCapabilities,
      if (input.pitchFrames.isEmpty) ..._pitchCapabilities,
    };

CapabilityReport _capabilityFor(
  AnalysisWorkState input,
  AnalysisCapability capability,
) {
  final existing = input.capabilityReports[capability];
  if (_unavailableCapabilities(input).contains(capability)) {
    return CapabilityReport(
      capability: capability,
      status: CapabilityStatus.unavailable,
      confidence: 0,
      reason: existing?.reason ?? CapabilityUnavailableReason.internalFailure,
      calibrationVersion: existing?.calibrationVersion ?? 'identity.v1',
      calibrationSource:
          existing?.calibrationSource ?? ConfidenceCalibrationSource.identity,
      details: existing?.details ?? const <String, Object?>{},
    );
  }
  return existing ??
      CapabilityReport(
        capability: capability,
        status: CapabilityStatus.notApplicable,
        confidence: 0,
      );
}

AnalysisTimeline _timeline(AnalysisWorkState input) => AnalysisTimeline(
  duration: _duration(input),
  events: input.events,
  chordSegments: input.chordSegments,
  beats: <BeatEvent>[
    for (final beat in input.beatGrid?.beats ?? const <BeatPoint>[])
      BeatEvent(
        id: 'beat-${beat.index}',
        time: beat.time,
        confidence: beat.confidence,
        beatIndex: beat.index,
      ),
  ],
  bars: <Duration>[
    for (final bar in input.beatGrid?.bars ?? const <BarPoint>[]) bar.time,
  ],
  tempoPoints: <TempoPoint>[
    for (final point in input.tempoCurve?.points ?? const <TempoCurvePoint>[])
      TempoPoint(time: point.time, bpm: point.bpm),
  ],
  pitchSegments: <PitchSegment>[
    for (final segment in input.pitchSegments)
      PitchSegment(
        start: segment.start,
        end: segment.end,
        confidence: segment.confidence,
        midiNote: segment.medianMidi,
      ),
  ],
);

Duration _duration(AnalysisWorkState input) => Duration(
  microseconds:
      input.input.input.samples.length *
      Duration.microsecondsPerSecond ~/
      input.input.input.sampleRate,
);

String _fingerprint(AnalysisWorkState input) {
  final pcm = ByteData(input.input.input.samples.length * 2);
  for (var index = 0; index < input.input.input.samples.length; index++) {
    final sample = input.input.input.samples[index];
    if (!sample.isFinite) {
      throw ArgumentError.value(sample, 'samples', 'must be finite');
    }
    pcm.setInt16(
      index * 2,
      (sample.clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  final header = <String>[
    input.input.input.sampleRate.toString(),
    input.input.input.channelCount.toString(),
    input.preprocessedAudio?.preprocessingVersion ?? 'unavailable',
  ].join(':');
  return crypto.sha256.convert(<int>[
    ...utf8.encode(header),
    ...pcm.buffer.asUint8List(),
  ]).toString();
}

List<AnalysisHotspot> _buildTimingHotspots(AnalysisWorkState input) {
  final alignment = input.alignment;
  if (alignment == null) return const <AnalysisHotspot>[];
  return buildTimingHotspots(
    alignment: alignment,
    tolerance: const Duration(milliseconds: 20),
    ids: TimingMetricSuiteIds.target,
  );
}

AnalysisDocument _withInsightOutputs(
  AnalysisDocument document, {
  required List<AnalysisInsight> insights,
  required List<AnalysisHotspot> hotspots,
}) => AnalysisDocument(
  id: document.id,
  schemaVersion: document.schemaVersion,
  createdAt: document.createdAt,
  mode: document.mode,
  input: document.input,
  provenance: document.provenance,
  signalQuality: document.signalQuality,
  capabilities: document.capabilities,
  timeline: document.timeline,
  metrics: document.metrics,
  hotspots: hotspots,
  insights: insights,
  warnings: document.warnings,
  completion: document.completion,
);

AnalysisInsight _toDocumentInsight(EvidenceBackedAnalysisInsight insight) =>
    AnalysisInsight(
      id: '${insight.ruleId}.v${insight.ruleVersion}',
      ruleId: insight.ruleId,
      ruleVersion: '${insight.ruleVersion}',
      priority: switch (insight.priority) {
        EvidenceInsightPriority.critical ||
        EvidenceInsightPriority.high => AnalysisInsightPriority.high,
        EvidenceInsightPriority.medium => AnalysisInsightPriority.medium,
        EvidenceInsightPriority.low => AnalysisInsightPriority.low,
      },
      kind: switch (insight.kind) {
        EvidenceInsightKind.improvement => AnalysisInsightKind.recommendation,
        EvidenceInsightKind.strength => AnalysisInsightKind.observation,
        EvidenceInsightKind.nextAction => AnalysisInsightKind.recommendation,
        EvidenceInsightKind.qualityWarning => AnalysisInsightKind.caution,
      },
      factIds: insight.factIds,
      messageKey: insight.messageKey,
      messageArgs: insight.messageArgs,
      recommendedAction: switch (insight.recommendedAction) {
        PracticeHotspotAction() || OpenChordTransitionExerciseAction() =>
          AnalysisRecommendedAction.repeatSection,
        RepeatSlowerAction() => AnalysisRecommendedAction.slowDown,
        CalibrateInputAction() => AnalysisRecommendedAction.adjustInput,
        CompareWithPreviousAction() ||
        AskTutorAction() => AnalysisRecommendedAction.continuePractice,
      },
    );
