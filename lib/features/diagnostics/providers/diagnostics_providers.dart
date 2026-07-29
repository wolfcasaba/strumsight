import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../../core/logging/logger_provider.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/dio_factory.dart';
import '../../analyze/model/analyze_result.dart';
import '../data/diagnostics_uploader.dart';
import '../model/diagnostics_session.dart';

/// Explicit, revocable upload consent. The composition root binds this to the
/// persisted Lab-mode setting; tests default to fail-closed.
final diagnosticsConsentProvider = Provider<bool>((_) => false);

/// A transport that is separate from the account client and has no bearer
/// interceptor. Disabled builds never instantiate it.
final diagnosticsApiClientProvider = Provider<ApiClient?>((ref) {
  final config = ref.watch(appConfigProvider);
  if (!config.flags.diagnosticsEnabled) return null;

  final client = DioFactory(
    baseUrl: config.apiBaseUrl,
    appVersion: config.appVersion,
    logger: ref.watch(appLoggerProvider),
  ).createDiagnosticsClient(diagnosticsEnabled: true);
  ref.onDispose(client.close);
  return client;
});

/// The best-effort diagnostics uploader, bound to the separately gated client.
final diagnosticsUploaderProvider = Provider<DiagnosticsUploader>((ref) {
  final config = ref.watch(appConfigProvider);
  return DiagnosticsUploader(
    client: ref.watch(diagnosticsApiClientProvider),
    diagToken: config.diagnosticsToken,
    logger: ref.watch(appLoggerProvider),
  );
});

/// Holds the Lab-mode diagnostics upload status for the current Analyze result
/// so the diagnostics panel can show uploading / uploaded / failed (r198).
/// Reset to [DiagnosticsUploadStatus.idle] at the start of each analyze.
class DiagnosticsUploadNotifier extends Notifier<DiagnosticsUploadStatus> {
  @override
  DiagnosticsUploadStatus build() => DiagnosticsUploadStatus.idle;

  /// Back to idle — called when a new analyze begins (clears a stale status).
  void reset() => state = DiagnosticsUploadStatus.idle;

  /// Build a diagnostics session from [result] + its recorded clip ([pcm]/[sr])
  /// and upload it best-effort. Fire-and-forget: sets `uploading`, then
  /// `uploaded`/`failed`. Never throws — a diagnostics failure never disturbs
  /// the Analyze result. No-op if the result carries no diagnostics. [surface]
  /// tags which screen produced it — `analyze` (default) or `live` (r199).
  Future<void> upload(
    AnalyzeResult result,
    List<double> pcm,
    int sr, {
    String surface = 'analyze',
  }) async {
    if (result.diagnostics == null) return;
    final config = ref.read(appConfigProvider);
    final consentGranted = ref.read(diagnosticsConsentProvider);
    if (!config.flags.diagnosticsEnabled || !consentGranted) return;

    state = DiagnosticsUploadStatus.uploading;

    final appVersion = config.appVersion;
    final device = _device();
    final clip = DiagnosticsUploader.clipFromPcm(pcm, sr);
    final session = DiagnosticsSession(
      sessionId: DateTime.now().microsecondsSinceEpoch.toString(),
      appVersion: appVersion,
      device: device,
      startedAt: DateTime.now().toUtc().toIso8601String(),
      surface: surface,
      events: DiagnosticsSession.eventsFrom(result),
      audioClips: clip == null ? const [] : [clip],
    );

    final status = await ref
        .read(diagnosticsUploaderProvider)
        .upload(
          session,
          consentGranted: consentGranted,
          appVersion: appVersion,
          device: device,
        );
    if (!ref.mounted) return;
    state = status;
  }

  /// Documented swallow (§4.5): `Platform` is unavailable on some hosts, and
  /// the device string is a cosmetic diagnostics header — an unknown platform
  /// is a correct answer here, not an error hidden from the user.
  String _device() {
    try {
      if (kIsWeb) return 'web';
      return Platform.operatingSystem;
    } catch (_) {
      return 'unknown';
    }
  }
}

final diagnosticsUploadProvider =
    NotifierProvider<DiagnosticsUploadNotifier, DiagnosticsUploadStatus>(
      DiagnosticsUploadNotifier.new,
    );
