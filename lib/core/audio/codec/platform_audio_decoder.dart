import 'dart:io';
import 'dart:typed_data';

import '../../foundation/app_failure.dart';
import '../../foundation/app_result.dart';

/// Decoded audio the whole app can consume: **mono** float32 PCM in `[-1, 1]`
/// plus the sample rate it is expressed at.
///
/// This is the shape the WAV path could produce too — `WavDecoder` still
/// returns the older `(List<double>, int)` record and nothing here forces it
/// to change; [DecodedPcm] is simply the richer, named form the compressed
/// path needs, where the frame count and the already-mixed-down channel count
/// are part of the contract.
final class DecodedPcm {
  const DecodedPcm({required this.sampleRate, required this.samples});

  /// Hz — the decoder's own rate, or the requested resample rate.
  final int sampleRate;

  /// Mono samples, one entry per frame.
  final Float32List samples;

  /// Always 1: the platform decoder averages every source channel down.
  int get channelCount => 1;

  int get frames => samples.length;

  Duration get duration {
    if (sampleRate <= 0) return Duration.zero;
    const perSecond = Duration.microsecondsPerSecond;
    return Duration(microseconds: samples.length * perSecond ~/ sampleRate);
  }
}

/// What a container declares about its first audio track, without decoding.
final class AudioProbe {
  const AudioProbe({
    required this.durationMs,
    required this.sampleRate,
    required this.channelCount,
    required this.mime,
  });

  /// Negative when the container declares no duration.
  final int durationMs;
  final int sampleRate;
  final int channelCount;
  final String mime;

  bool get hasKnownDuration => durationMs >= 0;

  Duration get duration =>
      Duration(milliseconds: durationMs < 0 ? 0 : durationMs);
}

/// Thrown by a platform bridge instead of leaking a transport type
/// (`PlatformException`) into this Flutter-free layer.
final class AudioDecoderPlatformError implements Exception {
  const AudioDecoderPlatformError({required this.code, this.message});

  /// One of the channel's stable codes, e.g. `no_audio_track`.
  final String code;
  final String? message;

  @override
  String toString() => 'AudioDecoderPlatformError($code)';
}

/// The transport seam. Implemented over a `MethodChannel` in
/// `lib/core/audio/method_channel_audio_decoder_bridge.dart`; kept abstract
/// here so this file stays inside the shared-domain boundary, which forbids a
/// `package:flutter/...` import under `lib/core/audio/codec/`.
abstract interface class AudioDecoderPlatformBridge {
  Future<Object?> invoke(String method, Map<String, Object?> arguments);
}

/// Limits enforced on the Dart side *before* a byte reaches the platform.
///
/// Deliberately duplicated from `InputLimits`, which lives in the
/// `audio_analysis` feature and therefore cannot be imported from core. The
/// duplication is measured, not trusted: `platform_audio_decoder_test.dart`
/// fails the moment the two drift apart.
abstract final class AudioDecoderLimits {
  static const int maxFileBytes = 64 * 1024 * 1024;
  static const Duration maxDuration = Duration(minutes: 10);
}

/// Existence + size of a candidate file.
typedef AudioFileStat = ({bool exists, int lengthBytes});

/// Reads an [AudioFileStat] for `path`. Injected so the guard cells need no
/// real file on disk.
typedef AudioFileStatReader = AudioFileStat Function(String path);

AudioFileStat _statFromDisk(String path) {
  final file = File(path);
  if (!file.existsSync()) return (exists: false, lengthBytes: 0);
  return (exists: true, lengthBytes: file.lengthSync());
}

/// Decodes MP3 / MP4 / M4A / AAC / OGG / FLAC / WAV through the Android
/// platform decoder on the `strumsight/audio_decoder` channel.
///
/// Android only for now: on every other platform both methods fail with
/// [FailureCode.audioUnsupportedPlatform] and the channel is never touched.
final class PlatformAudioDecoder {
  PlatformAudioDecoder({
    required this._bridge,
    bool? isSupportedPlatform,
    this._statReader = _statFromDisk,
    this.maxFileBytes = AudioDecoderLimits.maxFileBytes,
    this.maxDuration = AudioDecoderLimits.maxDuration,
  }) : _isSupportedPlatform = isSupportedPlatform ?? Platform.isAndroid;

  final AudioDecoderPlatformBridge _bridge;
  final AudioFileStatReader _statReader;
  final bool _isSupportedPlatform;
  final int maxFileBytes;
  final Duration maxDuration;

  /// What the container declares, without decoding a single frame.
  Future<AppResult<AudioProbe>> probe(String path) async {
    final guard = _guardFile(path);
    if (guard case Failure<void>(:final error)) {
      return Failure<AudioProbe>(error);
    }
    return _probe(path);
  }

  /// Decodes [path] to mono float32 PCM.
  ///
  /// [targetSampleRate] is optional — omitted, the decoder's own rate survives
  /// and nothing is resampled. [maxSeconds] stops the decode early instead of
  /// failing; without it a clip longer than [maxDuration] is rejected up front
  /// with [FailureCode.audioClipTooLong].
  Future<AppResult<DecodedPcm>> decodeToPcm(
    String path, {
    int? targetSampleRate,
    Duration? maxSeconds,
  }) async {
    final guard = _guardFile(path);
    if (guard case Failure<void>(:final error)) {
      return Failure<DecodedPcm>(error);
    }

    final probed = await _probe(path);
    if (probed case Failure<AudioProbe>(:final error)) {
      return Failure<DecodedPcm>(error);
    }
    final details = (probed as Success<AudioProbe>).value;
    final effective = _effective(details.duration, maxSeconds);
    if (details.hasKnownDuration && effective > maxDuration) {
      return const Failure<DecodedPcm>(
        AudioFailure(code: FailureCode.audioClipTooLong, retryable: false),
      );
    }

    final seconds = maxSeconds == null
        ? null
        : maxSeconds.inMicroseconds / Duration.microsecondsPerSecond;
    Object? reply;
    try {
      reply = await _bridge.invoke('decodeToPcm', <String, Object?>{
        'path': path,
        'targetSampleRate': targetSampleRate,
        'maxSeconds': seconds,
      });
    } on AudioDecoderPlatformError catch (error, stackTrace) {
      return Failure<DecodedPcm>(_mapError(error, stackTrace));
    }

    final map = _asMap(reply);
    if (map == null) return const Failure<DecodedPcm>(_malformed);
    final sampleRate = map['sampleRate'];
    final frames = map['frames'];
    final pcm = map['pcm'];
    if (sampleRate is! int || frames is! int || pcm is! Uint8List) {
      return const Failure<DecodedPcm>(_malformed);
    }
    if (frames < 0 || pcm.lengthInBytes != frames * 4) {
      return const Failure<DecodedPcm>(_malformed);
    }
    return Success<DecodedPcm>(
      DecodedPcm(sampleRate: sampleRate, samples: _float32Le(pcm, frames)),
    );
  }

  Future<AppResult<AudioProbe>> _probe(String path) async {
    Object? reply;
    try {
      reply = await _bridge.invoke('probe', <String, Object?>{'path': path});
    } on AudioDecoderPlatformError catch (error, stackTrace) {
      return Failure<AudioProbe>(_mapError(error, stackTrace));
    }
    final map = _asMap(reply);
    if (map == null) return const Failure<AudioProbe>(_malformed);
    final durationMs = map['durationMs'];
    final sampleRate = map['sampleRate'];
    final channelCount = map['channelCount'];
    final mime = map['mime'];
    if (durationMs is! int ||
        sampleRate is! int ||
        channelCount is! int ||
        mime is! String) {
      return const Failure<AudioProbe>(_malformed);
    }
    return Success<AudioProbe>(
      AudioProbe(
        durationMs: durationMs,
        sampleRate: sampleRate,
        channelCount: channelCount,
        mime: mime,
      ),
    );
  }

  AppResult<void> _guardFile(String path) {
    if (!_isSupportedPlatform) {
      return const Failure<void>(
        AudioFailure(
          code: FailureCode.audioUnsupportedPlatform,
          retryable: false,
        ),
      );
    }
    final stat = _statReader(path);
    if (!stat.exists) {
      return const Failure<void>(
        AudioFailure(code: FailureCode.audioFileNotFound, retryable: false),
      );
    }
    if (stat.lengthBytes > maxFileBytes) {
      return const Failure<void>(
        AudioFailure(code: FailureCode.audioFileTooLarge, retryable: false),
      );
    }
    return const Success<void>(null);
  }

  static Duration _effective(Duration probed, Duration? cap) =>
      cap == null || probed < cap ? probed : cap;

  /// The channel's stable codes mapped onto the app's stable failure codes.
  static AppFailure _mapError(
    AudioDecoderPlatformError error,
    StackTrace stackTrace,
  ) {
    final code = switch (error.code) {
      'no_audio_track' => FailureCode.audioNoAudioTrack,
      'unsupported_container' => FailureCode.audioUnsupportedContainer,
      'decoder_failed' => FailureCode.audioDecoderFailed,
      'file_not_found' => FailureCode.audioFileNotFound,
      'too_long' => FailureCode.audioClipTooLong,
      'unsupported_platform' => FailureCode.audioUnsupportedPlatform,
      _ => FailureCode.audioDecoderFailed,
    };
    return AudioFailure(
      code: code,
      retryable: false,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static const AudioFailure _malformed = AudioFailure(
    code: FailureCode.audioDecoderFailed,
    retryable: false,
  );

  static Map<Object?, Object?>? _asMap(Object? reply) =>
      reply is Map<Object?, Object?> ? reply : null;

  /// Little-endian float32 bytes to a [Float32List]. Zero-copy view when the
  /// host is little-endian and the payload is 4-byte aligned; otherwise read
  /// sample by sample, so the result is correct either way.
  static Float32List _float32Le(Uint8List bytes, int frames) {
    if (Endian.host == Endian.little && bytes.offsetInBytes % 4 == 0) {
      return Float32List.view(bytes.buffer, bytes.offsetInBytes, frames);
    }
    final data = ByteData.sublistView(bytes);
    final out = Float32List(frames);
    for (var i = 0; i < frames; i++) {
      out[i] = data.getFloat32(i * 4, Endian.little);
    }
    return out;
  }
}
