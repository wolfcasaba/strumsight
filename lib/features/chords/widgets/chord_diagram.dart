import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../chord_shape.dart';

/// A compact open-position chord diagram: 6 strings × 4 frets, with ○/× markers
/// above the nut and dots on the fretted positions. Draws nothing (a shrink) for
/// a chord we have no shape for. RAG chunk 014.
class ChordDiagram extends StatelessWidget {
  const ChordDiagram({
    super.key,
    required this.label,
    this.size = 96,
    this.showLabel = true,
  });

  final String label;
  final double size;

  /// Show the chord name above the grid. Off where the name is already shown
  /// prominently elsewhere (e.g. the Live screen's huge chord).
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final shape = ChordShapes.forLabel(label);
    if (shape == null) return const SizedBox.shrink();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final grid = CustomPaint(
      size: Size(size, size * 1.05),
      painter: _ChordPainter(shape, onSurface),
    );
    if (!showLabel) return grid;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.1)),
        const SizedBox(height: 2),
        grid,
      ],
    );
  }
}

class _ChordPainter extends CustomPainter {
  _ChordPainter(this.shape, this.ink);

  final ChordShape shape;
  final Color ink;

  static const _frets = 4;

  @override
  void paint(Canvas canvas, Size size) {
    const strings = 6;
    final topPad = size.height * 0.16; // room for ○/× markers
    final gridW = size.width * 0.86;
    final left = (size.width - gridW) / 2;
    final gridH = size.height - topPad - 6;
    final colGap = gridW / (strings - 1);
    final rowGap = gridH / _frets;

    final line = Paint()
      ..color = ink.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final nut = Paint()
      ..color = ink.withValues(alpha: 0.9)
      ..strokeWidth = 3;
    final dot = Paint()..color = AppColors.primary;

    // Strings (vertical) and frets (horizontal).
    for (var s = 0; s < strings; s++) {
      final x = left + s * colGap;
      canvas.drawLine(Offset(x, topPad), Offset(x, topPad + gridH), line);
    }
    for (var f = 0; f <= _frets; f++) {
      final y = topPad + f * rowGap;
      canvas.drawLine(
          Offset(left, y), Offset(left + gridW, y), f == 0 ? nut : line);
    }

    // Markers + dots per string (low-E on the left → high-E on the right).
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var s = 0; s < strings; s++) {
      final x = left + s * colGap;
      final fret = shape.frets[s];
      if (fret <= 0) {
        // ○ (open) or × (muted) above the nut.
        tp
          ..text = TextSpan(
              text: fret == 0 ? '○' : '×',
              style: TextStyle(color: ink.withValues(alpha: 0.8), fontSize: 12))
          ..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, 0));
      } else {
        final y = topPad + (fret - 0.5) * rowGap;
        canvas.drawCircle(Offset(x, y), colGap * 0.28, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChordPainter old) =>
      old.shape.label != shape.label || old.ink != ink;
}
