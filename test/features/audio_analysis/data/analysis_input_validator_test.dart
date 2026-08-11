import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/data/input/analysis_input_validator.dart';
import 'package:strumsight/features/audio_analysis/data/input/input_limits.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';

void main() {
  const validator = AnalysisInputValidator();

  test('file-size limit is inclusive at 64 MiB', () {
    // Generated with `python3 -c 'n = 64 * 1024 * 1024; print(n - 1, n, n + 1)'`.
    for (final byteCount in <int>[67108863, 67108864]) {
      expect(validator.validateFileByteCount(byteCount), isA<Success<void>>());
    }
    _expectFailure(
      validator.validateFileByteCount(67108865),
      FailureCode.audioFileTooLarge,
    );
    expect(InputLimits.maxFileBytes, 67108864);
  });

  test('duration limits include 12000 and 28800000 samples at 48 kHz', () {
    // Generated with `python3 -c 'print(48000 * 250 // 1000, 48000 * 600)'`.
    _expectFailure(
      validator.validatePcmMetadata(
        sampleCount: 11999,
        sampleRate: 48000,
        channelCount: 1,
      ),
      FailureCode.audioClipTooShort,
    );
    for (final sampleCount in <int>[12000, 12001, 28799999, 28800000]) {
      expect(
        validator.validatePcmMetadata(
          sampleCount: sampleCount,
          sampleRate: 48000,
          channelCount: 1,
        ),
        isA<Success<void>>(),
      );
    }
    _expectFailure(
      validator.validatePcmMetadata(
        sampleCount: 28800001,
        sampleRate: 48000,
        channelCount: 1,
      ),
      FailureCode.audioClipTooLong,
    );
  });

  test(
    'rejects empty PCM, out-of-range metadata, and imported non-finite PCM',
    () {
      _expectFailure(
        validator.validatePcmMetadata(
          sampleCount: 0,
          sampleRate: 48000,
          channelCount: 1,
        ),
        FailureCode.audioEmptyInput,
      );
      _expectFailure(
        validator.validatePcmMetadata(
          sampleCount: 12000,
          sampleRate: 7999,
          channelCount: 1,
        ),
        FailureCode.audioInvalidSampleRate,
      );
      _expectFailure(
        validator.validatePcmMetadata(
          sampleCount: 12000,
          sampleRate: 192001,
          channelCount: 1,
        ),
        FailureCode.audioInvalidSampleRate,
      );
      _expectFailure(
        validator.validatePcmMetadata(
          sampleCount: 12000,
          sampleRate: 48000,
          channelCount: 3,
        ),
        FailureCode.audioUnsupportedChannelCount,
      );

      for (final nonFinite in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        _expectFailure(
          validator.validate(
            PcmAnalysisInput(
              samples: _samplesWith(nonFinite),
              sampleRate: 48000,
              channelCount: 1,
              source: AnalysisInputSource.importedFile,
            ),
          ),
          FailureCode.audioNonFiniteSample,
        );
      }
    },
  );

  test(
    'sanitizes microphone non-finite PCM with a warning and no other mutation',
    () {
      for (final nonFinite in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final result = validator.validate(
          PcmAnalysisInput(
            samples: _samplesWith(
              nonFinite,
              prefix: <double>[0.25, nonFinite, -0.5],
            ),
            sampleRate: 48000,
            channelCount: 1,
            source: AnalysisInputSource.microphone,
          ),
        );

        expect(result, isA<Success<ValidatedPcmAnalysisInput>>());
        final validated = (result as Success<ValidatedPcmAnalysisInput>).value;
        expect(validated.input.samples.take(3), <double>[0.25, 0.0, -0.5]);
        expect(
          validated.input.samples.skip(3).every((sample) => sample == 0.0),
          isTrue,
        );
        expect(
          validated.warnings.single.messageKey,
          FailureCode.audioNonFiniteSample,
        );
        expect(validated.warnings.single.severity.name, 'warning');
      }
    },
  );

  test('redacts source display names in diagnostic string representations', () {
    const privateName = 'alice-private-session.wav';
    final input = FileAnalysisInput(
      bytes: const <int>[1, 2, 3],
      source: AnalysisInputSource.importedFile,
      sourceDisplayName: const SourceDisplayName(privateName),
    );

    expect(input.sourceDisplayName!.redacted, isTrue);
    expect(input.toString(), isNot(contains(privateName)));
    expect(input.sourceDisplayName.toString(), isNot(contains(privateName)));
  });
}

void _expectFailure<T>(AppResult<T> result, String code) {
  expect(result, isA<Failure<T>>());
  expect((result as Failure<T>).error.code, code);
}

List<double> _samplesWith(
  double nonFinite, {
  List<double> prefix = const <double>[0, double.nan, 0],
}) {
  final samples = List<double>.filled(12000, 0.0)
    ..setRange(0, prefix.length, prefix)
    ..[1] = nonFinite;
  return samples;
}
