import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_warning.dart';

import 'input_limits.dart';

/// Applies the stable, versioned validation rules at the analysis input boundary.
final class AnalysisInputValidator {
  const AnalysisInputValidator();

  AppResult<void> validateFileByteCount(int byteCount) {
    if (byteCount > InputLimits.maxFileBytes) {
      return const Failure<void>(
        AudioFailure(code: FailureCode.audioFileTooLarge, retryable: false),
      );
    }
    return const Success<void>(null);
  }

  AppResult<void> validatePcmMetadata({
    required int sampleCount,
    required int sampleRate,
    required int channelCount,
  }) {
    if (sampleCount <= 0) {
      return const Failure<void>(
        AudioFailure(code: FailureCode.audioEmptyInput, retryable: false),
      );
    }
    if (sampleRate < InputLimits.minSampleRate ||
        sampleRate > InputLimits.maxSampleRate) {
      return const Failure<void>(
        AudioFailure(
          code: FailureCode.audioInvalidSampleRate,
          retryable: false,
        ),
      );
    }
    if (channelCount <= 0 || channelCount > InputLimits.maxChannels) {
      return const Failure<void>(
        AudioFailure(
          code: FailureCode.audioUnsupportedChannelCount,
          retryable: false,
        ),
      );
    }

    final minSamples = _minimumSampleCount(sampleRate);
    if (sampleCount < minSamples) {
      return const Failure<void>(
        AudioFailure(code: FailureCode.audioClipTooShort, retryable: false),
      );
    }
    final maxSamples = _maximumSampleCount(sampleRate);
    if (sampleCount > maxSamples) {
      return const Failure<void>(
        AudioFailure(code: FailureCode.audioClipTooLong, retryable: false),
      );
    }
    return const Success<void>(null);
  }

  AppResult<ValidatedPcmAnalysisInput> validate(PcmAnalysisInput input) {
    final metadata = validatePcmMetadata(
      sampleCount: input.samples.length,
      sampleRate: input.sampleRate,
      channelCount: input.channelCount,
    );
    if (metadata case Failure<void>(:final error)) {
      return Failure<ValidatedPcmAnalysisInput>(error);
    }

    final firstNonFinite = input.samples.indexWhere(
      (sample) => !sample.isFinite,
    );
    if (firstNonFinite < 0) {
      return Success<ValidatedPcmAnalysisInput>(
        ValidatedPcmAnalysisInput(input: input),
      );
    }
    if (input.source != AnalysisInputSource.microphone) {
      return const Failure<ValidatedPcmAnalysisInput>(
        AudioFailure(code: FailureCode.audioNonFiniteSample, retryable: false),
      );
    }

    final sanitized = List<double>.from(input.samples)..[firstNonFinite] = 0.0;
    for (var index = firstNonFinite + 1; index < sanitized.length; index++) {
      if (!sanitized[index].isFinite) {
        sanitized[index] = 0.0;
      }
    }
    return Success<ValidatedPcmAnalysisInput>(
      ValidatedPcmAnalysisInput(
        input: PcmAnalysisInput(
          samples: sanitized,
          sampleRate: input.sampleRate,
          channelCount: input.channelCount,
          source: input.source,
          sourceDisplayName: input.sourceDisplayName,
        ),
        warnings: <AnalysisWarning>[
          AnalysisWarning(
            kind: AnalysisWarningKind.inputQuality,
            severity: AnalysisWarningSeverity.warning,
            messageKey: FailureCode.audioNonFiniteSample,
          ),
        ],
      ),
    );
  }

  static int _minimumSampleCount(int sampleRate) =>
      (InputLimits.minDuration.inMicroseconds * sampleRate +
          Duration.microsecondsPerSecond -
          1) ~/
      Duration.microsecondsPerSecond;

  static int _maximumSampleCount(int sampleRate) =>
      InputLimits.maxDuration.inMicroseconds *
      sampleRate ~/
      Duration.microsecondsPerSecond;
}
