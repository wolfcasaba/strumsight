import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/data/input/analysis_input_validator.dart';
import 'package:strumsight/features/audio_analysis/data/input/input_limits.dart';
import 'package:strumsight/features/audio_analysis/data/input/wav_decoder_adapter.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';

/// The safe import entry point. It deliberately does not receive a logger: a
/// user-provided display name must not reach diagnostics by accident.
final class AudioDecoderGateway {
  const AudioDecoderGateway({
    this.adapter = const WavDecoderAdapter(),
    this.validator = const AnalysisInputValidator(),
  });

  final WavDecoderAdapter adapter;
  final AnalysisInputValidator validator;

  static bool isAllowedFileSize(int bytes) =>
      bytes >= 0 && bytes <= InputLimits.maxFileBytes;

  AppResult<DecodedAudio> decode(FileAnalysisInput input) {
    if (!isAllowedFileSize(input.bytes.length)) {
      return const Failure<DecodedAudio>(
        ValidationFailure(code: FailureCode.fileTooLarge),
      );
    }
    final decoded = adapter.decode(input.bytes);
    if (decoded case Failure<DecodedAudio>(:final error)) {
      return Failure<DecodedAudio>(error);
    }
    return validator.validateImported((decoded as Success<DecodedAudio>).value);
  }
}
