import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../lesson_timing.dart';
import '../model/lesson.dart';

/// StrumSight's own play-along animation (not a note-highway clone): chord +
/// **↓/↑ arrow** cards flow right-to-left toward a fixed **strike line**, and
/// pulse as they cross it. Down-strokes are copper, up-strokes are the
/// confidence green — the moat, animated. Pure render from [playheadBeat].
class LessonHighway extends StatelessWidget {
  const LessonHighway({
    super.key,
    required this.lesson,
    required this.playheadBeat,
    this.height = 168,
    this.strikeX = 68,
    this.beatsVisibleAhead = 4,
  });

  final Lesson lesson;

  /// Current playhead in beats (negative during count-in).
  final double playheadBeat;

  final double height;

  /// Distance of the strike line from the left edge.
  final double strikeX;

  /// How many beats of lane are visible to the right of the strike line
  /// (sets the scroll speed).
  final double beatsVisibleAhead;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final pxPerBeat = (width - strikeX) / beatsVisibleAhead;
          final visible = LessonTiming.visibleEvents(
            lesson.events,
            playheadBeat,
            aheadBeats: beatsVisibleAhead + 1,
            behindBeats: 1.5,
          );
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xFF0E0E12),
              ),
              child: Stack(
                children: [
                  // Painted lane: perspective depth gradient + flowing beat grid
                  // + a glowing strike line. One cheap CustomPaint on its own
                  // layer, behind the cards (chunk 016b P5).
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: HighwayBackgroundPainter(
                          playheadBeat: playheadBeat,
                          pxPerBeat: pxPerBeat,
                          strikeX: strikeX,
                          beatsVisibleAhead: beatsVisibleAhead,
                          beatsPerBar: lesson.beatsPerBar,
                        ),
                      ),
                    ),
                  ),
                  for (final e in visible)
                    _EventCard(
                      event: e,
                      left: LessonTiming.xForEvent(
                            e.beat, playheadBeat, pxPerBeat, strikeX) -
                          _EventCard.width / 2,
                      proximity: _proximity(e.beat, playheadBeat),
                      depth: _depth(e.beat, playheadBeat, beatsVisibleAhead),
                      height: height,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 0 far from the strike line → 1 right on it (within half a beat).
  static double _proximity(double eventBeat, double playheadBeat) =>
      (1 - (eventBeat - playheadBeat).abs() / 0.5).clamp(0.0, 1.0);

  /// Perspective depth: 1.0 at/near the strike line, shrinking to ~0.5 at the
  /// far (future) edge so the lane reads with read-ahead depth.
  static double _depth(
      double eventBeat, double playheadBeat, double aheadBeats) {
    final ahead = (eventBeat - playheadBeat).clamp(0.0, aheadBeats);
    return 1.0 - (ahead / aheadBeats) * 0.5;
  }
}

/// The lane behind the cards: a flowing beat grid (downbeats accented) that
/// fades with distance for depth, plus a glowing strike line drawn as a radial
/// halo (no blur pass — cheap). One CustomPaint on its own RepaintBoundary
/// (chunk 016b P5). Repaints only when the playhead/geometry changes.
class HighwayBackgroundPainter extends CustomPainter {
  HighwayBackgroundPainter({
    required this.playheadBeat,
    required this.pxPerBeat,
    required this.strikeX,
    required this.beatsVisibleAhead,
    required this.beatsPerBar,
  });

  final double playheadBeat;
  final double pxPerBeat;
  final double strikeX;
  final double beatsVisibleAhead;
  final int beatsPerBar;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final line = Paint()..strokeWidth = 1;

    // Flowing beat grid — one vertical line per beat, fading with distance.
    final firstBeat = playheadBeat.floorToDouble() - 1;
    final lastBeat = playheadBeat + beatsVisibleAhead + 1;
    for (var b = firstBeat; b <= lastBeat; b += 1) {
      final x = strikeX + (b - playheadBeat) * pxPerBeat;
      if (x < -2 || x > size.width + 2) continue;
      final near =
          1 - ((b - playheadBeat).abs() / (beatsVisibleAhead + 1)).clamp(0.0, 1.0);
      final isDownbeat = (b % beatsPerBar).abs() < 1e-6;
      line
        ..strokeWidth = isDownbeat ? 2 : 1
        ..color = (isDownbeat ? AppColors.primary : Colors.white).withValues(
            alpha: (isDownbeat ? 0.20 : 0.08) * (0.3 + 0.7 * near));
      canvas.drawLine(Offset(x, 0), Offset(x, h), line);
    }

    // Glowing strike line: radial halo + bright core.
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
  bool shouldRepaint(HighwayBackgroundPainter old) =>
      old.playheadBeat != playheadBeat ||
      old.pxPerBeat != pxPerBeat ||
      old.strikeX != strikeX ||
      old.beatsVisibleAhead != beatsVisibleAhead ||
      old.beatsPerBar != beatsPerBar;
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.left,
    required this.proximity,
    required this.depth,
    required this.height,
  });

  static const double width = 64;

  final LessonEvent event;
  final double left;
  final double proximity;

  /// Perspective depth (1 near the strike line → ~0.5 far); scales + dims.
  final double depth;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = event.isDown ? AppColors.primary : AppColors.confidenceHigh;
    final scale = depth * (1.0 + 0.28 * proximity);
    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      child: SizedBox(
        width: width,
        child: Center(
          child: Opacity(
            opacity: (0.55 + 0.45 * depth).clamp(0.0, 1.0),
            child: Transform.scale(
            scale: scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (event.chord.isNotEmpty) ...[
                  Text(
                    event.chord,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: Color.lerp(
                          Colors.white.withValues(alpha: 0.75), color, proximity),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.15 + 0.25 * proximity),
                    boxShadow: proximity > 0.6
                        ? [
                            BoxShadow(
                              color: color.withValues(
                                  alpha: 0.5 * proximity),
                              blurRadius: 16 * proximity,
                            )
                          ]
                        : null,
                  ),
                  child: Icon(
                    event.isDown
                        ? Icons.arrow_downward
                        : Icons.arrow_upward,
                    color: color,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }
}

/// A small helper widget: the count-in number flashed before the lesson starts.
class CountInOverlay extends StatelessWidget {
  const CountInOverlay({super.key, required this.number});
  final int number;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          '$number',
          style: TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w900,
            fontSize: 72,
            color: AppColors.primary
                .withValues(alpha: 0.5 + 0.5 * (number / math.max(1, number))),
          ),
        ),
      );
}
