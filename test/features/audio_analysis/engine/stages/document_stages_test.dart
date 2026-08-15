// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_event.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_hotspot.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric_catalog.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_segment.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_warning.dart';
import 'package:strumsight/features/audio_analysis/domain/insights/insight_rule.dart';
import 'package:strumsight/features/audio_analysis/domain/insights/recommended_action.dart';
import 'package:strumsight/features/audio_analysis/domain/pitch/pitch_frame.dart';
import 'package:strumsight/features/audio_analysis/domain/pitch/monophonic_pitch_segment.dart';
import 'package:strumsight/features/audio_analysis/domain/preprocessed_audio.dart';
import 'package:strumsight/features/audio_analysis/domain/rhythm/beat_grid.dart';
import 'package:strumsight/features/audio_analysis/domain/rhythm/beat_point.dart';
import 'package:strumsight/features/audio_analysis/domain/rhythm/tempo_curve_point.dart';
import 'package:strumsight/features/audio_analysis/domain/signal_quality_report.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_cancellation.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_work_state.dart';
import 'package:strumsight/features/audio_analysis/engine/insights/insight_registry.dart';
import 'package:strumsight/features/audio_analysis/engine/quality/signal_quality_stage.dart';
import 'package:strumsight/features/audio_analysis/engine/rhythm/tempo_curve_builder.dart';
import 'package:strumsight/features/audio_analysis/engine/stages/document_stages.dart';

void main() {
  group('document stages (ADR 0253)', () {
    test('A2 — assembly publishes every available artifact but leaves insight '
        'outputs empty', () async {
      final state = _state();
      final result = await DocumentAssemblyStage(
        clock: () => DateTime.utc(2026, 8, 15),
      ).run(state, _context(DocumentStageIds.assembly));

      final assembled = _success(result);
      final document = assembled.document;
      expect(document, isNotNull);
      expect(document!.id, 'document-run');
      expect(document.createdAt, DateTime.utc(2026, 8, 15));
      expect(document.signalQuality, same(state.signalQuality!.report));
      expect(document.metrics, state.metrics);
      expect(document.capabilities, state.capabilityReports.values);
      expect(document.timeline.events, state.events);
      expect(document.timeline.chordSegments, state.chordSegments);
      expect(document.timeline.beats, hasLength(state.beatGrid!.beats.length));
      expect(document.timeline.bars, <Duration>[Duration.zero]);
      expect(document.timeline.tempoPoints, hasLength(1));
      expect(document.timeline.pitchSegments, hasLength(1));
      expect(document.warnings, state.warnings);
      expect(document.completion.status, AnalysisCompletionStatus.complete);
      expect(document.insights, isEmpty);
      expect(document.hotspots, isEmpty);
    });

    test('A3/A4 — insight rules receive the assembled document and the final '
        'document keeps ranked insight and hotspot output', () async {
      final assembled = _success(
        await DocumentAssemblyStage(
          clock: () => DateTime.utc(2026, 8, 15),
        ).run(_state(), _context(DocumentStageIds.assembly)),
      );
      final first = _CapturingRule(
        id: 'first',
        priority: EvidenceInsightPriority.high,
      );
      final second = _CapturingRule(
        id: 'second',
        priority: EvidenceInsightPriority.critical,
      );
      final stage = InsightsStage(
        registry: InsightRegistry(<AnalysisInsightRule>[first, second]),
        hotspotBuilder: (_) => <AnalysisHotspot>[
          _hotspot(id: 'low', severity: AnalysisHotspotSeverity.low),
          _hotspot(id: 'high', severity: AnalysisHotspotSeverity.high),
        ],
      );

      final finalized = _success(
        await stage.run(assembled, _context(DocumentStageIds.insights)),
      );

      expect(first.context!.document, same(assembled.document));
      expect(second.context!.document, same(assembled.document));
      expect(
        finalized.document!.insights.map((insight) => insight.ruleId),
        <String>['second', 'first'],
      );
      expect(
        finalized.document!.hotspots.map((hotspot) => hotspot.id),
        <String>['high', 'low'],
      );
    });

    test('A6 — unavailable pitch remains unavailable and has no fabricated '
        'pitch metric', () async {
      final state = _state().copyWith(
        metrics: const <AnalysisMetricResult>[],
        pitchFrames: const <PitchFrame>[],
      );

      final assembled = _success(
        await DocumentAssemblyStage(
          clock: () => DateTime.utc(2026, 8, 15),
        ).run(state, _context(DocumentStageIds.assembly)),
      );

      expect(assembled.document!.metrics, isEmpty);
      expect(
        assembled.document!.capabilities
            .singleWhere(
              (report) =>
                  report.capability == AnalysisCapability.monophonicPitch,
            )
            .status,
        CapabilityStatus.unavailable,
      );
    });

    test('document still exists when every degradable capability is '
        'unavailable', () async {
      final state = _state().copyWith(
        metrics: const <AnalysisMetricResult>[],
        unavailableCapabilities: AnalysisCapability.values.toSet(),
      );

      final assembled = _success(
        await DocumentAssemblyStage(
          clock: () => DateTime.utc(2026, 8, 15),
        ).run(state, _context(DocumentStageIds.assembly)),
      );

      expect(assembled.document, isNotNull);
      expect(assembled.document!.metrics, isEmpty);
      expect(
        assembled.document!.capabilities.every(
          (report) => report.status == CapabilityStatus.unavailable,
        ),
        isTrue,
      );
      expect(
        assembled.document!.completion.status,
        AnalysisCompletionStatus.degraded,
      );
    });
  });
}

AnalysisWorkState _success(AppResult<AnalysisWorkState> result) =>
    switch (result) {
      Success<AnalysisWorkState>(:final value) => value,
      Failure<AnalysisWorkState>(:final error) => throw StateError(error.code),
    };

AnalysisWorkState _state() =>
    AnalysisWorkState.seed(
      input: ValidatedPcmAnalysisInput(
        input: PcmAnalysisInput(
          samples: List<double>.filled(5000, 0.1),
          sampleRate: 1000,
          channelCount: 1,
          source: AnalysisInputSource.practiceSession,
        ),
      ),
      mode: AnalysisMode.freePlay,
    ).copyWith(
      preprocessedAudio: PreprocessedAudio(
        originalSamples: List<double>.filled(5000, 0.1),
        canonicalSamples: List<double>.filled(5000, 0.1),
        sampleRate: 1000,
        originalChannelCount: 1,
        normalizationGain: 1,
        preprocessingVersion: 'test.v1',
      ),
      signalQuality: SignalQualityStageResult(
        report: SignalQualityReport(
          overall: 0.9,
          peakDbfs: -10,
          rmsDbfs: -20,
          noiseFloorDbfs: -60,
          clippedSampleRatio: 0,
          silentRatio: 0.1,
          tonalness: 0.5,
        ),
        activeRegionRatio: 0.9,
        degradedMetrics: const <String>{},
        thresholdsVersion: 'test.v1',
      ),
      chordSegments: <ChordSegment>[
        ChordSegment(
          start: Duration.zero,
          end: const Duration(milliseconds: 500),
          confidence: 0.9,
          label: 'C',
        ),
      ],
      events: <AnalysisEvent>[
        StrumEvent(
          id: 'event-1',
          time: Duration.zero,
          confidence: 0.9,
          direction: StrumDirection.down,
        ),
      ],
      beatGrid: BeatGrid(
        beats: <BeatPoint>[
          BeatPoint(
            index: 0,
            time: Duration.zero,
            confidence: 0.9,
            source: BeatSource.estimated,
          ),
        ],
        bars: <BarPoint>[
          BarPoint(index: 0, time: Duration.zero, beatsPerBar: 4),
        ],
        beatsPerBar: 4,
        beatsPerBarSource: BeatsPerBarSource.legacyDefault,
        status: CapabilityStatus.available,
        meterStatus: CapabilityStatus.notApplicable,
      ),
      tempoCurve: TempoCurve(
        status: CapabilityStatus.available,
        legacyBpm: 120,
        medianBpm: 120,
        points: <TempoCurvePoint>[
          TempoCurvePoint(time: Duration.zero, bpm: 120, confidence: 0.9),
        ],
      ),
      pitchFrames: <PitchFrame>[
        PitchFrame(
          time: Duration.zero,
          confidence: 0.9,
          frequencyHz: 440,
          midiNote: 69,
        ),
      ],
      pitchSegments: <MonophonicPitchSegment>[
        MonophonicPitchSegment(
          start: Duration.zero,
          end: const Duration(milliseconds: 500),
          medianHz: 440,
          medianMidi: 69,
          centsOffset: 0,
          stabilityCents: 1,
          confidence: 0.9,
        ),
      ],
      metrics: <AnalysisMetricResult>[
        AnalysisMetricResult(
          id: AnalysisMetricId.rhythmInferredIoiConsistency,
          version: 1,
          status: CapabilityStatus.available,
          confidence: 0.9,
          value: PercentageMetricValue(0.8),
          unit: 'ratio',
          sampleCount: 1,
          evidence: const <String>['event-1'],
        ),
      ],
      capabilityReports: <AnalysisCapability, CapabilityReport>{
        for (final capability in AnalysisCapability.values)
          capability: CapabilityReport(
            capability: capability,
            status: CapabilityStatus.available,
            confidence: 0.9,
          ),
      },
      warnings: <AnalysisWarning>[
        AnalysisWarning(
          kind: AnalysisWarningKind.processing,
          severity: AnalysisWarningSeverity.info,
          messageKey: 'analysis.test_warning',
        ),
      ],
    );

AnalysisStageContext _context(String stageId) => AnalysisStageContext(
  runId: 'run',
  phase: stageId == DocumentStageIds.assembly
      ? AnalysisProgressPhase.buildingInsights
      : AnalysisProgressPhase.finalizing,
  cancellationToken: AnalysisCancellationSource(),
  eventSink: (_) {},
);

AnalysisHotspot _hotspot({
  required String id,
  required AnalysisHotspotSeverity severity,
}) => AnalysisHotspot(
  id: id,
  kind: AnalysisHotspotKind.timing,
  start: Duration.zero,
  end: const Duration(milliseconds: 100),
  severity: severity,
  confidence: 0.9,
  metricIds: const <String>[AnalysisMetricId.rhythmInferredIoiConsistency],
  evidenceIds: const <String>['event-1'],
);

final class _CapturingRule implements AnalysisInsightRule {
  _CapturingRule({required this.id, required this.priority});

  @override
  final String id;

  @override
  final EvidenceInsightPriority priority;

  AnalysisInsightContext? context;

  @override
  int get version => 1;

  @override
  EvidenceBackedAnalysisInsight? evaluate(AnalysisInsightContext value) {
    context = value;
    return EvidenceBackedAnalysisInsight(
      ruleId: id,
      ruleVersion: version,
      priority: priority,
      kind: EvidenceInsightKind.improvement,
      factIds: const <String>[AnalysisMetricId.rhythmInferredIoiConsistency],
      evidenceIds: const <String>['event-1'],
      messageKey: 'analysis.test_$id',
      messageArgs: const <String, String>{},
      confidence: 0.9,
      recommendedAction: const RepeatSlowerAction(
        metricId: AnalysisMetricId.rhythmInferredIoiConsistency,
      ),
    );
  }
}
