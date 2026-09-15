import 'dart:typed_data';

/// Re-frames an arbitrary-size sample stream into fixed [window]-length frames
/// advancing by [hop] (RAG chunk 001: mic chunk size ≠ analysis frame size).
///
/// **Allocation profile** (D4 latency round). This sits on the hottest hop of
/// the capture path — every mic chunk crosses it twice (onset + chord framer).
/// The pending-sample store is therefore a plain [Float64List] with a fill
/// pointer, grown by doubling, so a steady mic stream allocates NOTHING here
/// beyond the frames it yields: the capacity settles after the first chunk and
/// the leftover tail is moved down in place. It used to be a growable
/// `List<double>` (boxed doubles) sliced with `sublist` before a
/// `Float64List.fromList` copy — two allocations plus a boxed element-by-
/// element copy per frame, plus an O(n) `removeRange` shift per chunk.
///
/// The yielded frames stay FRESH [Float64List]s, one per frame: downstream
/// consumers retain them (the strum classifier keeps a post-onset evidence
/// ring of frames), so recycling one output buffer would silently rewrite
/// their history. Behaviour is therefore bit-identical to the old version.
class SlidingFramer {
  SlidingFramer({required this.window, required this.hop})
    : assert(hop <= window),
      _buffer = Float64List(window);

  final int window;
  final int hop;

  /// Samples accepted but not yet consumed by a frame. Only `[0, _fill)` holds
  /// live data; the rest is spare capacity.
  Float64List _buffer;
  int _fill = 0;

  /// Add a chunk; yields every complete frame that becomes available.
  Iterable<Float64List> add(List<double> chunk) sync* {
    _append(chunk);
    var start = 0;
    while (start + window <= _fill) {
      final frame = Float64List(window);
      frame.setRange(0, window, _buffer, start);
      yield frame;
      start += hop;
    }
    if (start > 0) _dropFront(start);
  }

  void reset() => _fill = 0;

  void _append(List<double> chunk) {
    final count = chunk.length;
    if (count == 0) return;
    _ensureCapacity(_fill + count);
    // A typed memcpy when the caller already hands us a Float64List (which the
    // mic path does, normalized once at the capture boundary).
    _buffer.setRange(_fill, _fill + count, chunk);
    _fill += count;
  }

  void _ensureCapacity(int needed) {
    if (needed <= _buffer.length) return;
    var capacity = _buffer.isEmpty ? 1 : _buffer.length;
    while (capacity < needed) {
      capacity *= 2;
    }
    final grown = Float64List(capacity);
    grown.setRange(0, _fill, _buffer);
    _buffer = grown;
  }

  /// Drops the [count] samples the emitted frames have consumed. A FORWARD
  /// copy (destination index is always below the source index) so the in-place
  /// move needs no temporary; the surviving tail is shorter than one [window]
  /// by construction, so this is bounded work per chunk.
  void _dropFront(int count) {
    final remaining = _fill - count;
    for (var i = 0; i < remaining; i++) {
      _buffer[i] = _buffer[count + i];
    }
    _fill = remaining;
  }
}
