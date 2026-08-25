import 'package:flutter/material.dart';

/// Strum direction, decoupled from any feature-layer strum model so the
/// design system stays framework-generic (no `core/music` dependency).
enum SsStrumDirection { down, up }

/// A down/up strum-direction glyph whose meaning is carried by BOTH colour
/// (the caller-supplied confidence [color]) AND shape — filled arrowhead
/// (tier 2, high), open chevron (tier 1, mid), open chevron + a hollow
/// "unsure" dot (tier 0, low) — so it stays legible without colour
/// (ADR 0278 §2, ADR 0280 §4).
final class SsStrumGlyph extends StatelessWidget {
  const SsStrumGlyph({
    super.key,
    required this.direction,
    required this.confidenceTier,
    required this.color,
    this.size = 24,
    this.semanticLabel,
  });

  final SsStrumDirection direction;

  /// 0 = low, 1 = mid, 2 = high — drives the glyph SHAPE, not just its tint.
  final int confidenceTier;

  final Color color;

  /// Glyph width in logical pixels; height is 1.2× this.
  final double size;

  /// When null the glyph is decorative-only (the caller announces direction
  /// via its own text, e.g. a live-region announcer) and is excluded from
  /// the semantics tree.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tier = confidenceTier.clamp(0, 2);
    final glyph = CustomPaint(
      size: Size(size, size * 1.2),
      painter: _SsStrumGlyphPainter(
        direction: direction,
        tier: tier,
        color: color,
        stroke: size * 0.11,
      ),
    );
    final label = semanticLabel;
    if (label == null) {
      return ExcludeSemantics(child: glyph);
    }
    return Semantics(label: label, excludeSemantics: true, child: glyph);
  }
}

class _SsStrumGlyphPainter extends CustomPainter {
  _SsStrumGlyphPainter({
    required this.direction,
    required this.tier,
    required this.color,
    required this.stroke,
  });

  final SsStrumDirection direction;

  /// 0 = low, 1 = mid, 2 = high.
  final int tier;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final hw = w * 0.31; // half-width of the arrowhead
    final hh = h * 0.33; // height of the arrowhead

    final line = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final down = direction == SsStrumDirection.down;
    final tipY = down ? h * 0.97 : h * 0.03;
    final farY = down ? h * 0.03 : h * 0.97;
    final baseY = down ? tipY - hh : tipY + hh;

    canvas.drawLine(Offset(cx, farY), Offset(cx, baseY), line);

    final tip = Offset(cx, tipY);
    final left = Offset(cx - hw, baseY);
    final right = Offset(cx + hw, baseY);

    if (tier == 2) {
      final head = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
      canvas.drawPath(
        head,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        head,
        Paint()
          ..color = color
          ..strokeWidth = stroke * 0.5
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
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
      if (tier == 0) {
        final dotY = down ? tip.dy - hh * 0.28 : tip.dy + hh * 0.28;
        canvas.drawCircle(
          Offset(cx, dotY),
          stroke * 0.9,
          Paint()
            ..color = color
            ..strokeWidth = stroke * 0.6
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SsStrumGlyphPainter old) =>
      old.direction != direction ||
      old.color != color ||
      old.tier != tier ||
      old.stroke != stroke;
}
