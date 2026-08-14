// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_event.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric_catalog.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/domain/preprocessed_audio.dart';
import 'package:strumsight/features/audio_analysis/domain/rhythm/beat_grid.dart';
import 'package:strumsight/features/audio_analysis/domain/rhythm/beat_point.dart';
import 'package:strumsight/features/audio_analysis/domain/signal_quality_report.dart';
import 'package:strumsight/features/audio_analysis/domain/target/analysis_target.dart';
import 'package:strumsight/features/audio_analysis/domain/target/expected_event.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_cancellation.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_stage.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_work_state.dart';
import 'package:strumsight/features/audio_analysis/engine/quality/signal_quality_stage.dart';
import 'package:strumsight/features/audio_analysis/engine/stages/evaluation_stages.dart';

void main() {
  group('evaluation stage composition (ADR 0251)', () {
    test('A2 — builds eleven uniform evaluation stages in fixed order', () {
      final stages = buildEvaluationStages();

      expect(stages.map((stage) => stage.id), <String>[
        EvaluationStageIds.alignment,
        EvaluationStageIds.timing,
        EvaluationStageIds.timingHotspots,
        EvaluationStageIds.rhythm,
        EvaluationStageIds.pitch,
        EvaluationStageIds.dynamics,
        EvaluationStageIds.accent,
        EvaluationStageIds.subdivision,
        EvaluationStageIds.transitions,
        EvaluationStageIds.technique,
        EvaluationStageIds.capability,
      ]);
    });

    test(
      'A3–A5 — the three reference cells preserve independent metrics',
      () async {
        final withoutReference = await _run(buildEvaluationStages(), _state());
        final withEmptyReference = await _run(
          buildEvaluationStages(),
          _state(target: _target(const <ExpectedEvent>[])),
        );
        final withReference = await _run(
          buildEvaluationStages(),
          _state(target: _target(_expectedEvents())),
        );

        expect(withoutReference.value, isNotNull);
        expect(withEmptyReference.value, isNotNull);
        expect(withReference.value, isNotNull);
        expect(withoutReference.value!.alignment, isNull);
        expect(withEmptyReference.value!.alignment, isNull);
        expect(withReference.value!.alignment, isNotNull);
        expect(
          withoutReference.unavailableCapabilities,
          contains(AnalysisCapability.timingAccuracy),
        );
        expect(
          withEmptyReference
              .value!
              .capabilityReports[AnalysisCapability.timingAccuracy]!
              .reason,
          CapabilityUnavailableReason.noReferenceTarget,
        );

        final absentReferenceMetricIds = withoutReference.value!.metrics
            .map((metric) => metric.id)
            .toSet();
        final presentReferenceMetricIds = withReference.value!.metrics
            .map((metric) => metric.id)
            .toSet();
        expect(
          presentReferenceMetricIds.difference(absentReferenceMetricIds),
          TimingMetricSuiteIds.target.all,
        );
        expect(
          absentReferenceMetricIds.intersection(DynamicsMetricIds.all),
          DynamicsMetricIds.all,
        );
        expect(
          absentReferenceMetricIds.intersection(
            RhythmMetricSuiteIds.inferred.all,
          ),
          RhythmMetricSuiteIds.inferred.all,
        );
      },
    );

    test(
      'A8 — fatal capability failure stops the sequential harness',
      () async {
        final calledStageIds = <String>[];
        final stages = <AnalysisStage<AnalysisWorkState, AnalysisWorkState>>[
          ...buildEvaluationStages().take(10),
          _FailingStage(id: EvaluationStageIds.capability, log: calledStageIds),
        ];

        final result = await _run(stages, _state());

        expect(result.value, isNull);
        expect(result.failure, isNotNull);
        expect(calledStageIds, <String>[EvaluationStageIds.capability]);
      },
    );
  });
}

Future<_SequentialResult> _run(
  List<AnalysisStage<AnalysisWorkState, AnalysisWorkState>> stages,
  AnalysisWorkState initial,
) async {
  var current = initial;
  final warnings = <String>[];
  final unavailableCapabilities = <AnalysisCapability>{};
  for (final stage in stages) {
    final result = await stage.run(current, _context(stage.id));
    switch (result) {
      case Success<AnalysisWorkState>(:final value):
        current = value;
      case Failure<AnalysisWorkState>(:final error):
        final classified = classifyEvaluationStageFailure(stage.id, error);
        if (!classified.isDegradable) {
          return _SequentialResult(
            value: null,
            warnings: warnings,
            unavailableCapabilities: unavailableCapabilities,
            failure: classified.failure,
          );
        }
        warnings.add(stage.id);
        unavailableCapabilities.addAll(classified.unavailableCapabilities);
    }
  }
  unavailableCapabilities.addAll(current.unavailableCapabilities);
  return _SequentialResult(
    value: current,
    warnings: warnings,
    unavailableCapabilities: unavailableCapabilities,
  );
}

AnalysisWorkState _state({AnalysisTarget? target}) =>
    AnalysisWorkState.seed(
      input: ValidatedPcmAnalysisInput(
        input: PcmAnalysisInput(
          samples: List<double>.filled(5000, 0.1),
          sampleRate: 1000,
          channelCount: 1,
          source: AnalysisInputSource.practiceSession,
        ),
      ),
      mode: AnalysisMode.practiceTarget,
      target: target,
    ).copyWith(
      preprocessedAudio: PreprocessedAudio(
        originalSamples: List<double>.filled(5000, 0.1),
        canonicalSamples: List<double>.filled(5000, 0.1),
        sampleRate: 1000,
        originalChannelCount: 1,
        normalizationGain: 1,
        preprocessingVersion: 'test',
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
        thresholdsVersion: 'test',
      ),
      events: _strums(),
      beatGrid: BeatGrid(
        beats: <BeatPoint>[
          for (var index = 0; index < 9; index += 1)
            BeatPoint(
              index: index,
              time: Duration(milliseconds: 500 * index),
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
    );

AnalysisTarget _target(List<ExpectedEvent> expectedEvents) => AnalysisTarget(
  id: 'practice-target',
  kind: AnalysisTargetKind.practice,
  timebase: AnalysisTargetTimebase.session,
  expectedEvents: expectedEvents,
);

List<ExpectedEvent> _expectedEvents() => <ExpectedEvent>[
  for (var index = 0; index < 8; index += 1)
    ExpectedEvent(
      id: 'expected-$index',
      time: Duration(milliseconds: 500 * index),
      type: ExpectedEventType.strum,
      direction: index.isEven ? StrumDirection.down : StrumDirection.up,
    ),
];

List<StrumEvent> _strums() => <StrumEvent>[
  for (var index = 0; index < 8; index += 1)
    StrumEvent(
      id: 'strum-$index',
      time: Duration(milliseconds: 500 * index),
      confidence: 0.9,
      direction: index.isEven ? StrumDirection.down : StrumDirection.up,
      sampleIndex: 500 * index,
      attackStrength: 0.1,
      localRms: 0.1,
    ),
];

AnalysisStageContext _context(String stageId) => AnalysisStageContext(
  runId: 'evaluation-$stageId',
  phase: AnalysisProgressPhase.computingMetrics,
  cancellationToken: AnalysisCancellationSource(),
  eventSink: (_) {},
);

final class _SequentialResult {
  const _SequentialResult({
    required this.value,
    required this.warnings,
    required this.unavailableCapabilities,
    this.failure,
  });

  final AnalysisWorkState? value;
  final List<String> warnings;
  final Set<AnalysisCapability> unavailableCapabilities;
  final AppFailure? failure;
}

final class _FailingStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  const _FailingStage({required this.id, required this.log});

  @override
  final String id;

  final List<String> log;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) async {
    log.add(id);
    return const Failure<AnalysisWorkState>(ValidationFailure());
  }
}
