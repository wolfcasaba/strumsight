/// A drop-oldest rolling buffer of recent microphone PCM, used by the Lab-mode
/// Live capture (r199). Holds at most [maxSeconds] of audio at the mic's actual
/// sample rate; older samples are dropped as new chunks arrive.
///
/// Zero overhead until it is [enabled] AND a [sampleRate] is known — the
/// default Live path never touches it. Trimming keeps a 1 s slack so the O(n)
/// front-drop runs at most ~once per second rather than on every chunk.
class PcmRingBuffer {
  PcmRingBuffer({this.maxSeconds = 30});

  /// How many seconds of the most recent audio to retain.
  final int maxSeconds;

  final List<double> _ring = [];

  /// Whether new chunks are retained. Off → [add] is a no-op (no allocation).
  bool enabled = false;

  /// The actual mic sample rate (set once the mic reports it).
  int sampleRate = 0;

  /// Append a mic [chunk]; no-op when disabled or the rate is unknown.
  void add(List<double> chunk) {
    if (!enabled || sampleRate <= 0) return;
    _ring.addAll(chunk);
    final max = maxSeconds * sampleRate;
    // Trim only once past a 1 s slack so the front-drop amortises to ~1/s.
    if (_ring.length > max + sampleRate) {
      _ring.removeRange(0, _ring.length - max);
    }
  }

  /// A COPY of the retained PCM plus its sample rate (empty when nothing held).
  (List<double>, int) recent() => (List<double>.from(_ring), sampleRate);

  /// Number of samples currently retained (for tests/introspection).
  int get length => _ring.length;

  /// Drop the buffered audio but keep the rate + enabled flag.
  void clear() => _ring.clear();

  /// Full reset (buffer + rate) — used when the mic stops.
  void reset() {
    _ring.clear();
    sampleRate = 0;
  }
}
