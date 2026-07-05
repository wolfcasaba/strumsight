import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../model/strum.dart';

/// A down/up strum arrow whose meaning is carried by BOTH colour (the
/// confidence ramp) AND shape (filled head at high confidence, open chevron
/// below) — so it stays legible for colour-blind users.
class StrumArrow extends StatelessWidget {
  const StrumArrow({
    super.key,
    required this.direction,
    required this.confidence,
    this.size = 24,
    this.strokeWidth,
    this.glow = false,
    this.semanticLabel,
  });

  final StrumDirection direction;

  /// 0..1 — drives colour and filled/outline shape.
  final double confidence;

  /// Arrow width in logical pixels; height is 1.2× this.
  final double size;

  final double? strokeWidth;

  /// Soft glow behind the arrow (used for the big hero arrow).
  final bool glow;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.confidence(confidence);
    final filled = confidence >= 0.75;
    final stroke = strokeWidth ?? (size * 0.11);

    Widget paint = CustomPaint(
      size: Size(size, size * 1.2),
      painter: _StrumArrowPainter(
        direction: direction,
        color: color,
        filled: filled,
        stroke: stroke,
      ),
    );

    if (glow) {
      paint = DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: size * 0.5),
          ],
        ),
        child: paint,
      );
    }

    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: paint,
    );
  }
}

class _StrumArrowPainter extends CustomPainter {
  _StrumArrowPainter({
    required this.direction,
    required this.color,
    required this.filled,
    required this.stroke,
  });

  final StrumDirection direction;
  final Color color;
  final bool filled;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final hw = w * 0.32; // half-width of the arrowhead
    final hh = h * 0.30; // height of the arrowhead

    final line = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final down = direction == StrumDirection.down;
    final tipY = down ? h * 0.97 : h * 0.03;
    final farY = down ? h * 0.03 : h * 0.97; // opposite end of the shaft
    final baseY = down ? tipY - hh : tipY + hh; // arrowhead base line

    // Shaft: from the far end to the base of the arrowhead.
    canvas.drawLine(Offset(cx, farY), Offset(cx, baseY), line);

    final tip = Offset(cx, tipY);
    final left = Offset(cx - hw, baseY);
    final right = Offset(cx + hw, baseY);

    if (filled) {
      final head = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
      canvas.drawPath(head, Paint()..color = color..style = PaintingStyle.fill);
    } else {
      final chevron = Paint()
        ..color = color
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(
        Path()
          ..moveTo(left.dx, left.dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(right.dx, right.dy),
        chevron,
      );
    }
  }

  @override
  bool shouldRepaint(_StrumArrowPainter old) =>
      old.direction != direction ||
      old.color != color ||
      old.filled != filled ||
      old.stroke != stroke;
}
