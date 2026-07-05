import 'dart:typed_data';

/// Re-frames an arbitrary-size sample stream into fixed [window]-length frames
/// advancing by [hop] (RAG chunk 001: mic chunk size ≠ analysis frame size).
class SlidingFramer {
  SlidingFramer({required this.window, required this.hop})
      : assert(hop <= window);

  final int window;
  final int hop;

  final List<double> _buffer = [];

  /// Add a chunk; yields every complete frame that becomes available.
  Iterable<Float64List> add(List<double> chunk) sync* {
    _buffer.addAll(chunk);
    var start = 0;
    while (start + window <= _buffer.length) {
      yield Float64List.fromList(_buffer.sublist(start, start + window));
      start += hop;
    }
    if (start > 0) _buffer.removeRange(0, start);
  }

  void reset() => _buffer.clear();
}
