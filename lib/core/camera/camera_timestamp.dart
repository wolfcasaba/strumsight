/// A non-negative monotonic timestamp assigned by a camera session.
///
/// It intentionally contains no wall-clock date: capture ordering must remain
/// meaningful when the device clock changes during a session.
final class CameraTimestamp implements Comparable<CameraTimestamp> {
  const CameraTimestamp(this.microsecondsSinceSessionStart)
    : assert(microsecondsSinceSessionStart >= 0);

  final int microsecondsSinceSessionStart;

  @override
  int compareTo(CameraTimestamp other) => microsecondsSinceSessionStart
      .compareTo(other.microsecondsSinceSessionStart);

  CameraTimestamp advanceBy(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'Must not be negative.');
    }
    return CameraTimestamp(
      microsecondsSinceSessionStart + duration.inMicroseconds,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CameraTimestamp &&
      other.microsecondsSinceSessionStart == microsecondsSinceSessionStart;

  @override
  int get hashCode => microsecondsSinceSessionStart.hashCode;

  @override
  String toString() => 'CameraTimestamp($microsecondsSinceSessionStart µs)';
}
