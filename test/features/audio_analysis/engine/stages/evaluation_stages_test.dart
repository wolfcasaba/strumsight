import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/domain/target/analysis_target.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_cancellation.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_work_state.dart';
import 'package:strumsight/features/audio_analysis/engine/stages/evaluation_stages.dart';

void main() {
  group('evaluation stages (ADR 0251)', () {
    test('A6 — empty expected events never call the EventAligner', () async {
      var callCount = 0;
      final stage = AlignmentEvaluationStage(
        align: ({required observed, required expected, required beatDuration}) {
          callCount += 1;
          throw StateError('The empty-target guard did not run.');
        },
      );
      final state = AnalysisWorkState.seed(
        input: _input(),
        mode: AnalysisMode.practiceTarget,
        target: AnalysisTarget(
          id: 'empty-practice-target',
          kind: AnalysisTargetKind.practice,
          timebase: AnalysisTargetTimebase.session,
        ),
      );

      final result = await stage.run(state, _context());

      expect(result, isA<Success<AnalysisWorkState>>());
      expect((result as Success<AnalysisWorkState>).value.alignment, isNull);
      expect(callCount, 0);
    });
  });
}

ValidatedPcmAnalysisInput _input() => ValidatedPcmAnalysisInput(
  input: PcmAnalysisInput(
    samples: const <double>[0.1, -0.1],
    sampleRate: 44100,
    channelCount: 1,
    source: AnalysisInputSource.practiceSession,
  ),
);

AnalysisStageContext _context() => AnalysisStageContext(
  runId: 'evaluation-stage-test',
  phase: AnalysisProgressPhase.computingMetrics,
  cancellationToken: AnalysisCancellationSource(),
  eventSink: (_) {},
);
