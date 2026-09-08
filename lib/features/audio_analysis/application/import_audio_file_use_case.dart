import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';

import '../data/input/analysis_audio_file_picker.dart';
import '../data/input/wav_decoder_adapter.dart';
import '../domain/analysis_input.dart';
import '../domain/analysis_mode.dart';

/// What one "Import file" attempt produced.
///
/// A sealed outcome instead of a nullable PCM value: cancel, "this build
/// cannot decode that container", and "the file is a WAV but a broken one"
/// are three different things to say to the user, and a nullable return would
/// have collapsed all three into the same silence.
sealed class AudioFileImportOutcome {
  const AudioFileImportOutcome();
}

/// The user dismissed the picker. Nothing to report — not a failure.
final class AudioFileImportCancelled extends AudioFileImportOutcome {
  const AudioFileImportCancelled();
}

/// The chosen container is not one this build can decode to PCM.
final class AudioFileImportUnsupported extends AudioFileImportOutcome {
  const AudioFileImportUnsupported(this.extension);

  /// Lower-case extension of the chosen file, or null when it had none.
  final String? extension;
}

/// The container was decodable in principle, but this file was rejected at
/// the input boundary (bad RIFF, unsupported bit depth, too large, too long…).
final class AudioFileImportFailed extends AudioFileImportOutcome {
  const AudioFileImportFailed(this.failure);

  final AppFailure failure;
}

/// Decoded, validated PCM ready for the SAME pipeline a recording feeds.
final class AudioFileImportReady extends AudioFileImportOutcome {
  const AudioFileImportReady(this.audio);

  /// Carries the imported file name in its `sourceDisplayName` — the only
  /// provenance the document keeps (see `AnalysisInputSummary.sourceName`,
  /// which the export codec's allowlist deliberately omits).
  final PcmAnalysisInput audio;
}

/// Picks an audio file and decodes it to PCM at the analysis input boundary.
///
/// It deliberately performs NO analysis: the decoded PCM is handed back so the
/// caller can start the identical `AnalysisController.analyze` run a
/// microphone capture starts. The pipeline never learns where the samples
/// came from beyond the `AnalysisInputSource` enum on the input itself.
final class ImportAudioFileUseCase {
  const ImportAudioFileUseCase({
    required AnalysisAudioFilePicker picker,
    WavDecoderAdapter decoder = const WavDecoderAdapter(),
  }) : _picker = picker,
       _decoder = decoder;

  final AnalysisAudioFilePicker _picker;
  final WavDecoderAdapter _decoder;

  Future<AudioFileImportOutcome> call() async {
    PickedAudioFile? picked;
    try {
      picked = await _picker.pickAnalysisAudioFile();
    } on Object catch (error, stackTrace) {
      // A platform picker can throw (no activity, a revoked content URI, an
      // unreadable file). Swallowing it would leave the CTA looking dead —
      // the same defect the honest "not available yet" snackbar existed for.
      return AudioFileImportFailed(
        UnknownFailure(cause: error, stackTrace: stackTrace),
      );
    }
    if (picked == null) return const AudioFileImportCancelled();

    final extension = picked.extension;
    const decodable = PlatformAnalysisAudioFilePicker.decodableExtensions;
    if (extension == null || !decodable.contains(extension)) {
      return AudioFileImportUnsupported(extension);
    }

    final decoded = _decoder.decodeInput(
      FileAnalysisInput(
        bytes: picked.bytes,
        source: AnalysisInputSource.importedFile,
        sourceDisplayName: SourceDisplayName(picked.displayName),
      ),
    );
    return switch (decoded) {
      Success<PcmAnalysisInput>(:final value) => AudioFileImportReady(value),
      Failure<PcmAnalysisInput>(:final error) => AudioFileImportFailed(error),
    };
  }
}
