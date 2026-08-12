import '../domain/analysis_document.dart';
import 'analysis_isolate_runner.dart';

/// Starts an injected V2 document pipeline. The composition root owns the
/// stage list; this use case deliberately has no DSP policy of its own.
final class AnalyzeAudioUseCase {
  const AnalyzeAudioUseCase(this._runner);

  final AnalysisRunner _runner;

  AnalysisRunHandle call(AnalysisDocument input) => _runner.start(input);
}
