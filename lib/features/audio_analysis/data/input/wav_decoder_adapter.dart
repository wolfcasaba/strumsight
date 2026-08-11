import 'dart:typed_data';

import 'package:strumsight/core/audio/codec/wav_decoder.dart' show WavDecoder;
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';

/// Classifies untrusted WAV bytes before delegating sample conversion to the
/// frozen V1 [WavDecoder]. This adapter is the import boundary; it never lets a
/// legacy `null` result escape without a typed reason.
final class WavDecoderAdapter {
  const WavDecoderAdapter();

  AppResult<DecodedAudio> decode(Uint8List bytes) {
    final headerResult = _readHeader(bytes);
    if (headerResult case Failure<_WavHeader>(:final error)) {
      return Failure<DecodedAudio>(error);
    }
    final header = (headerResult as Success<_WavHeader>).value;

    if (header.format != 1 && header.format != 3) {
      return const Failure<DecodedAudio>(
        AudioFailure(code: FailureCode.unsupportedFormat, retryable: false),
      );
    }
    final expectedBits = header.format == 1 ? 16 : 32;
    if (header.bitsPerSample != expectedBits) {
      return const Failure<DecodedAudio>(
        AudioFailure(code: FailureCode.unsupportedBitDepth, retryable: false),
      );
    }
    if (header.channels < 1 || header.channels > 2 || header.sampleRate <= 0) {
      return const Failure<DecodedAudio>(
        ValidationFailure(code: FailureCode.validationInvalidInput),
      );
    }
    final frameBytes = header.channels * (header.bitsPerSample ~/ 8);
    if (header.dataSize == 0 || header.dataSize % frameBytes != 0) {
      return const Failure<DecodedAudio>(
        AudioFailure(code: FailureCode.truncatedChunk, retryable: false),
      );
    }
    if (header.format == 3 && !_allFloat32SamplesFinite(bytes, header)) {
      return const Failure<DecodedAudio>(
        ValidationFailure(code: FailureCode.nonFiniteSample),
      );
    }

    try {
      final decoded = WavDecoder.decode(bytes);
      if (decoded == null) {
        return const Failure<DecodedAudio>(
          AudioFailure(code: FailureCode.truncatedChunk, retryable: false),
        );
      }
      return Success<DecodedAudio>(
        DecodedAudio(
          samples: Float32List.fromList(decoded.$1),
          sampleRate: decoded.$2,
          channelCount: header.channels,
          source: AnalysisInputSource.importedFile,
        ),
      );
    } catch (error, stackTrace) {
      return Failure<DecodedAudio>(
        ValidationFailure(
          code: FailureCode.invalidRiff,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  AppResult<_WavHeader> _readHeader(Uint8List bytes) {
    if (bytes.length < 12 || _tag(bytes, 0) != 'RIFF') {
      return const Failure<_WavHeader>(
        AudioFailure(code: FailureCode.invalidRiff, retryable: false),
      );
    }
    if (_tag(bytes, 8) != 'WAVE') {
      return const Failure<_WavHeader>(
        AudioFailure(code: FailureCode.invalidRiff, retryable: false),
      );
    }

    final data = ByteData.sublistView(bytes);
    var offset = 12;
    _WavFormat? format;
    _WavData? audioData;
    while (offset <= bytes.length - 8) {
      final id = _tag(bytes, offset);
      final size = data.getUint32(offset + 4, Endian.little);
      final body = offset + 8;
      if (size > bytes.length - body) {
        return Failure<_WavHeader>(
          AudioFailure(
            code: id == 'fmt '
                ? FailureCode.truncatedChunk
                : FailureCode.chunkSizeOutOfBounds,
            retryable: false,
          ),
        );
      }
      if (id == 'fmt ') {
        if (size < 16) {
          return const Failure<_WavHeader>(
            AudioFailure(code: FailureCode.truncatedChunk, retryable: false),
          );
        }
        format = _WavFormat(
          format: data.getUint16(body, Endian.little),
          channels: data.getUint16(body + 2, Endian.little),
          sampleRate: data.getUint32(body + 4, Endian.little),
          bitsPerSample: data.getUint16(body + 14, Endian.little),
        );
      } else if (id == 'data') {
        audioData = _WavData(offset: body, size: size);
      }
      offset = body + size + (size & 1);
    }

    if (format == null || audioData == null) {
      return const Failure<_WavHeader>(
        AudioFailure(code: FailureCode.truncatedChunk, retryable: false),
      );
    }
    return Success<_WavHeader>(
      _WavHeader(
        format: format.format,
        channels: format.channels,
        sampleRate: format.sampleRate,
        bitsPerSample: format.bitsPerSample,
        dataOffset: audioData.offset,
        dataSize: audioData.size,
      ),
    );
  }

  bool _allFloat32SamplesFinite(Uint8List bytes, _WavHeader header) {
    final data = ByteData.sublistView(bytes);
    final end = header.dataOffset + header.dataSize;
    for (var offset = header.dataOffset; offset < end; offset += 4) {
      if (!data.getFloat32(offset, Endian.little).isFinite) return false;
    }
    return true;
  }

  String _tag(Uint8List bytes, int offset) =>
      String.fromCharCodes(bytes.sublist(offset, offset + 4));
}

final class _WavFormat {
  const _WavFormat({
    required this.format,
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
  });

  final int format;
  final int channels;
  final int sampleRate;
  final int bitsPerSample;
}

final class _WavData {
  const _WavData({required this.offset, required this.size});

  final int offset;
  final int size;
}

final class _WavHeader {
  const _WavHeader({
    required this.format,
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataSize,
  });

  final int format;
  final int channels;
  final int sampleRate;
  final int bitsPerSample;
  final int dataOffset;
  final int dataSize;
}
