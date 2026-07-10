/// Pure tap-tempo estimator: tap along and it averages the recent inter-tap
/// intervals into a BPM. A gap longer than [resetAfter] starts a fresh count
/// (you're setting a new tempo, not continuing the old one). Clock is injected
/// so it's fully unit-testable.
class TapTempo {
  TapTempo({
    this.maxTaps = 6,
    this.resetAfter = const Duration(seconds: 2),
    this.minBpm = 30,
    this.maxBpm = 300,
  });

  /// How many recent taps to average over (a rolling window).
  final int maxTaps;

  /// A gap beyond this resets the running average.
  final Duration resetAfter;

  final int minBpm;
  final int maxBpm;

  final List<DateTime> _taps = [];

  /// Number of taps currently retained.
  int get count => _taps.length;

  void reset() => _taps.clear();

  /// Register a tap at [now]; returns the current BPM estimate, or null if there
  /// aren't yet two taps to measure an interval.
  int? tap(DateTime now) {
    if (_taps.isNotEmpty && now.difference(_taps.last) > resetAfter) {
      _taps.clear();
    }
    _taps.add(now);
    if (_taps.length > maxTaps) _taps.removeAt(0);
    return bpm;
  }

  /// The current BPM estimate from the retained taps, or null if < 2 taps.
  int? get bpm {
    if (_taps.length < 2) return null;
    final totalMs =
        _taps.last.difference(_taps.first).inMicroseconds / 1000.0;
    final avgMs = totalMs / (_taps.length - 1);
    if (avgMs <= 0) return null;
    final raw = (60000.0 / avgMs).round();
    return raw.clamp(minBpm, maxBpm);
  }
}
