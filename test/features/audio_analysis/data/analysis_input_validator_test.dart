import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  const validator = AnalysisInputValidator();

  PcmAnalysisInput input(
    Float32List values, {
    AnalysisInputSource source = AnalysisInputSource.microphone,
  }) => PcmAnalysisInput(
    samples: values,
    sampleRate: 48000,
    channelCount: 1,
    source: source,
  );

  test('accepts inclusive duration boundaries', () {
    expect(
      validator.validate(input(Float32List(11999))),
      isA<Failure<ValidatedAnalysisInput>>(),
    );
    expect(
      validator.validate(input(Float32List(12000))),
      isA<Success<ValidatedAnalysisInput>>(),
    );
    expect(
      validator.validate(input(Float32List(12001))),
      isA<Success<ValidatedAnalysisInput>>(),
    );
    expect(
      validator.validate(input(Float32List(28799999))),
      isA<Success<ValidatedAnalysisInput>>(),
    );
    expect(
      validator.validate(input(Float32List(28800000))),
      isA<Success<ValidatedAnalysisInput>>(),
    );
    expect(
      validator.validate(input(Float32List(28800001))),
      isA<Failure<ValidatedAnalysisInput>>(),
    );
  });

  test('reports named duration failures', () {
    expect(
      _code(validator.validate(input(Float32List(11999)))),
      FailureCode.clipTooShort,
    );
    expect(
      _code(validator.validate(input(Float32List(28800001)))),
      FailureCode.clipTooLong,
    );
  });

  test('rejects non-finite imported samples', () {
    for (final value in <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      final samples = Float32List(12000)..[11999] = value;
      expect(
        _importedCode(
          validator.validateImported(
            DecodedAudio(
              samples: samples,
              sampleRate: 48000,
              channelCount: 1,
              source: AnalysisInputSource.importedFile,
            ),
          ),
        ),
        FailureCode.nonFiniteSample,
      );
    }
  });

  test('sanitizes non-finite microphone samples with a warning', () {
    for (final value in <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      final samples = Float32List(12000)
        ..fillRange(0, 12000, .5)
        ..[0] = .125
        ..[1] = value
        ..[2] = -.25;
      final result = validator.validate(input(samples));
      expect(result, isA<Success<ValidatedAnalysisInput>>());
      final validated = (result as Success<ValidatedAnalysisInput>).value;
      expect(validated.warningCodes, contains(FailureCode.nonFiniteSample));
      expect(validated.input.samples[0], .125);
      expect(validated.input.samples[1], 0);
      expect(validated.input.samples[2], -.25);
    }
  });
}

String _code(AppResult<ValidatedAnalysisInput> result) =>
    (result as Failure<ValidatedAnalysisInput>).error.code;

String _importedCode(AppResult<DecodedAudio> result) =>
    (result as Failure<DecodedAudio>).error.code;
