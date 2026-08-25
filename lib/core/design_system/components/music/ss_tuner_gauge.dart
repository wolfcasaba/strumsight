import 'package:flutter/material.dart';

/// The Stage hero slot's cents-offset pointer (Ch13 §9.9): a horizontal
/// −50..+50 cent gauge with a moving marker. Purely presentational — every
/// colour arrives from the caller and the accessible narration is a
/// caller-supplied [semanticLabel], the same convention
/// `SsSignalQualityIndicator`/`SsTempoDisplay` already use (l10n stays in the
/// feature layer).
final class SsTunerGauge extends StatelessWidget {
  const SsTunerGauge({
    super.key,
    required this.cents,
    required this.hasSignal,
    required this.markerColor,
    required this.trackColor,
    required this.tickColor,
    required this.semanticLabel,
    this.width = 300,
    this.height = 80,
  });

  /// −50..+50, negative = flat. Ignored (the marker centers at zero) while
  /// [hasSignal] is false.
  final double cents;

  final bool hasSignal;
  final Color markerColor;
  final Color trackColor;
  final Color tickColor;
  final String semanticLabel;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _SsTunerGaugePainter(
            cents: hasSignal ? cents.clamp(-50.0, 50.0).toDouble() : 0,
            showMarker: hasSignal,
            marker: markerColor,
            track: trackColor,
            tick: tickColor,
          ),
        ),
      ),
    );
  }
}

class _SsTunerGaugePainter extends CustomPainter {
  _SsTunerGaugePainter({
    required this.cents,
    required this.showMarker,
    required this.marker,
    required this.track,
    required this.tick,
  });

  final double cents;
  final bool showMarker;
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

    final trackPaint = Paint()
      ..color = track
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(pad, baseY), Offset(w - pad, baseY), trackPaint);

    final tickPaint = Paint()
      ..color = tick
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final c in const [-50.0, -25.0, 0.0, 25.0, 50.0]) {
      final x = xForCents(c);
      final len = c == 0 ? 16.0 : 9.0;
      canvas.drawLine(
        Offset(x, baseY - len),
        Offset(x, baseY + len),
        tickPaint,
      );
    }

    if (!showMarker) return;

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
  bool shouldRepaint(_SsTunerGaugePainter old) =>
      old.cents != cents ||
      old.showMarker != showMarker ||
      old.marker != marker ||
      old.track != track ||
      old.tick != tick;
}
