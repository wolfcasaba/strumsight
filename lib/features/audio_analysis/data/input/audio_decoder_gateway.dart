import 'package:strumsight/core/audio/codec/wav_decoder.dart' show DecodedAudio;
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';

/// Converts a file input to validated PCM without exposing nullable decode state.
abstract interface class AudioDecoderGateway {
  AppResult<DecodedAudio> decode(FileAnalysisInput input);
}
