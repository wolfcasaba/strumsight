// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_cancellation.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_pipeline.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_stage.dart';
import '../../../support/fake_analysis_stages.dart';
import 'package:test/test.dart';

void main() {
  group('AnalysisPipeline', () {
    test(
      'runs stages in order and records every stage version and timing',
      () async {
        final runOrder = <String>[];
        final pipeline = AnalysisPipeline<int>(
          stages: List<AnalysisStage<int, int>>.generate(
            5,
            (index) => FakeAnalysisStage(
              id: 'stage-$index',
              version: index + 1,
              runOrder: runOrder,
            ),
          ),
        );

        final observation = await _observe(
          pipeline.start(0, cancellationToken: AnalysisCancellationSource()),
        );

        expect(
          observation.result.completion,
          AnalysisCompletionStatus.complete,
        );
        expect(observation.result.value, 5);
        expect(runOrder, <String>[
          'stage-0',
          'stage-1',
          'stage-2',
          'stage-3',
          'stage-4',
        ]);
        expect(observation.result.provenance.stageVersions, <String, String>{
          'stage-0': '1',
          'stage-1': '2',
          'stage-2': '3',
          'stage-3': '4',
          'stage-4': '5',
        });
        expect(observation.result.provenance.stageTimings, hasLength(5));
        expect(
          observation.result.provenance.stageTimings.map((timing) => timing.id),
          runOrder,
        );
      },
    );

    for (final cancellationCase
        in <
          ({
            String name,
            List<FakeAnalysisStage> Function(AnalysisCancellationSource source)
            stages,
            void Function(List<FakeAnalysisStage> stages) verify,
          })
        >[
          (
            name: 'before the first stage',
            stages: (source) {
              source.cancel();
              return <FakeAnalysisStage>[FakeAnalysisStage(id: 'first')];
            },
            verify: (_) {},
          ),
          (
            name: 'between two stages',
            stages: (source) => <FakeAnalysisStage>[
              FakeAnalysisStage(
                id: 'first',
                onCompleted: (_) => source.cancel(),
              ),
              FakeAnalysisStage(id: 'second'),
            ],
            verify: (_) {},
          ),
          (
            name: 'during a stage checkpoint',
            stages: (source) => <FakeAnalysisStage>[
              FakeAnalysisStage(
                id: 'first',
                checkCancellation: true,
                onStarted: (_) => source.cancel(),
              ),
            ],
            verify: (stages) => expect(stages.single.completedCheckpoints, 0),
          ),
          (
            name: 'after the final stage before result publication',
            stages: (source) => <FakeAnalysisStage>[
              FakeAnalysisStage(
                id: 'last',
                onCompleted: (_) => source.cancel(),
              ),
            ],
            verify: (_) {},
          ),
        ]) {
      test(
        'cancellation $cancellationCase.name publishes no result and closes progress',
        () async {
          final source = AnalysisCancellationSource();
          final stages = cancellationCase.stages(source);
          final pipeline = AnalysisPipeline<int>(stages: stages);

          final observation = await _observe(
            pipeline.start(0, cancellationToken: source),
          );

          expect(
            observation.result.completion,
            AnalysisCompletionStatus.cancelled,
          );
          expect(observation.result.value, isNull);
          expect(
            observation.events.whereType<AnalysisRunResultEvent>(),
            isEmpty,
          );
          expect(observation.isProgressClosed, isTrue);
          cancellationCase.verify(stages);
        },
      );
    }

    test(
      'continues after a degradable stage failure with a warning and unavailable capability',
      () async {
        final failedStage = FakeAnalysisStage(
          id: 'harmony',
          failure: const MlFailure(),
        );
        final followingStage = FakeAnalysisStage(id: 'metrics');
        final pipeline = AnalysisPipeline<int>(
          stages: <AnalysisStage<int, int>>[failedStage, followingStage],
          failureClassifier: (_, failure) => StageFailure.degradable(
            failure,
            unavailableCapabilities: const <AnalysisCapability>{
              AnalysisCapability.chordTimeline,
            },
          ),
        );

        final observation = await _observe(
          pipeline.start(0, cancellationToken: AnalysisCancellationSource()),
        );

        expect(
          observation.result.completion,
          AnalysisCompletionStatus.degraded,
        );
        expect(observation.result.warnings, hasLength(1));
        expect(observation.result.stageOutputs.containsKey('harmony'), isFalse);
        expect(observation.result.stageOutputs['metrics'], 1);
        expect(
          observation.result.unavailableCapabilities,
          contains(AnalysisCapability.chordTimeline),
        );
        expect(followingStage.calls, 1);
      },
    );

    test(
      'stops after a fatal stage failure without running the following stage',
      () async {
        final followingStage = FakeAnalysisStage(id: 'must-not-run');
        final pipeline = AnalysisPipeline<int>(
          stages: <AnalysisStage<int, int>>[
            FakeAnalysisStage(id: 'fails', failure: const MlFailure()),
            followingStage,
          ],
        );

        final observation = await _observe(
          pipeline.start(0, cancellationToken: AnalysisCancellationSource()),
        );

        expect(observation.result.completion, AnalysisCompletionStatus.failed);
        expect(observation.result.value, isNull);
        expect(followingStage.calls, 0);
      },
    );

    test(
      'drops late progress and result events from an inactive run',
      () async {
        final source = AnalysisCancellationSource();
        final firstStage = FakeAnalysisStage(
          id: 'first',
          checkCancellation: true,
          onStarted: (_) => source.cancel(),
        );
        final pipeline = AnalysisPipeline<int>(
          stages: <AnalysisStage<int, int>>[firstStage],
        );

        await _observe(pipeline.start(0, cancellationToken: source));
        final secondRun = pipeline.start(
          0,
          cancellationToken: AnalysisCancellationSource(),
        );
        final staleContext = firstStage.lastContext!;

        staleContext.reportProgress();
        staleContext.publishResult(AnalysisCompletionStatus.complete);

        await _observe(secondRun);
        expect(pipeline.droppedLateEvents, 2);
      },
    );

    test('rejects duplicate stage IDs at pipeline construction', () {
      expect(
        () => AnalysisPipeline<int>(
          stages: <AnalysisStage<int, int>>[
            FakeAnalysisStage(id: 'duplicate'),
            FakeAnalysisStage(id: 'duplicate'),
          ],
        ),
        throwsArgumentError,
      );
    });
  });
}

Future<_RunObservation> _observe(AnalysisPipelineRun<int> run) async {
  var closed = false;
  final events = <AnalysisProgressEvent>[];
  final done = Completer<void>();
  final subscription = run.progress.listen(
    events.add,
    onDone: () {
      closed = true;
      done.complete();
    },
  );
  final result = await run.result;
  await done.future;
  await subscription.cancel();
  return _RunObservation(
    result: result,
    events: events,
    isProgressClosed: closed,
  );
}

final class _RunObservation {
  const _RunObservation({
    required this.result,
    required this.events,
    required this.isProgressClosed,
  });

  final AnalysisPipelineResult<int> result;
  final List<AnalysisProgressEvent> events;
  final bool isProgressClosed;
}
