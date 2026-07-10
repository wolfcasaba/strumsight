/// Rock-Band-style tap-test maths (RAG chunk 016b P3) — pure & testable.
///
/// The user taps along an audible click with period [beatPeriodSec]. Each
/// tap's signed offset from its nearest beat is collected; the device's
/// input+audio latency is the **median** of the valid offsets (robust to a
/// couple of botched taps), and the **median absolute deviation** reports
/// whether the user tapped consistently enough to trust the result.
class LatencyCalibrator {
  LatencyCalibrator({
    this.beatPeriodSec = 0.6, // 100 BPM
    this.maxAbsOffsetSec = 0.25,
    this.minSamples = 5,
  });

  final double beatPeriodSec;

  /// Taps farther than this from every beat are discarded as botched.
  final double maxAbsOffsetSec;

  /// Valid taps needed before [offsetSec] reports a value.
  final int minSamples;

  final List<double> _offsets = [];

  /// Register a tap at [tapSec] (seconds on the same clock as the beats,
  /// beats at integer multiples of [beatPeriodSec]). Returns the tap's signed
  /// offset when it counted, or null when it was discarded as botched.
  double? registerTap(double tapSec) {
    final nearest = (tapSec / beatPeriodSec).round() * beatPeriodSec;
    final offset = tapSec - nearest;
    if (offset.abs() > maxAbsOffsetSec) return null;
    _offsets.add(offset);
    return offset;
  }

  int get sampleCount => _offsets.length;

  /// The calibrated latency (positive = the user's taps/mic arrive LATE), or
  /// null until [minSamples] valid taps have been collected. Median.
  double? get offsetSec {
    if (_offsets.length < minSamples) return null;
    return _median(List.of(_offsets));
  }

  /// Median absolute deviation of the offsets — tap consistency.
  double get jitterSec {
    if (_offsets.length < 2) return 0;
    final m = _median(List.of(_offsets));
    return _median([for (final o in _offsets) (o - m).abs()]);
  }

  /// A result worth saving: enough taps, and consistent within ±40 ms.
  bool get isStable => offsetSec != null && jitterSec <= 0.04;

  void reset() => _offsets.clear();

  static double _median(List<double> xs) {
    xs.sort();
    final n = xs.length;
    return n.isOdd ? xs[n ~/ 2] : (xs[n ~/ 2 - 1] + xs[n ~/ 2]) / 2;
  }
}
