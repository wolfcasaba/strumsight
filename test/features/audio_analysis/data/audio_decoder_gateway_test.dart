import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  const gateway = AudioDecoderGateway();

  group('AudioDecoderGateway', () {
    test(
      'decodes supported WAV format matrix and preserves channel metadata',
      () {
        for (final specification in <_WavSpecification>[
          const _WavSpecification(format: 1, bitsPerSample: 16, channels: 1),
          const _WavSpecification(format: 1, bitsPerSample: 16, channels: 2),
          const _WavSpecification(format: 3, bitsPerSample: 32, channels: 1),
          const _WavSpecification(format: 3, bitsPerSample: 32, channels: 2),
        ]) {
          final result = gateway.decode(
            FileAnalysisInput(
              bytes: _wav(specification),
              sourceDisplayName: const SourceDisplayName('private-take.wav'),
            ),
          );

          expect(
            result,
            isA<Success<DecodedAudio>>(),
            reason: '$specification',
          );
          final audio = (result as Success<DecodedAudio>).value;
          expect(audio.channelCount, specification.channels);
          expect(audio.samples, hasLength(12000));
          expect(audio.samples.every((sample) => sample.isFinite), isTrue);
        }
      },
    );

    test(
      'maps unsupported format and bit depth to distinct typed failures',
      () {
        final unsupportedBitDepth = gateway.decode(
          FileAnalysisInput(
            bytes: _wav(const _WavSpecification(format: 1, bitsPerSample: 8)),
          ),
        );
        final unsupported24BitDepth = gateway.decode(
          FileAnalysisInput(
            bytes: _wav(const _WavSpecification(format: 1, bitsPerSample: 24)),
          ),
        );
        final unsupportedFormat = gateway.decode(
          FileAnalysisInput(
            bytes: _wav(const _WavSpecification(format: 2, bitsPerSample: 16)),
          ),
        );

        expect(
          _failureCode(unsupportedBitDepth),
          FailureCode.unsupportedBitDepth,
        );
        expect(
          _failureCode(unsupported24BitDepth),
          FailureCode.unsupportedBitDepth,
        );
        expect(_failureCode(unsupportedFormat), FailureCode.unsupportedFormat);
      },
    );

    test('rejects malformed RIFF structures without throwing', () {
      final cases = <String, _MalformedCase>{
        'non RIFF header': _MalformedCase(
          Uint8List.fromList('NOPE'.codeUnits),
          FailureCode.invalidRiff,
        ),
        'non WAVE form': _MalformedCase(
          _wav(const _WavSpecification())..setRange(8, 12, 'NOPE'.codeUnits),
          FailureCode.invalidRiff,
        ),
        'truncated fmt': _MalformedCase(
          _riffWithChunk('fmt ', 16, const <int>[1, 2]),
          FailureCode.truncatedChunk,
        ),
        'truncated data': _MalformedCase(
          _riffWithChunk('data', 4, const <int>[1, 2]),
          FailureCode.chunkSizeOutOfBounds,
        ),
        'declared data beyond bytes': _MalformedCase(
          _riffWithChunk('data', 16, const <int>[1, 2]),
          FailureCode.chunkSizeOutOfBounds,
        ),
        'overflow chunk size': _MalformedCase(
          _riffWithChunk('data', 0xFFFFFFFF, const <int>[]),
          FailureCode.chunkSizeOutOfBounds,
        ),
      };

      for (final entry in cases.entries) {
        expect(
          () => gateway.decode(FileAnalysisInput(bytes: entry.value.bytes)),
          returnsNormally,
          reason: entry.key,
        );
        expect(
          gateway.decode(FileAnalysisInput(bytes: entry.value.bytes)),
          isA<Failure<DecodedAudio>>(),
          reason: entry.key,
        );
        expect(
          _failureCode(
            gateway.decode(FileAnalysisInput(bytes: entry.value.bytes)),
          ),
          entry.value.failureCode,
          reason: entry.key,
        );
      }
    });

    test('enforces an inclusive file-size limit before decoding', () {
      expect(
        AudioDecoderGateway.isAllowedFileSize(InputLimits.maxFileBytes - 1),
        isTrue,
      );
      expect(
        AudioDecoderGateway.isAllowedFileSize(InputLimits.maxFileBytes),
        isTrue,
      );
      expect(
        AudioDecoderGateway.isAllowedFileSize(InputLimits.maxFileBytes + 1),
        isFalse,
      );
      final tooLarge = gateway.decode(
        FileAnalysisInput(bytes: Uint8List(InputLimits.maxFileBytes + 1)),
      );
      expect(_failureCode(tooLarge), FailureCode.fileTooLarge);
    });

    test('never sends source display names to a logger', () {
      final input = FileAnalysisInput(
        bytes: _wav(const _WavSpecification()),
        sourceDisplayName: const SourceDisplayName('my-private-take.wav'),
      );

      gateway.decode(input);

      expect(
        input.sourceDisplayName.toString(),
        isNot(contains('my-private-take.wav')),
      );
      expect(input.sourceDisplayName!.redacted, isTrue);
    });
  });
}

String _failureCode(AppResult<DecodedAudio> result) =>
    (result as Failure<DecodedAudio>).error.code;

final class _WavSpecification {
  const _WavSpecification({
    this.format = 1,
    this.bitsPerSample = 16,
    this.channels = 1,
  });

  final int format;
  final int bitsPerSample;
  final int channels;

  @override
  String toString() => 'format=$format bits=$bitsPerSample channels=$channels';
}

final class _MalformedCase {
  const _MalformedCase(this.bytes, this.failureCode);

  final Uint8List bytes;
  final String failureCode;
}

Uint8List _wav(_WavSpecification specification) {
  final bytesPerSample = specification.bitsPerSample ~/ 8;
  const frames = 12000;
  final dataLength = frames * specification.channels * bytesPerSample;
  final data = ByteData(44 + dataLength);
  _tag(data, 0, 'RIFF');
  data.setUint32(4, 36 + dataLength, Endian.little);
  _tag(data, 8, 'WAVE');
  _tag(data, 12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, specification.format, Endian.little);
  data.setUint16(22, specification.channels, Endian.little);
  data.setUint32(24, 48000, Endian.little);
  data.setUint32(
    28,
    48000 * specification.channels * bytesPerSample,
    Endian.little,
  );
  data.setUint16(32, specification.channels * bytesPerSample, Endian.little);
  data.setUint16(34, specification.bitsPerSample, Endian.little);
  _tag(data, 36, 'data');
  data.setUint32(40, dataLength, Endian.little);
  for (var offset = 44; offset < 44 + dataLength; offset += bytesPerSample) {
    if (specification.bitsPerSample == 32) {
      data.setFloat32(offset, .5, Endian.little);
    } else if (specification.bitsPerSample == 16) {
      data.setInt16(offset, 16384, Endian.little);
    }
  }
  return data.buffer.asUint8List();
}

Uint8List _riffWithChunk(String id, int declaredSize, List<int> body) {
  final data = ByteData(20 + body.length);
  _tag(data, 0, 'RIFF');
  data.setUint32(4, 12 + body.length, Endian.little);
  _tag(data, 8, 'WAVE');
  _tag(data, 12, id);
  data.setUint32(16, declaredSize, Endian.little);
  data.buffer.asUint8List().setRange(20, 20 + body.length, body);
  return data.buffer.asUint8List();
}

void _tag(ByteData data, int offset, String value) =>
    data.buffer.asUint8List().setRange(offset, offset + 4, value.codeUnits);
