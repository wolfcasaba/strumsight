import 'dart:async';

import '../foundation/app_failure.dart';
import '../foundation/app_result.dart';
import '../platform/microphone_permission.dart';
import 'capture/audio_capture.dart';
import 'capture/audio_capture_factory.dart';
import 'lifecycle/audio_session_coordinator.dart';
import 'lifecycle/audio_session_lease.dart';

/// One microphone session for one owner (RAG chunk 001, SDD Ch2 Kör 9).
///
/// Every mic user (Live, Tuner, Analyze recorder) goes through this class, and
/// it enforces the three rules that used to be re-implemented per engine:
///
/// 1. **permission first** — an unknown permission state is never "granted";
/// 2. **exclusive session** — the [AudioSessionCoordinator] lease means a
///    second owner gets a busy failure instead of stealing a live capture;
/// 3. **no orphan stream** — every failure path (denied, busy, engine throw,
///    a stop that lands mid-handshake) releases both the capture and the lease.
///
/// [start] is single-flight: a second call while one is in flight joins it
/// instead of opening a second capture (round 101 lesson, now shared).
class MicCapture {
  MicCapture({
    required this.owner,
    required this._coordinator,
    this._permissions = const PermissionHandlerMicrophoneGateway(),
    this._captureFactory = createPlatformAudioCapture,
  });

  final AudioOwner owner;
  final AudioSessionCoordinator _coordinator;
  final MicrophonePermissionGateway _permissions;
  final AudioCaptureFactory _captureFactory;

  AudioSessionLease? _lease;
  AudioCapture? _capture;
  int _sampleRate = 0;
  bool _stopRequested = false;
  Future<AppResult<int>>? _inFlight;

  /// Whether a capture is currently running for this owner.
  bool get isActive => _capture != null;

  /// The permission state, asking the user only when it is not granted yet.
  Future<MicrophonePermissionState> ensurePermission() async {
    final current = await _permissions.currentState();
    if (current.isGranted) return current;
    return _permissions.request();
  }

  /// Starts capture; the value is the ACTUAL sample rate.
  ///
  /// [onRevoke] is what the coordinator calls when the app goes to the
  /// background; it defaults to [stop], which is enough for a plain capture.
  /// Engines pass their own teardown so the DSP isolate dies with the stream.
  Future<AppResult<int>> start(
    void Function(List<double> chunk) onChunk, {
    Future<void> Function()? onRevoke,
  }) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    if (_capture != null) return Future.value(Success(_sampleRate));
    _stopRequested = false;
    return _inFlight = _doStart(
      onChunk,
      onRevoke,
    ).whenComplete(() => _inFlight = null);
  }

  Future<AppResult<int>> _doStart(
    void Function(List<double> chunk) onChunk,
    Future<void> Function()? onRevoke,
  ) async {
    final permission = await ensurePermission();
    if (!permission.isGranted) return Failure(permission.failure!);
    // The user may have left the screen while the dialog was up (§9.3): honour
    // the stop instead of opening a microphone nobody is watching.
    if (_stopRequested) return const Failure(CancelledFailure());

    final leaseResult = await _coordinator.acquire(
      owner,
      onRevoke: onRevoke ?? stop,
    );
    if (leaseResult case Failure<AudioSessionLease>(:final error)) {
      return Failure(error);
    }
    final lease = (leaseResult as Success<AudioSessionLease>).value;
    if (_stopRequested) {
      await lease.release();
      return const Failure(CancelledFailure());
    }
    _lease = lease;

    final capture = _captureFactory();
    try {
      _sampleRate = await capture.start(onChunk);
    } catch (error, stackTrace) {
      // Busy device, revoked mid-handshake, platform channel error: unwind
      // completely so a retry starts from a clean state.
      await capture.stop();
      await _release(lease);
      return Failure(
        AudioFailure(
          code: FailureCode.audioCaptureFailed,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
    if (_stopRequested) {
      // stop() landed while the platform was handing us the stream — it could
      // not cancel a capture that did not exist yet, so do it here.
      await capture.stop();
      await _release(lease);
      return const Failure(CancelledFailure());
    }
    _capture = capture;
    return Success(_sampleRate);
  }

  /// Stops the capture and gives the session back. Idempotent, and safe to
  /// call while a [start] is still in flight — that start then unwinds itself.
  Future<void> stop() async {
    _stopRequested = true;
    final capture = _capture;
    _capture = null;
    await capture?.stop();
    final lease = _lease;
    if (lease != null) await _release(lease);
  }

  Future<void> _release(AudioSessionLease lease) async {
    if (identical(_lease, lease)) _lease = null;
    await lease.release();
  }
}
