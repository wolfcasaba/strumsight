// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_pipeline.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_work_state.dart';
import 'package:strumsight/features/audio_analysis/engine/stages/analysis_stage_phases.dart';
import 'package:strumsight/features/audio_analysis/engine/stages/evaluation_stages.dart';
import 'package:strumsight/features/audio_analysis/engine/stages/ingest_stages.dart';

void main() {
  group('analysisStagePhases (ADR 0252)', () {
    test(
      'A5 — every one of the 20 built stages has exactly one phase mapping',
      () {
        final stages = buildFullAnalysisStages();

        expect(stages, hasLength(20));
        expect(
          stages.map((stage) => stage.id).toSet(),
          analysisStagePhases.keys.toSet(),
        );
      },
    );

    test('the phase mapping is non-decreasing along the chain order', () {
      final stages = buildFullAnalysisStages();

      var previousIndex = -1;
      for (final stage in stages) {
        final phase = analysisStagePhases[stage.id]!;
        expect(phase.index, greaterThanOrEqualTo(previousIndex));
        previousIndex = phase.index;
      }
    });

    test('A3 — a missing stage-id mapping is rejected at construction', () {
      final stages = buildFullAnalysisStages();
      final incompleteMap = Map<String, AnalysisProgressPhase>.of(
        analysisStagePhases,
      )..remove(IngestStageIds.events);

      expect(
        () => AnalysisPipeline<AnalysisWorkState>(
          stages: stages,
          failureClassifier: classifyAnalysisStageFailure,
          stagePhases: incompleteMap,
        ),
        throwsArgumentError,
      );
    });

    test('A4 — a regressing phase mapping is rejected at construction', () {
      final stages = buildFullAnalysisStages();
      final regressingMap = Map<String, AnalysisProgressPhase>.of(
        analysisStagePhases,
      )..[IngestStageIds.events] = AnalysisProgressPhase.validatingInput;

      expect(
        () => AnalysisPipeline<AnalysisWorkState>(
          stages: stages,
          failureClassifier: classifyAnalysisStageFailure,
          stagePhases: regressingMap,
        ),
        throwsArgumentError,
      );
    });

    test('A2 — the full 18-stage chain is accepted with its phase map', () {
      final stages = buildFullAnalysisStages();

      expect(
        () => AnalysisPipeline<AnalysisWorkState>(
          stages: stages,
          failureClassifier: classifyAnalysisStageFailure,
          stagePhases: analysisStagePhases,
        ),
        returnsNormally,
      );
    });

    test(
      'classifyAnalysisStageFailure dispatches to the owning classifier',
      () {
        expect(
          classifyAnalysisStageFailure(
            IngestStageIds.pitch,
            const MlFailure(),
          ).isDegradable,
          classifyIngestStageFailure(
            IngestStageIds.pitch,
            const MlFailure(),
          ).isDegradable,
        );
        expect(
          classifyAnalysisStageFailure(
            EvaluationStageIds.capability,
            const MlFailure(),
          ).isDegradable,
          classifyEvaluationStageFailure(
            EvaluationStageIds.capability,
            const MlFailure(),
          ).isDegradable,
        );
      },
    );
  });
}
