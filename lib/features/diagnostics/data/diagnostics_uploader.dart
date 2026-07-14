import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/api/api_config.dart';
import '../../learn/audio/wav.dart';
import '../model/diagnostics_session.dart';

/// Outcome of a diagnostics upload, surfaced to the Lab-mode UI. This is the
/// ONLY thing the uploader returns — it never throws into the caller (a failed
/// diagnostics push must never disturb the Analyze result).
enum DiagnosticsUploadStatus { idle, uploading, uploaded, failed }

/// Best-effort uploader for a Lab-mode [DiagnosticsSession] (r198). Gzips the
/// session JSON, POSTs it to `${ApiConfig.baseUrl}/diagnostics` with the diag
/// token + `Content-Encoding: gzip`, retries a couple of times on network
/// failure, and returns a status — NEVER throwing. Fire-and-forget from the
/// Analyze path.
class DiagnosticsUploader {
  DiagnosticsUploader({Dio? dio, this.maxRetries = 2})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: ApiConfig.baseUrl,
              connectTimeout: const Duration(seconds: 6),
              sendTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 6),
            ));

  final Dio _dio;

  /// How many additional attempts after the first (total = maxRetries + 1).
  final int maxRetries;

  /// Cap on the raw (pre-base64) WAV clip. base64 inflates ~4/3, so this keeps
  /// the encoded clip well under the ~8 MB upload budget. A longer clip is
  /// decimated (integer downsample) to fit — a diagnostic clip does not need
  /// full fidelity.
  static const int maxWavBytes = 5 * 1024 * 1024;

  /// Upload [session]. [appVersion]/[device] populate the optional headers.
  /// Returns [DiagnosticsUploadStatus.uploaded] on a 2xx, else `.failed`.
  Future<DiagnosticsUploadStatus> upload(
    DiagnosticsSession session, {
    String? appVersion,
    String? device,
  }) async {
    final Uint8List body;
    try {
      final json = jsonEncode(session.toJson());
      body = Uint8List.fromList(gzip.encode(utf8.encode(json)));
    } catch (_) {
      // Serialization/compression should never fail, but if it does, don't
      // throw — just report a failed upload.
      return DiagnosticsUploadStatus.failed;
    }

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final res = await _dio.post<dynamic>(
          '/diagnostics',
          data: Stream.fromIterable([body]),
          options: Options(
            headers: {
              'X-Diag-Token': ApiConfig.diagToken,
              'Content-Type': 'application/json',
              'Content-Encoding': 'gzip',
              'Content-Length': body.length,
              'X-Session-Id': session.sessionId,
              'X-App-Version': ?appVersion,
              'X-Device': ?device,
            },
          ),
        );
        final code = res.statusCode ?? 0;
        if (code >= 200 && code < 300) {
          return DiagnosticsUploadStatus.uploaded;
        }
        // A non-2xx that isn't a transport error: no point retrying auth/shape
        // problems — report failed.
        return DiagnosticsUploadStatus.failed;
      } on DioException catch (_) {
        // Transport error — retry if attempts remain, else fail.
        if (attempt >= maxRetries) return DiagnosticsUploadStatus.failed;
      } catch (_) {
        return DiagnosticsUploadStatus.failed;
      }
    }
    return DiagnosticsUploadStatus.failed;
  }

  /// Encode mono [pcm] (samples in [-1, 1]) at [sampleRate] Hz into a base64
  /// 16-bit WAV, decimating to keep the raw WAV under [maxWavBytes]. Returns
  /// null on empty/invalid input so the session simply carries no clip.
  static DiagnosticsAudioClip? clipFromPcm(List<double> pcm, int sampleRate) {
    if (pcm.isEmpty || sampleRate <= 0) return null;
    // 16-bit WAV = 44-byte header + 2 bytes/sample. Choose an integer decimation
    // factor so the output fits the byte cap.
    final maxSamples = (maxWavBytes - 44) ~/ 2;
    var factor = 1;
    if (pcm.length > maxSamples) {
      factor = (pcm.length + maxSamples - 1) ~/ maxSamples;
    }
    final outLen = pcm.length ~/ factor;
    if (outLen <= 0) return null;
    final samples = Int16List(outLen);
    for (var i = 0; i < outLen; i++) {
      // Average the decimation block to avoid aliasing artefacts.
      var acc = 0.0;
      final base = i * factor;
      for (var k = 0; k < factor; k++) {
        acc += pcm[base + k];
      }
      final v = (acc / factor).clamp(-1.0, 1.0);
      samples[i] = (v * 32767.0).round();
    }
    final outRate = sampleRate ~/ factor;
    final wav = pcmToWav(samples, outRate <= 0 ? sampleRate : outRate);
    return DiagnosticsAudioClip(tSec: 0, wavBase64: base64Encode(wav));
  }
}
