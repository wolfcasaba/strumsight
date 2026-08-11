// ignore_for_file: depend_on_referenced_packages

import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_cancellation.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_pipeline.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_stage.dart';
import '../support/fake_analysis_stages.dart';
import 'package:test/test.dart';

void main() {
  test(
    'progress phases are strictly monotonic for deterministic random stage assemblies',
    () async {
      var seed = 0x5EED;
      for (var sample = 0; sample < 80; sample++) {
        seed = _next(seed);
        final count = (seed % AnalysisProgressPhase.values.length) + 1;
        final pipeline = AnalysisPipeline<int>(
          stages: List<AnalysisStage<int, int>>.generate(
            count,
            (index) => FakeAnalysisStage(
              id: 'sample-$sample-stage-$index',
              emitProgress: index.isEven,
            ),
          ),
        );
        final run = pipeline.start(
          0,
          cancellationToken: AnalysisCancellationSource(),
        );
        final events = await run.progress.toList();
        await run.result;
        final phases = events
            .whereType<AnalysisPhaseProgressEvent>()
            .map((event) => event.phase.index)
            .toList();

        expect(phases, hasLength(count));
        for (var index = 1; index < phases.length; index++) {
          expect(phases[index], greaterThan(phases[index - 1]));
        }
      }
    },
  );
}

int _next(int value) => (value * 1103515245 + 12345) & 0x7fffffff;
