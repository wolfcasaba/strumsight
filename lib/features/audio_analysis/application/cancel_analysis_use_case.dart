import 'analysis_isolate_runner.dart';

/// Cancels exactly the handle supplied by the controller's active run.
final class CancelAnalysisUseCase {
  const CancelAnalysisUseCase();

  Future<void> call(AnalysisRunHandle run) => run.cancel();
}
