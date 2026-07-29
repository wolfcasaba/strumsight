/// A raw microphone PCM source (SDD Ch2, Kör 9).
///
/// The engines depend on this interface, never on the capture plugin, so a
/// test can drive chunk delivery, a start failure or a stop race deterministic-
/// ally — without a platform channel.
abstract interface class AudioCapture {
  /// Starts the stream and returns the ACTUAL sample rate, which may differ
  /// from the requested one (RAG chunk 001 — the device decides).
  ///
  /// Throws when the microphone cannot be opened (busy, revoked mid-handshake,
  /// platform error); the caller turns that into an [AppFailure].
  Future<int> start(void Function(List<double> chunk) onChunk);

  /// Cancels the subscription and releases the microphone. Idempotent.
  Future<void> stop();
}
