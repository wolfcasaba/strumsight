import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_stage.dart';

/// Deterministic integer stage for pipeline-contract tests.
///
/// Tests drive cancellation through [onStarted] or [onCompleted]; no timer or
/// ambient clock is involved. A configured [failure] is returned as an
/// [AppResult] value, just as a production stage must do for expected errors.
final class FakeAnalysisStage implements AnalysisStage<int, int> {
  FakeAnalysisStage({
    required this.id,
    this.version = 1,
    this.increment = 1,
    this.failure,
    this.checkCancellation = false,
    this.emitProgress = true,
    this.onStarted,
    this.onCompleted,
    this.runOrder,
  });

  @override
  final String id;

  @override
  final int version;

  final int increment;
  final AppFailure? failure;
  final bool checkCancellation;
  final bool emitProgress;
  final void Function(AnalysisStageContext context)? onStarted;
  final void Function(AnalysisStageContext context)? onCompleted;
  final List<String>? runOrder;

  int calls = 0;
  int completedCheckpoints = 0;
  AnalysisStageContext? lastContext;

  @override
  Future<AppResult<int>> run(int input, AnalysisStageContext context) async {
    calls++;
    runOrder?.add(id);
    lastContext = context;
    onStarted?.call(context);

    if (emitProgress) context.reportProgress();

    if (checkCancellation) {
      for (var checkpoint = 0; checkpoint < 3; checkpoint++) {
        context.cancellationToken.throwIfCancelled();
        completedCheckpoints++;
      }
    }

    onCompleted?.call(context);
    if (failure != null) return AppResult<int>.failure(failure!);
    return AppResult<int>.success(input + increment);
  }
}
