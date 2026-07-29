import 'dart:async';

import 'package:audio_streamer/audio_streamer.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:permission_handler/permission_handler.dart';

import '../foundation/app_failure.dart';
import '../foundation/app_result.dart';

/// Thin wrapper around the mic PCM stream + runtime permission (RAG chunk
/// 001). Both real engines share it; stop() actually releases the microphone.
class MicCapture {
  StreamSubscription<List<double>>? _sub;

  /// Whether mic permission is granted, requesting it if needed.
  ///
  /// Convenience view of [requestPermission] for the existing call sites: a
  /// failure — denied OR a platform error — is false, so the caller shows the
  /// mic-error banner instead of starting a capture that cannot work.
  static Future<bool> ensurePermission() async =>
      (await requestPermission()).isSuccess;

  /// Ask for the microphone permission, reporting *why* it is unavailable.
  ///
  /// The only error treated as "granted" is a [MissingPluginException], i.e.
  /// there is no permission channel at all (host widget tests, desktop dev) —
  /// there is no permission system to deny us. Any other platform error is a
  /// [PermissionFailure]: an unknown error is never reported as success
  /// (E01-R04 §4.5). Tests that need a *denied* path inject a fake instead
  /// (see `ClipRecorder.ensurePermission`).
  static Future<AppResult<void>> requestPermission() async {
    try {
      final status = await Permission.microphone.status;
      if (status.isGranted) return const Success(null);
      final result = await Permission.microphone.request();
      if (result.isGranted) return const Success(null);
      return Failure(
        PermissionFailure(
          code: FailureCode.permissionMicrophoneDenied,
          // Permanently denied ⇒ retrying the dialog cannot help; the user
          // has to change it in system settings.
          retryable: !result.isPermanentlyDenied,
        ),
      );
    } on MissingPluginException {
      // No permission platform channel — nothing can deny us here.
      return const Success(null);
    } catch (e, stackTrace) {
      return Failure(
        PermissionFailure(
          code: FailureCode.permissionUnavailable,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Start streaming; [onChunk] receives PCM chunks (-1..1, mono). Returns the
  /// ACTUAL sample rate (may differ from the requested 44.1 kHz — chunk 001).
  Future<int> start(void Function(List<double> chunk) onChunk) async {
    final streamer = AudioStreamer();
    streamer.sampleRate = 44100;
    _sub = streamer.audioStream.listen(onChunk);
    return streamer.actualSampleRate;
  }

  /// Stop streaming and release the microphone.
  Future<void> stop() async {
    // Only null the field if it still points at the subscription WE are
    // cancelling — a start() racing this await may already have installed a
    // new one, and blindly nulling would orphan it live (round 114).
    final sub = _sub;
    await sub?.cancel();
    if (identical(_sub, sub)) _sub = null;
  }
}
