import '../domain/analysis_document.dart';
import '../domain/analysis_input.dart';
import 'analysis_isolate_runner.dart';

/// Starts an injected V2 document pipeline. The composition root owns the
/// stage list; this use case deliberately has no DSP policy of its own.
///
/// [call] still takes only a document: [AnalysisController] (out of this
/// round's scope, ADR 0254) has no real audio source wired yet, so this seam
/// wraps the seed in an empty, in-memory-only [ValidatedPcmAnalysisInput] to
/// satisfy [AnalysisRunner.start]'s [AnalysisRunRequest] contract. A future
/// round that plumbs real capture audio into the controller replaces this
/// placeholder with the caller's actual PCM.
final class AnalyzeAudioUseCase {
  const AnalyzeAudioUseCase(this._runner);

  final AnalysisRunner _runner;

  AnalysisRunHandle call(AnalysisDocument input) => _runner.start(
    AnalysisRunRequest(seed: input, audio: _placeholderAudio(input)),
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
