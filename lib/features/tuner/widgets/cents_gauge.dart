import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';

/// A horizontal −50..+50 cents gauge with a moving marker. Turns green when
/// the note is in tune.
class CentsGauge extends StatelessWidget {
  const CentsGauge({
    super.key,
    required this.cents,
    required this.inTune,
    this.width = 300,
    this.height = 80,
  });

  final double cents;
  final bool inTune;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _GaugePainter(
          cents: cents.clamp(-50.0, 50.0).toDouble(),
          marker: inTune ? AppColors.confidenceHigh : AppColors.primary,
          track: palette.track,
          tick: palette.muted,
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.cents,
    required this.marker,
    required this.track,
    required this.tick,
  });

  final double cents;
  final Color marker;
  final Color track;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 16.0;
    final w = size.width;
    final h = size.height;
    final baseY = h * 0.62;
    final usable = w - pad * 2;

    double xForCents(double c) => pad + (c + 50) / 100 * usable;

    // Baseline track.
    final trackPaint = Paint()
      ..color = track
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(pad, baseY), Offset(w - pad, baseY), trackPaint);

    // Ticks at -50,-25,0,25,50 (centre tick tallest).
    final tickPaint = Paint()
      ..color = tick
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final c in const [-50.0, -25.0, 0.0, 25.0, 50.0]) {
      final x = xForCents(c);
      final len = c == 0 ? 16.0 : 9.0;
      canvas.drawLine(Offset(x, baseY - len), Offset(x, baseY + len), tickPaint);
    }

    // Marker: a filled triangle above the baseline at the current cents.
    final mx = xForCents(cents);
    final markerPaint = Paint()..color = marker;
    final path = Path()
      ..moveTo(mx, baseY - 2)
      ..lineTo(mx - 9, baseY - 22)
      ..lineTo(mx + 9, baseY - 22)
      ..close();
    canvas.drawPath(path, markerPaint);
    canvas.drawCircle(Offset(mx, baseY), 4, markerPaint);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.cents != cents || old.marker != marker || old.track != track;
}
