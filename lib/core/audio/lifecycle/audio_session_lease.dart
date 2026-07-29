/// Everything that may own the microphone (SDD Ch2, Kör 9 §9.2).
///
/// The owner is part of the contract: a busy failure names who holds the mic,
/// and the log line says which feature refused to let go.
enum AudioOwner {
  live,
  tuner,
  analyzeRecorder,
  latencyCalibration,
  diagnostics,
}

/// The right to use the microphone, handed out by the
/// `AudioSessionCoordinator`. Exactly one lease can be active at a time.
///
/// A lease is single-use: once released (by its owner, or revoked when the app
/// leaves the foreground) it stays inactive — acquiring again returns a new
/// one, so a stale reference can never re-open the microphone.
abstract interface class AudioSessionLease {
  AudioOwner get owner;

  /// False once released or revoked.
  bool get isActive;

  /// Gives the microphone back. Idempotent — releasing twice is not an error,
  /// and a lease that was already revoked releases into a no-op instead of
  /// stealing the session from whoever acquired it next.
  Future<void> release();
}
