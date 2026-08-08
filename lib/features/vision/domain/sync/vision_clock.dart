/// Boundaries that turn capture timestamps into monotonic session time.
library;

import '../../../../core/camera/camera_timestamp.dart';

/// A timestamp on the shared session-relative microsecond timeline.
///
/// It may be negative after applying a clock offset: a mapped timestamp can
/// legitimately precede the selected session reference instant.
final class SessionTimestamp implements Comparable<SessionTimestamp> {
  const SessionTimestamp(this.microseconds);

  final int microseconds;

  @override
  int compareTo(SessionTimestamp other) =>
      microseconds.compareTo(other.microseconds);

  SessionTimestamp operator +(Duration duration) =>
      SessionTimestamp(microseconds + duration.inMicroseconds);

  @override
  bool operator ==(Object other) =>
      other is SessionTimestamp && other.microseconds == microseconds;

  @override
  int get hashCode => microseconds.hashCode;

  @override
  String toString() => 'SessionTimestamp($microseconds µs)';
}

/// A controlled failure for timestamps that cannot form a monotonic mapping.
final class ClockMappingException implements Exception {
  const ClockMappingException(this.message);

  final String message;

  @override
  String toString() => 'ClockMappingException: $message';
}

/// Accepts camera timestamps without changing their monotonic time base.
final class VisionClock {
  CameraTimestamp? _lastTimestamp;

  /// Converts [timestamp] to the common session-relative timeline.
  ///
  /// Camera capture is documented as strictly monotonic. Rejecting a broken
  /// producer here prevents a later calibration from silently reordering it.
  SessionTimestamp toSessionTime(CameraTimestamp timestamp) {
    final previous = _lastTimestamp;
    if (previous != null && timestamp.compareTo(previous) <= 0) {
      throw ClockMappingException(
        'Vision timestamps must be strictly increasing: '
        '${timestamp.microsecondsSinceSessionStart} followed '
        '${previous.microsecondsSinceSessionStart}.',
      );
    }
    _lastTimestamp = timestamp;
    return SessionTimestamp(timestamp.microsecondsSinceSessionStart);
  }
}

/// Converts the current audio boundary's wall-clock value once, at ingress.
///
/// [reference] is supplied by the owning session or calibration flow. Only the
/// resulting [SessionTimestamp] is allowed into mapping arithmetic.
final class AudioClock {
  AudioClock({required this.reference});

  final DateTime reference;
  DateTime? _lastObservedAt;

  SessionTimestamp toSessionTime(DateTime observedAt) {
    final previous = _lastObservedAt;
    if (previous != null && observedAt.isBefore(previous)) {
      throw ClockMappingException(
        'Audio timestamps must not move backwards: $observedAt before '
        '$previous.',
      );
    }
    _lastObservedAt = observedAt;
    return SessionTimestamp(observedAt.difference(reference).inMicroseconds);
  }
}
