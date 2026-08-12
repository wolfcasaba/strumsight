/// Versioned timing and mismatch policy for target alignment.
final class TolerancePolicy {
  const TolerancePolicy();

  static const String version = 'target-alignment-tolerance.v1';
  static const double beatDurationRatio = 0.25;
  static const int minimumMilliseconds = 40;
  static const int maximumMilliseconds = 150;
  static const double missedPenalty = 1;
  static const double extraPenalty = 1;
  static const double directionMismatchPenalty = 0.5;
  static const double typeMismatchPenalty = 0.25;
  static const double confidenceMultiplierBase = 2;

  /// Returns `clamp(beatDuration * ratio, minMs, maxMs)`.
  Duration forBeatDuration(Duration beatDuration) {
    if (beatDuration <= Duration.zero) {
      throw ArgumentError.value(beatDuration, 'beatDuration');
    }
    final calculatedMicroseconds =
        (beatDuration.inMicroseconds * beatDurationRatio).round();
    final minimumMicroseconds =
        minimumMilliseconds * Duration.microsecondsPerMillisecond;
    final maximumMicroseconds =
        maximumMilliseconds * Duration.microsecondsPerMillisecond;
    return Duration(
      microseconds: calculatedMicroseconds.clamp(
        minimumMicroseconds,
        maximumMicroseconds,
      ),
    );
  }
}
