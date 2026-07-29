import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../learn/audio/wav.dart';
import '../model/diagnostics_session.dart';

/// Outcome of a diagnostics upload, surfaced to the Lab-mode UI. This is the
/// ONLY thing the uploader returns — it never throws into the caller (a failed
/// diagnostics push must never disturb the Analyze result).
enum DiagnosticsUploadStatus { idle, uploading, uploaded, failed }

/// Best-effort uploader for a Lab-mode [DiagnosticsSession] (r198). Gzips the
/// session JSON, POSTs it once with the diagnostics token +
/// `Content-Encoding: gzip`, and returns a status — NEVER throwing.
class DiagnosticsUploader {
  DiagnosticsUploader({
    required this.client,
    required this.diagToken,
    AppLogger logger = const NoopAppLogger(),
  }) : _log = logger;

  final ApiClient? client;

  /// Every swallowed error is reported here — the upload stays best-effort,
  /// but it is no longer *silent* (E01-R04 §4.5).
  final AppLogger _log;

  /// `X-Diag-Token` header value for the diagnostics endpoint.
  final String diagToken;

  /// Cap on the raw (pre-base64) WAV clip. base64 inflates ~4/3, so this keeps
  /// the encoded clip well under the ~8 MB upload budget. A longer clip is
  /// decimated (integer downsample) to fit — a diagnostic clip does not need
  /// full fidelity.
  static const int maxWavBytes = 5 * 1024 * 1024;

  /// Upload [session]. [appVersion]/[device] populate the optional headers.
  /// Returns [DiagnosticsUploadStatus.uploaded] on a 2xx, else `.failed`.
  Future<DiagnosticsUploadStatus> upload(
    DiagnosticsSession session, {
    required bool consentGranted,
    String? appVersion,
    String? device,
  }) async {
    final apiClient = client;
    if (!consentGranted || apiClient == null) {
      return DiagnosticsUploadStatus.failed;
    }

    final Uint8List body;
    try {
      final json = jsonEncode(session.toJson());
      body = Uint8List.fromList(gzip.encode(utf8.encode(json)));
    } catch (e, stackTrace) {
      // Serialization/compression should never fail, but if it does, don't
      // throw — just report (and log) a failed upload.
      _log.warning(
        'diagnostics.encode_failed',
        error: e,
        stackTrace: stackTrace,
        fields: const {'code': FailureCode.unknown},
      );
      return DiagnosticsUploadStatus.failed;
    }

    final result = await apiClient.post(
      '/diagnostics',
      data: Stream<Uint8List>.fromIterable([body]),
      headers: {
        'X-Diag-Token': diagToken,
        'Content-Type': 'application/json',
        'Content-Encoding': 'gzip',
        'Content-Length': body.length,
        'X-Session-Id': session.sessionId,
        'X-App-Version': ?appVersion,
        'X-Device': ?device,
      },
      requiresAuthentication: false,
    );
    return switch (result) {
      Success() => DiagnosticsUploadStatus.uploaded,
      Failure(:final error) => () {
        _log.warning(
          'diagnostics.upload_failed',
          fields: {'code': error.code, 'retryable': error.retryable},
        );
        return DiagnosticsUploadStatus.failed;
      }(),
    };
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
