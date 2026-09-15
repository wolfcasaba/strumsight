import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../foundations/ss_motion.dart';
import '../../motion/ss_motion_scope.dart';

/// A ring around [child] that CLOSES when [locked] turns true and opens
/// again when it turns false — the tuner's "string locked in" moment made
/// visible (Ch18 spec §4: GuitarTuna-class lock feel). The arc sweeps from
/// 12 o'clock over [SsMotion.standard]; under reduced motion it snaps.
///
/// Colour and shape together: the closed ring is a shape change, not only a
/// tint, so the lock still reads without colour. Theme-agnostic — the caller
/// supplies [color] (and an optional [trackColor] for the open ring).
final class SsLockRing extends StatelessWidget {
  const SsLockRing({
    super.key,
    required this.locked,
    required this.color,
    required this.child,
    this.trackColor,
    this.strokeWidth = 4,
    this.padding = 12,
    this.duration = SsMotion.standard,
  });

  final bool locked;
  final Color color;
  final Widget child;

  /// Faint full circle drawn under the arc; null draws no track.
  final Color? trackColor;

  final double strokeWidth;

  /// Gap between the child and the ring.
  final double padding;

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: locked ? 1 : 0),
      duration: SsMotionScope.durationOf(context, duration),
      curve: SsMotion.enter,
      child: Padding(
        padding: EdgeInsets.all(padding + strokeWidth),
        child: child,
      ),
      builder: (context, closed, child) => CustomPaint(
        painter: SsLockRingPainter(
          closed: closed,
          color: color,
          trackColor: trackColor,
          strokeWidth: strokeWidth,
        ),
        child: child,
      ),
    );
  }
}

/// Paints [SsLockRing]: an optional track circle plus an arc of `closed ×
/// 360°` from 12 o'clock, inscribed in the square that fits the size.
final class SsLockRingPainter extends CustomPainter {
  const SsLockRingPainter({
    required this.closed,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  /// 0 = fully open (no arc), 1 = fully closed ring.
  final double closed;
  final Color color;
  final Color? trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.shortestSide - strokeWidth) / 2;
    if (radius <= 0) return;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: radius,
    );
    final track = trackColor;
    if (track != null) {
      canvas.drawArc(
        rect,
        0,
        2 * math.pi,
        false,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
    }
    if (closed <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * closed.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(SsLockRingPainter old) =>
      old.closed != closed ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
