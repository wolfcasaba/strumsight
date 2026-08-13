import 'package:meta/meta.dart';

/// Immutable, widget-independent window over an analysis timeline.
///
/// The minimum visible window is deliberately expressed as one millisecond per
/// logical pixel. That makes the documented maximum zoom deterministic across
/// the painter, gestures and unit tests.
@immutable
final class TimelineViewport {
  TimelineViewport({
    required this.duration,
    required this.logicalWidth,
    required this.start,
    required this.end,
  }) : assert(!duration.isNegative),
       assert(logicalWidth > 0),
       assert(!start.isNegative),
       assert(end >= start),
       assert(end <= duration);

  TimelineViewport.full({
    required this.duration,
    required this.logicalWidth,
  }) : start = Duration.zero,
       end = duration,
       assert(!duration.isNegative),
       assert(logicalWidth > 0);

  /// The named maximum-zoom resolution from the round brief: 1 px = 1 ms.
  static const double millisecondsPerLogicalPixel = 1;

  final Duration duration;
  final double logicalWidth;
  final Duration start;
  final Duration end;

  Duration get visibleDuration => end - start;

  /// The inclusive smallest window. A clip shorter than this is never cropped.
  Duration get minimumVisibleDuration {
    final requestedMicroseconds =
        (logicalWidth * millisecondsPerLogicalPixel * 1000).round();
    return Duration(
      microseconds: requestedMicroseconds.clamp(0, duration.inMicroseconds),
    );
  }

  bool get isWithinDuration =>
      !start.isNegative && end >= start && end <= duration;

  /// Returns a window of [requestedDuration], preserving [focalTime]'s
  /// relative position where possible and clamping at clip edges.
  TimelineViewport withVisibleDuration(
    Duration requestedDuration, {
    required Duration focalTime,
  }) {
    final boundedWindow = _clampWindow(requestedDuration);
    final focal = _clampDuration(focalTime, Duration.zero, duration);
    final oldWindowMicros = visibleDuration.inMicroseconds;
    final ratio = oldWindowMicros == 0
        ? 0.5
        : ((focal - start).inMicroseconds / oldWindowMicros).clamp(0.0, 1.0);
    final rawStartMicros =
        focal.inMicroseconds - (boundedWindow.inMicroseconds * ratio).round();
    return _withClampedStart(
      Duration(microseconds: rawStartMicros),
      window: boundedWindow,
    );
  }

  TimelineViewport zoomBy({required double scale, required Duration focalTime}) {
    if (!scale.isFinite || scale <= 0) {
      throw ArgumentError.value(scale, 'scale', 'must be finite and positive');
    }
    final requestedMicros = (visibleDuration.inMicroseconds / scale).round();
    return withVisibleDuration(
      Duration(microseconds: requestedMicros),
      focalTime: focalTime,
    );
  }

  TimelineViewport panBy(Duration delta) =>
      _withClampedStart(start + delta, window: visibleDuration);

  /// Converts a horizontal logical pixel to timeline time within this window.
  Duration timeForPixel(double pixel) {
    final fraction = (pixel / logicalWidth).clamp(0.0, 1.0);
    return start +
        Duration(
          microseconds: (visibleDuration.inMicroseconds * fraction).round(),
        );
  }

  /// Converts a timeline time to a logical pixel within this window.
  double pixelForTime(Duration time) {
    if (visibleDuration == Duration.zero) return 0;
    final bounded = _clampDuration(time, start, end);
    return (bounded - start).inMicroseconds / visibleDuration.inMicroseconds *
        logicalWidth;
  }

  /// Pans or expands the current window so [rangeStart]..[rangeEnd] is visible.
  TimelineViewport revealRange(Duration rangeStart, Duration rangeEnd) {
    final boundedStart = _clampDuration(rangeStart, Duration.zero, duration);
    final boundedEnd = _clampDuration(rangeEnd, boundedStart, duration);
    if (boundedStart >= start && boundedEnd <= end) return this;
    final rangeLength = boundedEnd - boundedStart;
    if (rangeLength >= visibleDuration) {
      return _withClampedStart(boundedStart, window: visibleDuration);
    }
    if (boundedStart < start) {
      return _withClampedStart(boundedStart, window: visibleDuration);
    }
    return _withClampedStart(boundedEnd - visibleDuration, window: visibleDuration);
  }

  Duration _clampWindow(Duration requested) {
    final minimum = minimumVisibleDuration;
    return _clampDuration(requested, minimum, duration);
  }

  TimelineViewport _withClampedStart(Duration requestedStart, {Duration? window}) {
    final selectedWindow = window ?? _clampWindow(visibleDuration);
    final maxStart = duration - selectedWindow;
    final clampedStart = _clampDuration(requestedStart, Duration.zero, maxStart);
    return TimelineViewport(
      duration: duration,
      logicalWidth: logicalWidth,
      start: clampedStart,
      end: clampedStart + selectedWindow,
    );
  }

  static Duration _clampDuration(Duration value, Duration lower, Duration upper) {
    final clamped = value.inMicroseconds.clamp(
      lower.inMicroseconds,
      upper.inMicroseconds,
    );
    return Duration(microseconds: clamped);
  }
}
