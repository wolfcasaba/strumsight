import 'dart:typed_data';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/data/input/input_limits.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';

/// Enforces the versioned PCM limits at the analysis trust boundary.
final class AnalysisInputValidator {
  const AnalysisInputValidator();

  AppResult<ValidatedAnalysisInput> validate(PcmAnalysisInput input) {
    final metadataFailure = _metadataFailure(
      sampleCount: input.samples.length,
      sampleRate: input.sampleRate,
      channelCount: input.channelCount,
    );
    if (metadataFailure != null) {
      return Failure<ValidatedAnalysisInput>(metadataFailure);
    }

    final nonFiniteIndex = _firstNonFinite(input.samples);
    if (nonFiniteIndex == null) {
      return Success<ValidatedAnalysisInput>(
        ValidatedAnalysisInput(input: input),
      );
    }
    if (input.source != AnalysisInputSource.microphone) {
      return const Failure<ValidatedAnalysisInput>(
        ValidationFailure(code: FailureCode.nonFiniteSample),
      );
    }

    final sanitized = Float32List.fromList(input.samples);
    for (var index = nonFiniteIndex; index < sanitized.length; index++) {
      if (!sanitized[index].isFinite) sanitized[index] = 0;
    }
    return Success<ValidatedAnalysisInput>(
      ValidatedAnalysisInput(
        input: PcmAnalysisInput(
          samples: sanitized,
          sampleRate: input.sampleRate,
          channelCount: input.channelCount,
          source: input.source,
          sourceDisplayName: input.sourceDisplayName,
        ),
        warningCodes: const <String>[FailureCode.nonFiniteSample],
      ),
    );
  }

  /// Imported audio is rejected, never sanitized, when its PCM is non-finite.
  AppResult<DecodedAudio> validateImported(DecodedAudio audio) {
    final metadataFailure = _metadataFailure(
      sampleCount: audio.samples.length,
      sampleRate: audio.sampleRate,
      channelCount: audio.channelCount,
    );
    if (metadataFailure != null) return Failure<DecodedAudio>(metadataFailure);
    if (audio.source != AnalysisInputSource.importedFile ||
        _firstNonFinite(audio.samples) != null) {
      return const Failure<DecodedAudio>(
        ValidationFailure(code: FailureCode.nonFiniteSample),
      );
    }
    return Success<DecodedAudio>(audio);
  }

  AppFailure? _metadataFailure({
    required int sampleCount,
    required int sampleRate,
    required int channelCount,
  }) {
    if (sampleCount == 0 ||
        sampleRate < InputLimits.minSampleRate ||
        sampleRate > InputLimits.maxSampleRate ||
        channelCount < 1 ||
        channelCount > InputLimits.maxChannels) {
      return const ValidationFailure(code: FailureCode.validationInvalidInput);
    }
    if (sampleCount * Duration.microsecondsPerSecond <
        sampleRate * InputLimits.minDuration.inMicroseconds) {
      return const ValidationFailure(code: FailureCode.clipTooShort);
    }
    if (sampleCount * Duration.microsecondsPerSecond >
        sampleRate * InputLimits.maxDuration.inMicroseconds) {
      return const ValidationFailure(code: FailureCode.clipTooLong);
    }
    return null;
  }

  int? _firstNonFinite(Float32List samples) {
    for (var index = 0; index < samples.length; index++) {
      if (!samples[index].isFinite) return index;
    }
    return null;
  }
}
