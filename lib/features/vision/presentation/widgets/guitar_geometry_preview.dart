/// Read-only painter widget that renders the nut, bridge, neck polygon
/// preview and the centerline for the manual guitar calibration screen
/// (SDD Ch6 §13.3, E05-R11).
///
/// **Coordinate contract (§5.2):** Every `NormalizedPoint` drawn here is
/// converted through [PreviewFit.toPreview] (R07) — the widget performs NO
/// `1 - x`, `swap`, or `MediaQuery`-based manual mapping of its own. The
/// single input is the fit's viewport rectangle (already in logical pixels)
/// and the normalised anchor + polygon list.
library;

import 'package:flutter/material.dart';

import '../../../../core/camera/camera_coordinate_space.dart';
import '../../../../core/camera/preview_fit.dart';
import 'guitar_anchor_editor.dart' show anchorPainterColor;

class GuitarGeometryPreview extends StatelessWidget {
  const GuitarGeometryPreview({
    super.key,
    required this.fit,
    required this.nut,
    required this.bridge,
    required this.neckPolygon,
  });

  final PreviewFit fit;
  final NormalizedPoint nut;
  final NormalizedPoint bridge;
  final List<NormalizedPoint> neckPolygon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('guitar-geometry-preview'),
      width: fit.viewport.width,
      height: fit.viewport.height,
      child: CustomPaint(
        painter: _GeometryPainter(
          fit: fit,
          nut: nut,
          bridge: bridge,
          neckPolygon: neckPolygon,
          color: anchorPainterColor(context),
        ),
      ),
    );
  }
}

class _GeometryPainter extends CustomPainter {
  const _GeometryPainter({
    required this.fit,
    required this.nut,
    required this.bridge,
    required this.neckPolygon,
    required this.color,
  });

  final PreviewFit fit;
  final NormalizedPoint nut;
  final NormalizedPoint bridge;
  final List<NormalizedPoint> neckPolygon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final toPreview = fit.toPreview();
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Filled polygon overlay.
    final fillPath = Path();
    for (var i = 0; i < neckPolygon.length; i++) {
      final v = toPreview.apply(neckPolygon[i]);
      final o = Offset(v.x, v.y);
      if (i == 0) {
        fillPath.moveTo(o.dx, o.dy);
      } else {
        fillPath.lineTo(o.dx, o.dy);
      }
    }
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(fillPath, strokePaint);

    // Centerline nut↔bridge.
    final nutPreview = toPreview.apply(nut);
    final bridgePreview = toPreview.apply(bridge);
    final centerlinePaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(nutPreview.x, nutPreview.y),
      Offset(bridgePreview.x, bridgePreview.y),
      centerlinePaint,
    );

    // Anchor markers (the editor also draws them, this is just a subtle
    // hint so the preview is readable on its own when used in a screenshot).
    final anchorPaint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(nutPreview.x, nutPreview.y), 8, anchorPaint);
    canvas.drawCircle(Offset(bridgePreview.x, bridgePreview.y), 8, anchorPaint);
  }

  @override
  bool shouldRepaint(covariant _GeometryPainter oldDelegate) =>
      oldDelegate.fit != fit ||
      oldDelegate.nut != nut ||
      oldDelegate.bridge != bridge ||
      oldDelegate.color != color ||
      !_listEquals(oldDelegate.neckPolygon, neckPolygon);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
