abstract interface class SongTransportClock {
  Duration get elapsed;

  void start();
  void stop();
  void reset();
}

final class StopwatchSongTransportClock implements SongTransportClock {
  final Stopwatch _stopwatch = Stopwatch();

  @override
  Duration get elapsed => _stopwatch.elapsed;

  @override
  void reset() => _stopwatch.reset();

  @override
  void start() => _stopwatch.start();

  @override
  void stop() => _stopwatch.stop();
}

final class FakeSongTransportClock implements SongTransportClock {
  Duration _elapsed = Duration.zero;
  bool _running = false;

  @override
  Duration get elapsed => _elapsed;

  void advance(Duration amount) {
    if (amount.isNegative) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Clock cannot advance backward.',
      );
    }
    if (_running) _elapsed += amount;
  }

  @override
  void reset() => _elapsed = Duration.zero;

  @override
  void start() => _running = true;

  @override
  void stop() => _running = false;
}
