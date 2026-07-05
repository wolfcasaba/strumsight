import 'dart:collection';

/// BPM from inter-onset intervals (RAG chunk 007): median IOI over the last
/// 8 onsets, folded into 60–200 BPM, EMA-smoothed. Pure and tiny.
class TempoTracker {
  final ListQueue<double> _onsets = ListQueue();
  double _bpm = 0;

  static const _maxOnsets = 8;
  static const _minBpm = 60.0;
  static const _maxBpm = 200.0;

  double get bpm => _bpm;

  void addOnset(double timeSec) {
    // A long gap means the player stopped — restart the estimate.
    if (_onsets.isNotEmpty && timeSec - _onsets.last > 2.0) {
      _onsets.clear();
      _bpm = 0;
    }
    _onsets.addLast(timeSec);
    if (_onsets.length > _maxOnsets) _onsets.removeFirst();
    if (_onsets.length < 3) return;

    final times = _onsets.toList();
    final iois = [
      for (var i = 1; i < times.length; i++) times[i] - times[i - 1],
    ]..sort();
    final mid = iois.length ~/ 2;
    final medianIoi =
        iois.length.isOdd ? iois[mid] : (iois[mid - 1] + iois[mid]) / 2;
    if (medianIoi <= 0) return;

    // Fold eighth/half-time interpretations into the displayable range.
    var candidate = 60 / medianIoi;
    while (candidate < _minBpm) {
      candidate *= 2;
    }
    while (candidate > _maxBpm) {
      candidate /= 2;
    }

    _bpm = _bpm == 0 ? candidate : 0.8 * _bpm + 0.2 * candidate;
  }

  void reset() {
    _onsets.clear();
    _bpm = 0;
  }
}
