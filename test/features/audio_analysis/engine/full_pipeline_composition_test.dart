// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_cancellation.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_pipeline.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_work_state.dart';
import 'package:strumsight/features/audio_analysis/engine/stages/analysis_stage_phases.dart';
import 'package:strumsight/features/audio_analysis/engine/stages/evaluation_stages.dart';
import 'package:strumsight/features/audio_analysis/engine/stages/ingest_stages.dart';

import '../../../support/synth.dart';

const _sampleRate = 44100;

void main() {
  group('full analysis pipeline composition (ADR 0252)', () {
    test(
      'A2/A8 — all 18 stages run in a single live AnalysisPipeline with '
      'non-decreasing published phases',
      () async {
        final pipeline = AnalysisPipeline<AnalysisWorkState>(
          stages: buildFullAnalysisStages(),
          failureClassifier: classifyAnalysisStageFailure,
          stagePhases: analysisStagePhases,
        );
        final initial = AnalysisWorkState.seed(
          input: _input(samples: _fullClip()),
          mode: AnalysisMode.freePlay,
        );

        final run = pipeline.start(
          initial,
          cancellationToken: AnalysisCancellationSource(),
        );
        final events = <AnalysisProgressEvent>[];
        final done = Completer<void>();
        final subscription = run.progress.listen(
          events.add,
          onDone: done.complete,
        );
        final result = await run.result;
        await done.future;
        await subscription.cancel();

        expect(result.completion, AnalysisCompletionStatus.complete);
        final value = result.value;
        expect(value, isNotNull);
        expect(
          result.provenance.stageTimings.map((timing) => timing.id),
          <String>[
            IngestStageIds.preprocessing,
            IngestStageIds.signalQuality,
            IngestStageIds.legacyEvidence,
            IngestStageIds.pitch,
            IngestStageIds.harmony,
            IngestStageIds.rhythm,
            IngestStageIds.events,
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
          ],
        );

        final publishedPhases = events
            .whereType<AnalysisPhaseProgressEvent>()
            .map((event) => event.phase)
            .toList();
        expect(publishedPhases, hasLength(18));
        expect(
          publishedPhases,
          <AnalysisProgressPhase>[
            for (final stage in buildFullAnalysisStages())
              analysisStagePhases[stage.id]!,
          ],
        );
        for (var index = 1; index < publishedPhases.length; index++) {
          expect(
            publishedPhases[index].index,
            greaterThanOrEqualTo(publishedPhases[index - 1].index),
          );
        }
        // The evaluation stages share `computingMetrics` — proof that the
        // decoupled map, not the old positional cap, is what makes 18
        // stages composable at all (ADR 0252 §5.1).
        expect(
          publishedPhases.where(
            (phase) => phase == AnalysisProgressPhase.computingMetrics,
          ),
          hasLength(10),
        );
        expect(value!.capabilityReports, isNotEmpty);
        expect(value.overallConfidence, isNotNull);
      },
    );
  });
}

ValidatedPcmAnalysisInput _input({required List<double> samples}) =>
    ValidatedPcmAnalysisInput(
      input: PcmAnalysisInput(
        samples: samples,
        sampleRate: _sampleRate,
        channelCount: 1,
        source: AnalysisInputSource.practiceSession,
      ),
    );

List<double> _sine(double frequency, {required double seconds}) =>
    List<double>.generate(
      (seconds * _sampleRate).round(),
      (index) => 0.4 * math.sin(2 * math.pi * frequency * index / _sampleRate),
    );

/// A single real clip combining a clean monophonic passage (so the pitch
/// stage extracts voiced frames/segments) with a polyphonic chord-plus-strum
/// passage (so the legacy-evidence stage's wrapped V1 analyzer derives
/// non-empty chords and strums, in turn feeding harmony/rhythm/events and
/// every evaluation stage downstream). Mirrors
/// `ingest_pipeline_composition_test.dart`'s A4 fixture (ADR 0250).
List<double> _fullClip() => <double>[
  ..._sine(220, seconds: 0.4),
  ...chordSignal(cMajorFreqs, seconds: 0.8),
  ...chordSignal(gMajorFreqs, seconds: 0.8),
  ...strumPattern(
    lowFirstPerStrum: <bool>[true, false, true, false],
    gapSeconds: 0.5,
  ),
];
