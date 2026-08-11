import 'dart:typed_data';

import 'package:strumsight/core/audio/codec/wav_decoder.dart' as core_codec;
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';

import 'analysis_input_validator.dart';
import 'audio_decoder_gateway.dart';

/// Bounds-checking adapter around the legacy WAV decoder.
///
/// The legacy decoder remains untouched and still returns nullable output. This
/// adapter validates RIFF chunks first, maps each rejection to a stable failure,
/// then turns a successful decode into a [PcmAnalysisInput].
final class WavDecoderAdapter implements AudioDecoderGateway {
  const WavDecoderAdapter({this.validator = const AnalysisInputValidator()});

  final AnalysisInputValidator validator;

  @override
  AppResult<core_codec.DecodedAudio> decode(FileAnalysisInput input) =>
      decodeInput(input).map((input) => (input.samples, input.sampleRate));

  /// Decodes to the richer V2 input type so the original channel count survives.
  AppResult<PcmAnalysisInput> decodeInput(FileAnalysisInput input) {
    final bytes = input.bytes;
    final fileSize = validator.validateFileByteCount(bytes.length);
    if (fileSize case Failure<void>(:final error)) {
      return Failure<PcmAnalysisInput>(error);
    }

    final inspected = _inspect(bytes);
    if (inspected case Failure<_WavHeader>(:final error)) {
      return Failure<PcmAnalysisInput>(error);
    }
    final header = (inspected as Success<_WavHeader>).value;

    try {
      final decoded = core_codec.WavDecoder.decode(bytes);
      if (decoded == null) {
        return const Failure<PcmAnalysisInput>(
          AudioFailure(code: FailureCode.audioTruncatedChunk, retryable: false),
        );
      }
      final (samples, sampleRate) = decoded;
      final validated = validator.validate(
        PcmAnalysisInput(
          samples: samples,
          sampleRate: sampleRate,
          channelCount: header.channels,
          source: input.source,
          sourceDisplayName: input.sourceDisplayName,
        ),
      );
      return switch (validated) {
        Success<ValidatedPcmAnalysisInput>(:final value) =>
          Success<PcmAnalysisInput>(value.input),
        Failure<ValidatedPcmAnalysisInput>(:final error) =>
          Failure<PcmAnalysisInput>(error),
      };
    } on RangeError catch (error, stackTrace) {
      return Failure<PcmAnalysisInput>(
        AudioFailure(
          code: FailureCode.audioChunkSizeOutOfBounds,
          retryable: false,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } on ArgumentError catch (error, stackTrace) {
      return Failure<PcmAnalysisInput>(
        AudioFailure(
          code: FailureCode.audioNonFiniteSample,
          retryable: false,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  AppResult<_WavHeader> _inspect(Uint8List bytes) {
    if (bytes.length < 12 ||
        _tag(bytes, 0) != 'RIFF' ||
        _tag(bytes, 8) != 'WAVE') {
      return const Failure<_WavHeader>(
        AudioFailure(code: FailureCode.audioInvalidRiff, retryable: false),
      );
    }
    final data = ByteData.sublistView(bytes);
    _WavHeader? header;
    var hasDataChunk = false;
    var offset = 12;
    while (offset < bytes.length) {
      if (bytes.length - offset < 8) {
        return const Failure<_WavHeader>(
          AudioFailure(code: FailureCode.audioTruncatedChunk, retryable: false),
        );
      }
      final chunkId = _tag(bytes, offset);
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final body = offset + 8;
      if (chunkSize > bytes.length - body) {
        if (chunkId == 'fmt ') {
          return const Failure<_WavHeader>(
            AudioFailure(
              code: FailureCode.audioTruncatedChunk,
              retryable: false,
            ),
          );
        }
        return const Failure<_WavHeader>(
          AudioFailure(
            code: FailureCode.audioChunkSizeOutOfBounds,
            retryable: false,
          ),
        );
      }
      final chunkEnd = body + chunkSize;

      if (chunkId == 'fmt ') {
        if (chunkSize < 16) {
          return const Failure<_WavHeader>(
            AudioFailure(
              code: FailureCode.audioTruncatedChunk,
              retryable: false,
            ),
          );
        }
        final format = data.getUint16(body, Endian.little);
        final channels = data.getUint16(body + 2, Endian.little);
        final sampleRate = data.getUint32(body + 4, Endian.little);
        final byteRate = data.getUint32(body + 8, Endian.little);
        final blockAlign = data.getUint16(body + 12, Endian.little);
        final bitsPerSample = data.getUint16(body + 14, Endian.little);
        final supported = _validateFormat(
          format: format,
          channels: channels,
          sampleRate: sampleRate,
          byteRate: byteRate,
          blockAlign: blockAlign,
          bitsPerSample: bitsPerSample,
        );
        if (supported case Failure<void>(:final error)) {
          return Failure<_WavHeader>(error);
        }
        header = _WavHeader(
          format: format,
          channels: channels,
          sampleRate: sampleRate,
          bitsPerSample: bitsPerSample,
          blockAlign: blockAlign,
        );
      } else if (chunkId == 'data') {
        if (header == null) {
          return const Failure<_WavHeader>(
            AudioFailure(
              code: FailureCode.audioTruncatedChunk,
              retryable: false,
            ),
          );
        }
        if (hasDataChunk) {
          return const Failure<_WavHeader>(
            AudioFailure(
              code: FailureCode.audioMultipleDataChunks,
              retryable: false,
            ),
          );
        }
        if (chunkSize == 0 || chunkSize % header.blockAlign != 0) {
          return const Failure<_WavHeader>(
            AudioFailure(
              code: FailureCode.audioTruncatedChunk,
              retryable: false,
            ),
          );
        }
        if (header.format == 3) {
          for (
            var sampleOffset = body;
            sampleOffset < chunkEnd;
            sampleOffset += 4
          ) {
            if (!data.getFloat32(sampleOffset, Endian.little).isFinite) {
              return const Failure<_WavHeader>(
                AudioFailure(
                  code: FailureCode.audioNonFiniteSample,
                  retryable: false,
                ),
              );
            }
          }
        }
        hasDataChunk = true;
      }

      offset = chunkEnd;
      if (chunkSize.isOdd) {
        if (offset == bytes.length) {
          return const Failure<_WavHeader>(
            AudioFailure(
              code: FailureCode.audioTruncatedChunk,
              retryable: false,
            ),
          );
        }
        offset++;
      }
    }
    if (!hasDataChunk || header == null) {
      return const Failure<_WavHeader>(
        AudioFailure(code: FailureCode.audioTruncatedChunk, retryable: false),
      );
    }
    return Success<_WavHeader>(header);
  }

  AppResult<void> _validateFormat({
    required int format,
    required int channels,
    required int sampleRate,
    required int byteRate,
    required int blockAlign,
    required int bitsPerSample,
  }) {
    if (format != 1 && format != 3) {
      return const Failure<void>(
        AudioFailure(
          code: FailureCode.audioUnsupportedFormat,
          retryable: false,
        ),
      );
    }
    if ((format == 1 && bitsPerSample != 16) ||
        (format == 3 && bitsPerSample != 32)) {
      return const Failure<void>(
        AudioFailure(
          code: FailureCode.audioUnsupportedBitDepth,
          retryable: false,
        ),
      );
    }
    final metadata = validator.validatePcmMetadata(
      sampleCount: 1,
      sampleRate: sampleRate,
      channelCount: channels,
    );
    if (metadata case Failure<void>(:final error)) {
      if (error.code == FailureCode.audioEmptyInput ||
          error.code == FailureCode.audioClipTooShort) {
        // Sample count is unknown at header validation time; defer it to PCM.
      } else {
        return Failure<void>(error);
      }
    }
    final expectedBlockAlign = channels * (bitsPerSample ~/ 8);
    if (blockAlign != expectedBlockAlign ||
        byteRate != sampleRate * blockAlign) {
      return const Failure<void>(
        AudioFailure(code: FailureCode.audioTruncatedChunk, retryable: false),
      );
    }
    return const Success<void>(null);
  }

  static String _tag(Uint8List bytes, int offset) =>
      String.fromCharCodes(bytes.sublist(offset, offset + 4));
}

final class _WavHeader {
  const _WavHeader({
    required this.format,
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.blockAlign,
  });

  final int format;
  final int channels;
  final int sampleRate;
  final int bitsPerSample;
  final int blockAlign;
}
