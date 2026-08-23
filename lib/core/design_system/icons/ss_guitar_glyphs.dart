import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ss_icons.dart';

/// The single named stroke-to-size ratio every glyph in [SsGuitarGlyphPainter]
/// derives its line thickness from (Ch13 §9.8 "egységes stroke", ADR 0411
/// §2) — a painter must never hardcode its own width.
const double kSsGuitarGlyphStrokeRatio = 0.08;

/// Factory for the fourteen Ch13 §9.8 guitar-technique glyphs.
abstract final class SsGuitarGlyphs {
  /// The only place a stroke width is computed from a requested size — every
  /// glyph in [SsGuitarGlyphPainter] reads this via its constructor, so no
  /// individual glyph can substitute a hand-picked value (A9).
  static double strokeWidthFor(double size) => size * kSsGuitarGlyphStrokeRatio;

  static SsGuitarGlyphPainter painterFor(
    SsGuitarGlyphName name, {
    required Color color,
    required double size,
  }) => SsGuitarGlyphPainter(name: name, color: color, size: size);
}

/// Paints exactly one of the fourteen guitar-technique glyphs, chosen by
/// [name]. All fourteen share this single class so there is exactly one
/// [strokeWidth] computation for the whole set (A9), exposed here so a test
/// can confirm it always equals [SsGuitarGlyphs.strokeWidthFor].
final class SsGuitarGlyphPainter extends CustomPainter {
  SsGuitarGlyphPainter({
    required this.name,
    required this.color,
    required this.size,
  }) : strokeWidth = SsGuitarGlyphs.strokeWidthFor(size);

  final SsGuitarGlyphName name;
  final Color color;
  final double size;
  final double strokeWidth;

  Paint get _line => Paint()
    ..color = color
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  Paint get _fill => Paint()
    ..color = color
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    switch (name) {
      case SsGuitarGlyphName.downstrum:
        _paintStrum(canvas, canvasSize, down: true);
      case SsGuitarGlyphName.upstrum:
        _paintStrum(canvas, canvasSize, down: false);
      case SsGuitarGlyphName.alternatePicking:
        _paintAlternatePicking(canvas, canvasSize);
      case SsGuitarGlyphName.palmMute:
        _paintPalmMute(canvas, canvasSize);
      case SsGuitarGlyphName.bend:
        _paintBend(canvas, canvasSize);
      case SsGuitarGlyphName.vibrato:
        _paintVibrato(canvas, canvasSize);
      case SsGuitarGlyphName.hammerOn:
        _paintHammerOn(canvas, canvasSize);
      case SsGuitarGlyphName.pullOff:
        _paintPullOff(canvas, canvasSize);
      case SsGuitarGlyphName.slide:
        _paintSlide(canvas, canvasSize);
      case SsGuitarGlyphName.capo:
        _paintCapo(canvas, canvasSize);
      case SsGuitarGlyphName.metronome:
        _paintMetronome(canvas, canvasSize);
      case SsGuitarGlyphName.tuningPeg:
        _paintTuningPeg(canvas, canvasSize);
      case SsGuitarGlyphName.fretboard:
        _paintFretboard(canvas, canvasSize);
      case SsGuitarGlyphName.loopAB:
        _paintLoopAB(canvas, canvasSize);
    }
  }

  // The down/up strum shaft-and-arrowhead — the product's central signal
  // (ADR 0411 §3). Painted, never a `Text('↓')`/`Text('↑')` character.
  void _paintStrum(Canvas canvas, Size s, {required bool down}) {
    final cx = s.width / 2;
    final topY = s.height * 0.12;
    final bottomY = s.height * 0.88;
    final tipY = down ? bottomY : topY;
    final farY = down ? topY : bottomY;
    final headHalf = s.width * 0.22;
    final headLen = s.height * 0.22;
    final baseY = down ? tipY - headLen : tipY + headLen;

    canvas.drawLine(Offset(cx, farY), Offset(cx, baseY), _line);
    canvas.drawPath(
      Path()
        ..moveTo(cx, tipY)
        ..lineTo(cx - headHalf, baseY)
        ..lineTo(cx + headHalf, baseY)
        ..close(),
      _fill,
    );
  }

  void _paintAlternatePicking(Canvas canvas, Size s) {
    canvas.drawPath(
      Path()
        ..moveTo(s.width * 0.1, s.height * 0.3)
        ..lineTo(s.width * 0.35, s.height * 0.75)
        ..lineTo(s.width * 0.6, s.height * 0.3)
        ..lineTo(s.width * 0.9, s.height * 0.75),
      _line,
    );
  }

  void _paintPalmMute(Canvas canvas, Size s) {
    canvas.drawLine(
      Offset(s.width * 0.15, s.height * 0.5),
      Offset(s.width * 0.9, s.height * 0.5),
      _line,
    );
    final palm = Rect.fromCenter(
      center: Offset(s.width * 0.24, s.height * 0.5),
      width: s.width * 0.3,
      height: s.height * 0.42,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(palm, Radius.circular(s.width * 0.08)),
      _fill,
    );
  }

  void _paintBend(Canvas canvas, Size s) {
    final tip = Offset(s.width * 0.78, s.height * 0.2);
    canvas.drawPath(
      Path()
        ..moveTo(s.width * 0.2, s.height * 0.85)
        ..quadraticBezierTo(s.width * 0.85, s.height * 0.85, tip.dx, tip.dy),
      _line,
    );
    _arrowHead(canvas, tip: tip, angle: -math.pi / 2.4);
  }

  void _paintVibrato(Canvas canvas, Size s) {
    final path = Path()..moveTo(s.width * 0.1, s.height * 0.5);
    const segments = 4;
    final dx = s.width * 0.8 / segments;
    var x = s.width * 0.1;
    for (var i = 0; i < segments; i++) {
      final midX = x + dx / 2;
      final endX = x + dx;
      final dir = i.isEven ? -1 : 1;
      path.quadraticBezierTo(
        midX,
        s.height * 0.5 + dir * s.height * 0.18,
        endX,
        s.height * 0.5,
      );
      x = endX;
    }
    canvas.drawPath(path, _line);
  }

  void _paintHammerOn(Canvas canvas, Size s) {
    final start = Offset(s.width * 0.25, s.height * 0.75);
    final end = Offset(s.width * 0.75, s.height * 0.75);
    canvas.drawCircle(start, strokeWidth * 0.9, _fill);
    canvas.drawCircle(
      end,
      strokeWidth * 0.9,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 0.6,
    );
    final arcTip = Offset(end.dx, end.dy - strokeWidth * 1.2);
    canvas.drawPath(
      Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(
          s.width * 0.5,
          s.height * 0.15,
          arcTip.dx,
          arcTip.dy,
        ),
      _line,
    );
    _arrowHead(canvas, tip: arcTip, angle: math.pi / 2);
  }

  void _paintPullOff(Canvas canvas, Size s) {
    final start = Offset(s.width * 0.25, s.height * 0.75);
    final end = Offset(s.width * 0.75, s.height * 0.75);
    canvas.drawCircle(
      start,
      strokeWidth * 0.9,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 0.6,
    );
    canvas.drawCircle(end, strokeWidth * 0.9, _fill);
    final arcTip = Offset(start.dx, start.dy - strokeWidth * 1.2);
    canvas.drawPath(
      Path()
        ..moveTo(end.dx, end.dy)
        ..quadraticBezierTo(
          s.width * 0.5,
          s.height * 0.15,
          arcTip.dx,
          arcTip.dy,
        ),
      _line,
    );
    _arrowHead(canvas, tip: arcTip, angle: math.pi);
  }

  void _paintSlide(Canvas canvas, Size s) {
    final start = Offset(s.width * 0.2, s.height * 0.8);
    final end = Offset(s.width * 0.8, s.height * 0.2);
    canvas.drawLine(start, end, _line);
    _arrowHead(
      canvas,
      tip: end,
      angle: math.atan2(end.dy - start.dy, end.dx - start.dx),
    );
  }

  void _paintCapo(Canvas canvas, Size s) {
    for (final fx in [0.3, 0.5, 0.7]) {
      canvas.drawLine(
        Offset(s.width * fx, s.height * 0.15),
        Offset(s.width * fx, s.height * 0.85),
        _line,
      );
    }
    final bar = Rect.fromLTWH(
      s.width * 0.15,
      s.height * 0.38,
      s.width * 0.7,
      s.height * 0.24,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bar, Radius.circular(s.width * 0.06)),
      _line,
    );
  }

  void _paintMetronome(Canvas canvas, Size s) {
    canvas.drawPath(
      Path()
        ..moveTo(s.width * 0.5, s.height * 0.1)
        ..lineTo(s.width * 0.78, s.height * 0.9)
        ..lineTo(s.width * 0.22, s.height * 0.9)
        ..close(),
      _line,
    );
    canvas.drawLine(
      Offset(s.width * 0.5, s.height * 0.85),
      Offset(s.width * 0.62, s.height * 0.25),
      _line,
    );
    canvas.drawCircle(
      Offset(s.width * 0.62, s.height * 0.25),
      strokeWidth * 0.7,
      _fill,
    );
  }

  void _paintTuningPeg(Canvas canvas, Size s) {
    canvas.drawLine(
      Offset(s.width * 0.18, s.height * 0.5),
      Offset(s.width * 0.54, s.height * 0.5),
      _line,
    );
    canvas.drawCircle(
      Offset(s.width * 0.72, s.height * 0.5),
      s.width * 0.18,
      _line,
    );
    canvas.drawLine(
      Offset(s.width * 0.72, s.height * 0.32),
      Offset(s.width * 0.72, s.height * 0.12),
      _line,
    );
  }

  void _paintFretboard(Canvas canvas, Size s) {
    for (final fx in [0.2, 0.4, 0.6, 0.8]) {
      canvas.drawLine(
        Offset(s.width * fx, s.height * 0.1),
        Offset(s.width * fx, s.height * 0.9),
        _line,
      );
    }
    for (final fy in [0.3, 0.5, 0.7]) {
      canvas.drawLine(
        Offset(s.width * 0.15, s.height * fy),
        Offset(s.width * 0.85, s.height * fy),
        _line,
      );
    }
  }

  void _paintLoopAB(Canvas canvas, Size s) {
    final center = Offset(s.width * 0.5, s.height * 0.5);
    final radius = s.width * 0.32;
    const startAngle = -math.pi * 0.15;
    const sweepAngle = math.pi * 1.7;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      _line,
    );
    final endAngle = startAngle + sweepAngle;
    final tip =
        center + Offset(math.cos(endAngle), math.sin(endAngle)) * radius;
    _arrowHead(canvas, tip: tip, angle: endAngle + math.pi / 2);
  }

  void _arrowHead(Canvas canvas, {required Offset tip, required double angle}) {
    final length = strokeWidth * 1.5;
    final left =
        tip + Offset(math.cos(angle + 2.6), math.sin(angle + 2.6)) * length;
    final right =
        tip + Offset(math.cos(angle - 2.6), math.sin(angle - 2.6)) * length;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close(),
      _fill,
    );
  }

  @override
  bool shouldRepaint(covariant SsGuitarGlyphPainter old) =>
      old.name != name || old.color != color || old.size != size;
}
