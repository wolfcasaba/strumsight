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
          return ClipRect(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.black.withValues(alpha: 0.18),
              ),
              child: Stack(
                children: [
                  // The strike line (where "now" is).
                  Positioned(
                    left: strikeX,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 3,
                      color: AppColors.primary.withValues(alpha: 0.85),
                    ),
                  ),
                  for (final e in visible)
                    _EventCard(
                      event: e,
                      left: LessonTiming.xForEvent(
                            e.beat, playheadBeat, pxPerBeat, strikeX) -
                          _EventCard.width / 2,
                      proximity: _proximity(e.beat, playheadBeat),
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
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.left,
    required this.proximity,
    required this.height,
  });

  static const double width = 64;

  final LessonEvent event;
  final double left;
  final double proximity;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = event.isDown ? AppColors.primary : AppColors.confidenceHigh;
    final scale = 1.0 + 0.28 * proximity;
    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      child: SizedBox(
        width: width,
        child: Center(
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
