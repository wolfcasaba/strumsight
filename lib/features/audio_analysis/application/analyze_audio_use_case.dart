import '../domain/analysis_document.dart';
import '../domain/analysis_input.dart';
import 'analysis_isolate_runner.dart';

/// Starts an injected V2 document pipeline. The composition root owns the
/// stage list; this use case deliberately has no DSP policy of its own.
///
/// [call] takes the document seed and, since E17-R02, the validated PCM the
/// chain actually analyses. The capture flow
/// (`analysis_capture_providers.dart`) always passes [audio]; when it is
/// omitted (the pre-E17-R02 callers, ADR 0254) the seed is wrapped in an
/// empty, in-memory-only [ValidatedPcmAnalysisInput] so the
/// [AnalysisRunRequest] contract is still satisfied.
final class AnalyzeAudioUseCase {
  const AnalyzeAudioUseCase(this._runner);

  final AnalysisRunner _runner;

  AnalysisRunHandle call(
    AnalysisDocument input, {
    ValidatedPcmAnalysisInput? audio,
  }) => _runner.start(
    AnalysisRunRequest(seed: input, audio: audio ?? _placeholderAudio(input)),
  );

  ValidatedPcmAnalysisInput _placeholderAudio(AnalysisDocument input) =>
      ValidatedPcmAnalysisInput(
        input: PcmAnalysisInput(
          samples: const <double>[],
          sampleRate: input.input.sampleRate,
          channelCount: input.input.channelCount,
          source: input.input.source,
        ),
      );
}
