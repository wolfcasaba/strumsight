import 'package:flutter/material.dart';

import '../../../../core/music/strum.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/model/compiled_practice_target.dart';
import '../../domain/model/meter.dart';

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
    return Semantics(
      container: true,
      label: l10n.practiceHighwayLabel,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Color(0xFF0E0E12)),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _HighwayBackgroundPainter(
                            playhead: widget.playhead,
                            pixelsPerSecond: widget.pixelsPerSecond,
                            strikeX: widget.strikeX,
                            visibleSeconds: widget.visibleSeconds,
                            behindSeconds: widget.behindSeconds,
                            meter: widget.target.meter,
                            leftHanded: widget.leftHanded,
                          ),
                        ),
                      ),
                    ),
                    for (final candidate in candidates)
                      _Marker(
                        candidate: candidate,
                        height: widget.height,
                        leftHanded: widget.leftHanded,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Candidate {
  const _Candidate({required this.event, required this.x});
  final CompiledTargetEvent event;
  final double x;
}

class _Marker extends StatelessWidget {
  const _Marker({
    required this.candidate,
    required this.height,
    required this.leftHanded,
  });

  static const double width = 64;

  final _Candidate candidate;
  final double height;
  final bool leftHanded;

  @override
  Widget build(BuildContext context) {
    final event = candidate.event;
    final isRest = event.direction == null;
    final color = isRest
        ? AppColors.primary.withValues(alpha: 0.55)
        : (event.direction == StrumDirection.down
              ? AppColors.primary
              : AppColors.confidenceHigh);
    final x = candidate.x;
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
    required this.pixelsPerSecond,
    required this.strikeX,
    required this.visibleSeconds,
    required this.behindSeconds,
    required this.meter,
    required this.leftHanded,
  });

  final Duration playhead;
  final double pixelsPerSecond;
  final double strikeX;
  final double visibleSeconds;
  final double behindSeconds;
  final Meter meter;
  final bool leftHanded;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final beatsPerBar = meter.beatsPerBar;
    const secPerBeat = 0.5; // 120 BPM
    final pxPerBeat = pixelsPerSecond * secPerBeat;
    if (pxPerBeat <= 0) return;
    final playheadSeconds =
        playhead.inMicroseconds / Duration.microsecondsPerSecond;
    final firstBeat = (playheadSeconds - behindSeconds) / secPerBeat;
    final lastBeat = (playheadSeconds + visibleSeconds) / secPerBeat;
    final line = Paint()..strokeWidth = 1;
    for (var b = firstBeat.floorToDouble(); b <= lastBeat + 1; b += 1) {
      final x = strikeX + (b - playheadSeconds) * pxPerBeat;
      if (x < -2 || x > size.width + 2) continue;
      final isDownbeat = (b % beatsPerBar).abs() < 1e-6;
      line
        ..strokeWidth = isDownbeat ? 2 : 1
        ..color = (isDownbeat ? AppColors.primary : Colors.white).withValues(
          alpha: isDownbeat ? 0.20 : 0.08,
        );
      canvas.drawLine(Offset(x, 0), Offset(x, h), line);
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
      old.pixelsPerSecond != pixelsPerSecond ||
      old.strikeX != strikeX ||
      old.visibleSeconds != visibleSeconds ||
      old.behindSeconds != behindSeconds ||
      old.meter != meter ||
      old.leftHanded != leftHanded;
}
