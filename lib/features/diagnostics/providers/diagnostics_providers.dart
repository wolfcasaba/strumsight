import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../analyze/model/analyze_result.dart';
import '../data/diagnostics_uploader.dart';
import '../model/diagnostics_session.dart';

/// The best-effort diagnostics uploader (injectable for tests via override).
final diagnosticsUploaderProvider = Provider<DiagnosticsUploader>(
  (_) => DiagnosticsUploader(),
);

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
  /// the Analyze result. No-op if the result carries no diagnostics.
  Future<void> upload(AnalyzeResult result, List<double> pcm, int sr) async {
    if (result.diagnostics == null) return;
    state = DiagnosticsUploadStatus.uploading;

    final appVersion = await _appVersion();
    final device = _device();
    final clip = DiagnosticsUploader.clipFromPcm(pcm, sr);
    final session = DiagnosticsSession(
      sessionId: DateTime.now().microsecondsSinceEpoch.toString(),
      appVersion: appVersion,
      device: device,
      startedAt: DateTime.now().toUtc().toIso8601String(),
      events: DiagnosticsSession.eventsFrom(result),
      audioClips: clip == null ? const [] : [clip],
    );

    final status = await ref
        .read(diagnosticsUploaderProvider)
        .upload(session, appVersion: appVersion, device: device);
    state = status;
  }

  Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return 'unknown';
    }
  }

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
