import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/data/input/audio_decoder_gateway.dart';
import 'package:strumsight/features/audio_analysis/data/input/wav_decoder_adapter.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';

void main() {
  const decoder = WavDecoderAdapter();

  test('gateway returns a typed, non-null decode result', () {
    const AudioDecoderGateway gateway = WavDecoderAdapter();

    expect(gateway.decode(_file(_wav())).isSuccess, isTrue);
  });

  group('WavDecoderAdapter format matrix', () {
    for (final format in <_FormatCase>[
      const _FormatCase('16-bit mono PCM', format: 1, bitsPerSample: 16),
      const _FormatCase(
        '16-bit stereo PCM',
        format: 1,
        bitsPerSample: 16,
        channels: 2,
      ),
      const _FormatCase('32-bit mono float', format: 3, bitsPerSample: 32),
      const _FormatCase(
        '32-bit stereo float',
        format: 3,
        bitsPerSample: 32,
        channels: 2,
      ),
    ]) {
      test('decodes ${format.label}', () {
        final result = decoder.decodeInput(_file(_wav(format: format)));

        expect(result, isA<Success<PcmAnalysisInput>>());
        final input = (result as Success<PcmAnalysisInput>).value;
        expect(input.channelCount, format.channels);
        expect(input.samples, hasLength(12000));
        expect(input.samples.every((sample) => sample.isFinite), isTrue);
      });
    }

    test('rejects 8-bit PCM with unsupportedBitDepth', () {
      _expectFailure(
        decoder.decodeInput(
          _file(
            _wav(
              format: const _FormatCase(
                '8-bit PCM',
                format: 1,
                bitsPerSample: 8,
              ),
            ),
          ),
        ),
        FailureCode.audioUnsupportedBitDepth,
      );
    });

    test('rejects 24-bit PCM with unsupportedBitDepth', () {
      _expectFailure(
        decoder.decodeInput(
          _file(
            _wav(
              format: const _FormatCase(
                '24-bit PCM',
                format: 1,
                bitsPerSample: 24,
              ),
            ),
          ),
        ),
        FailureCode.audioUnsupportedBitDepth,
      );
    });

    test('rejects ADPCM with unsupportedFormat', () {
      _expectFailure(
        decoder.decodeInput(
          _file(
            _wav(
              format: const _FormatCase('ADPCM', format: 2, bitsPerSample: 16),
            ),
          ),
        ),
        FailureCode.audioUnsupportedFormat,
      );
    });
  });

  group('WavDecoderAdapter malformed matrix', () {
    test('rejects a non-RIFF header', () {
      final bytes = _wav();
      bytes.setRange(0, 4, 'NOPE'.codeUnits);

      _expectFailure(
        decoder.decodeInput(_file(bytes)),
        FailureCode.audioInvalidRiff,
      );
    });

    test('rejects a RIFF header with a non-WAVE form type', () {
      final bytes = _wav();
      bytes.setRange(8, 12, 'NOPE'.codeUnits);

      _expectFailure(
        decoder.decodeInput(_file(bytes)),
        FailureCode.audioInvalidRiff,
      );
    });

    test('rejects a truncated fmt chunk', () {
      final bytes = _wav().sublist(0, 24);

      _expectFailure(
        decoder.decodeInput(_file(bytes)),
        FailureCode.audioTruncatedChunk,
      );
    });

    test('rejects a truncated data chunk', () {
      final bytes = _wav().sublist(0, 46);

      _expectFailure(
        decoder.decodeInput(_file(bytes)),
        FailureCode.audioChunkSizeOutOfBounds,
      );
    });

    test('rejects a data chunk larger than the remaining bytes', () {
      final bytes = _wav();
      _writeUint32(bytes, 40, bytes.length);

      _expectFailure(
        decoder.decodeInput(_file(bytes)),
        FailureCode.audioChunkSizeOutOfBounds,
      );
    });

    test('rejects a 0xFFFFFFFF chunk length without crashing', () {
      final bytes = _wav();
      _writeUint32(bytes, 40, 0xFFFFFFFF);

      _expectFailure(
        decoder.decodeInput(_file(bytes)),
        FailureCode.audioChunkSizeOutOfBounds,
      );
    });

    test('rejects a stereo data chunk with an incomplete frame', () {
      final bytes = _wav(
        format: const _FormatCase(
          'stereo PCM',
          format: 1,
          bitsPerSample: 16,
          channels: 2,
        ),
      );
      _writeUint32(bytes, 40, 6);
      final malformed = Uint8List.fromList(<int>[...bytes, 0, 0]);

      _expectFailure(
        decoder.decodeInput(_file(malformed)),
        FailureCode.audioTruncatedChunk,
      );
    });
  });
}

FileAnalysisInput _file(Uint8List bytes) => FileAnalysisInput(
  bytes: bytes,
  source: AnalysisInputSource.importedFile,
  sourceDisplayName: const SourceDisplayName('private-recording.wav'),
);

void _expectFailure<T>(AppResult<T> result, String code) {
  expect(result, isA<Failure<T>>());
  expect((result as Failure<T>).error.code, code);
}

Uint8List _wav({
  _FormatCase format = const _FormatCase(
    'default',
    format: 1,
    bitsPerSample: 16,
  ),
}) {
  final bytesPerSample = format.bitsPerSample ~/ 8;
  final frameBytes = format.channels * bytesPerSample;
  const frameCount = 12000;
  final dataLength = frameCount * frameBytes;
  final bytes = Uint8List(44 + dataLength);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  _writeUint32(bytes, 4, 36 + dataLength);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  _writeUint32(bytes, 16, 16);
  _writeUint16(bytes, 20, format.format);
  _writeUint16(bytes, 22, format.channels);
  _writeUint32(bytes, 24, 48000);
  _writeUint32(bytes, 28, 48000 * frameBytes);
  _writeUint16(bytes, 32, frameBytes);
  _writeUint16(bytes, 34, format.bitsPerSample);
  bytes.setRange(36, 40, 'data'.codeUnits);
  _writeUint32(bytes, 40, dataLength);
  if (format.format == 3 && format.bitsPerSample == 32) {
    for (var offset = 44; offset < bytes.length; offset += 4) {
      ByteData.sublistView(bytes).setFloat32(offset, 0.25, Endian.little);
    }
  } else if (format.bitsPerSample == 16) {
    for (var offset = 44; offset < bytes.length; offset += 2) {
      ByteData.sublistView(bytes).setInt16(offset, 8192, Endian.little);
    }
  }
  return bytes;
}

void _writeUint16(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(bytes).setUint16(offset, value, Endian.little);

void _writeUint32(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(bytes).setUint32(offset, value, Endian.little);

final class _FormatCase {
  const _FormatCase(
    this.label, {
    required this.format,
    required this.bitsPerSample,
    this.channels = 1,
  });

  final String label;
  final int format;
  final int bitsPerSample;
  final int channels;
}
