import 'package:flutter/material.dart';

import '../../../../core/music/strum.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/model/compiled_practice_target.dart';
import '../../domain/model/meter.dart';
import '../../domain/model/tempo.dart';

/// Pure horizontal-position function for a single target event on the
/// practice highway (ADR 0080 D2).
///
/// `x = strikeX + (targetTime − playhead + visualOffset) * pixelsPerSecond`.
///
/// When `targetTime == playhead` and `visualOffset == 0` the result is
/// **exactly** `strikeX` (no `closeTo`, no fudge). The function is pure
/// (no widget dependencies) so the A1 matrix can be asserted directly on
/// the math, and the widget only has to consume the value.
double targetX({
  required Duration targetTime,
  required Duration playhead,
  required Duration visualOffset,
  required double pixelsPerSecond,
  required double strikeX,
}) {
  final delta =
      (targetTime - playhead).inMicroseconds / Duration.microsecondsPerSecond;
  final offset = visualOffset.inMicroseconds / Duration.microsecondsPerSecond;
  return strikeX + (delta + offset) * pixelsPerSecond;
}

/// Pure helper: is the candidate x-coordinate inside the visible lane plus
/// the fixed margin? Used to decide whether a target event should be built
/// at all (ADR 0080 D5).
bool targetInVisibilityWindow(double x, double width, double margin) {
  return x >= -margin && x <= width + margin;
}

/// Returns the leftmost index whose [CompiledTargetEvent.time] is >= the
/// lower bound. Pure over the sorted [events] list — used by the highway
/// to bound the per-frame scan (ADR 0080 D5).
int lowerBoundTime(List<CompiledTargetEvent> events, Duration lower) {
  var lo = 0;
  var hi = events.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (events[mid].time.inMicroseconds < lower.inMicroseconds) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// The wide Practice V2 highway: a scrollable lane of [CompiledTargetEvent]
/// records moving toward a fixed strike line. Built only from the compiled
/// target — the Learn `Lesson` model is never imported (ADR 0080 D1).
class PracticeHighway extends StatefulWidget {
  const PracticeHighway({
    required this.target,
    required this.playhead,
    required this.width,
    required this.height,
    required this.strikeX,
    required this.pixelsPerSecond,
    required this.visibleSeconds,
    required this.behindSeconds,
    this.visualOffset = Duration.zero,
    this.leftHanded = false,
    super.key,
  });

  final CompiledPracticeTarget target;
  final Duration playhead;
  final Duration visualOffset;
  final double width;
  final double height;
  final double strikeX;
  final double pixelsPerSecond;
  final double visibleSeconds;
  final double behindSeconds;

  /// When true the lane is visually mirrored — the down/up icons keep their
  /// semantic meaning (SDD §22.2: the [StrumDirection] interpretation does
  /// not flip). The marker scan, the target positions, and the bar/beat
  /// grid all flow through the same `targetX` math, so only the painter
  /// flips the lane horizontally.
  final bool leftHanded;

  @override
  State<PracticeHighway> createState() => _PracticeHighwayState();
}

class _PracticeHighwayState extends State<PracticeHighway> {
  /// Records examined during the last build, including those filtered out
  /// by the visibility window. Exposed so the A7 scaling test can confirm
  /// the lane is bounded (not the full list) — the scan starts at the
  /// binary-search lower bound and stops at the first record past the
  /// upper bound.
  @visibleForTesting
  int lastExaminedRecordCount = 0;

  @override
  Widget build(BuildContext context) {
    final candidates = <_Candidate>[];
    final events = widget.target.events;
    final lower =
        widget.playhead -
        Duration(milliseconds: (widget.behindSeconds * 1000).round());
    final upper =
        widget.playhead +
        Duration(milliseconds: (widget.visibleSeconds * 1000).round());
    final start = lowerBoundTime(events, lower);
    var examined = 0;
    final margin = widget.pixelsPerSecond;
    for (var i = start; i < events.length; i++) {
      final event = events[i];
      examined++;
      if (event.time > upper) break;
      final x = targetX(
        targetTime: event.time,
        playhead: widget.playhead,
        visualOffset: widget.visualOffset,
        pixelsPerSecond: widget.pixelsPerSecond,
        strikeX: widget.strikeX,
      );
      if (!targetInVisibilityWindow(x, widget.width, margin)) continue;
      candidates.add(_Candidate(event: event, x: x));
    }
    lastExaminedRecordCount = examined;

    final l10n = AppLocalizations.of(context);
    final lane = Semantics(
      container: true,
      label: l10n.practiceHighwayLabel,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stack = Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _HighwayBackgroundPainter(
                        playhead: widget.playhead,
                        visualOffset: widget.visualOffset,
                        pixelsPerSecond: widget.pixelsPerSecond,
                        strikeX: widget.strikeX,
                        visibleSeconds: widget.visibleSeconds,
                        behindSeconds: widget.behindSeconds,
                        meter: widget.target.meter,
                        tempo: widget.target.tempo,
                        barBoundaries: widget.target.barBoundaries,
                        leftHanded: widget.leftHanded,
                      ),
                    ),
                  ),
                ),
                for (final candidate in candidates)
                  PracticeTargetMarker(
                    event: candidate.event,
                    x: candidate.x,
                    height: widget.height,
                  ),
              ],
            );
            return ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Color(0xFF0E0E12)),
                child: widget.leftHanded
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
                        child: stack,
                      )
                    : stack,
              ),
            );
          },
        ),
      ),
    );
    return lane;
  }
}

class _Candidate {
  const _Candidate({required this.event, required this.x});
  final CompiledTargetEvent event;
  final double x;
}

/// Single target marker rendered on the practice highway.
///
/// Public (rather than a private `_Marker`) so the A7 scaling test can
/// assert on the count of built markers with `find.byType(
/// PracticeTargetMarker)` — the brief's measurement handle.
class PracticeTargetMarker extends StatelessWidget {
  const PracticeTargetMarker({
    required this.event,
    required this.x,
    required this.height,
    super.key,
  });

  static const double width = 64;

  final CompiledTargetEvent event;
  final double x;
  final double height;

  @override
  Widget build(BuildContext context) {
    final isRest = event.direction == null;
    final color = isRest
        ? AppColors.primary.withValues(alpha: 0.55)
        : (event.direction == StrumDirection.down
              ? AppColors.primary
              : AppColors.confidenceHigh);
    final icon = isRest
        ? Icons.remove
        : (event.direction == StrumDirection.down
              ? Icons.arrow_downward
              : Icons.arrow_upward);
    final semanticLabel = isRest
        ? AppLocalizations.of(context).practiceHighwayRestMarker
        : (event.direction == StrumDirection.down
              ? AppLocalizations.of(context).strumDown
              : AppLocalizations.of(context).strumUp);
    return Positioned(
      left: x - width / 2,
      top: 0,
      bottom: 0,
      child: SizedBox(
        width: width,
        child: Center(
          child: Semantics(
            label: semanticLabel,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: isRest ? 0.12 : 0.22),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}

class _HighwayBackgroundPainter extends CustomPainter {
  _HighwayBackgroundPainter({
    required this.playhead,
    required this.visualOffset,
    required this.pixelsPerSecond,
    required this.strikeX,
    required this.visibleSeconds,
    required this.behindSeconds,
    required this.meter,
    required this.tempo,
    required this.barBoundaries,
    required this.leftHanded,
  });

  final Duration playhead;
  final Duration visualOffset;
  final double pixelsPerSecond;
  final double strikeX;
  final double visibleSeconds;
  final double behindSeconds;
  final Meter meter;
  final Tempo tempo;
  final List<Duration> barBoundaries;
  final bool leftHanded;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final beatsPerBar = meter.beatsPerBar;
    // Tempo drives the beat grid: 60/bpm seconds per beat. The previous
    // hardcoded 0.5 (= 120 BPM) drifted on every real practice — the
    // catalog is 60–90 BPM, so the downbeats ended up two beats off.
    final secPerBeat = tempo.bpm > 0 ? 60.0 / tempo.bpm : 0.5;
    final pxPerBeat = pixelsPerSecond * secPerBeat;
    final playheadSeconds =
        playhead.inMicroseconds / Duration.microsecondsPerSecond;
    final visualOffsetSeconds =
        visualOffset.inMicroseconds / Duration.microsecondsPerSecond;

    double xAt(Duration t) {
      final delta =
          (t.inMicroseconds / Duration.microsecondsPerSecond) -
          playheadSeconds +
          visualOffsetSeconds;
      return strikeX + delta * pixelsPerSecond;
    }

    final line = Paint()..strokeWidth = 1;

    // --- Bar lines: drawn from the compiled `barBoundaries`, which the
    // compiler produced for the actual tempo + meter (R06). The grid and
    // the markers therefore share the SAME time→x math.
    if (barBoundaries.isNotEmpty && pxPerBeat > 0) {
      for (final barStart in barBoundaries) {
        final x = xAt(barStart);
        if (x < -2 || x > size.width + 2) continue;
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, h),
          line
            ..strokeWidth = 2
            ..color = AppColors.primary.withValues(alpha: 0.20),
        );
      }
    }

    // --- Beat lines within the visible window. The first beat of each bar
    // is already drawn above (the bar line is the downbeat); we draw the
    // remaining `beatsPerBar - 1` beats per bar from the bar start.
    if (pxPerBeat > 0 && beatsPerBar > 1) {
      final firstBeat = (playheadSeconds - behindSeconds) / secPerBeat;
      final lastBeat = (playheadSeconds + visibleSeconds) / secPerBeat;
      for (var b = firstBeat.floorToDouble(); b <= lastBeat + 1; b += 1) {
        if (b <= firstBeat.floorToDouble()) continue;
        final x = strikeX + (b - playheadSeconds) * pxPerBeat;
        if (x < -2 || x > size.width + 2) continue;
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, h),
          line
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.08),
        );
      }
    }

    final cy = h / 2;
    final r = h * 0.62;
    canvas.drawRect(
      Rect.fromLTWH(strikeX - r, 0, r * 2, h),
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.34),
            AppColors.primary.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(strikeX, cy), radius: r)),
    );
    canvas.drawLine(
      Offset(strikeX, 0),
      Offset(strikeX, h),
      Paint()
        ..strokeWidth = 3
        ..color = AppColors.primary.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_HighwayBackgroundPainter old) =>
      old.playhead != playhead ||
      old.visualOffset != visualOffset ||
      old.pixelsPerSecond != pixelsPerSecond ||
      old.strikeX != strikeX ||
      old.visibleSeconds != visibleSeconds ||
      old.behindSeconds != behindSeconds ||
      old.meter != meter ||
      old.tempo != tempo ||
      old.barBoundaries != barBoundaries ||
      old.leftHanded != leftHanded;
}
