import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../settings/providers/left_handed_provider.dart';
import '../chord_shape.dart';

/// A compact open-position chord diagram: 6 strings × 4 frets, with ○/× markers
/// above the nut and dots on the fretted positions. Draws nothing (a shrink) for
/// a chord we have no shape for. Mirrors when left-handed. RAG chunk 014.
class ChordDiagram extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = ChordShapes.forLabel(label);
    if (shape == null) return const SizedBox.shrink();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final mirror = ref.watch(leftHandedProvider);
    final grid = CustomPaint(
      size: Size(size, size * 1.05),
      painter: _ChordPainter(shape, onSurface, mirror),
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
  _ChordPainter(this.shape, this.ink, this.mirror);

  final ChordShape shape;
  final Color ink;

  /// Left-handed: draw high-E on the left (reverse the string order).
  final bool mirror;

  static const _frets = 4;

  /// Horizontal slot for string index [s] (0 = low-E), honouring [mirror].
  double _slot(int s) => mirror ? (5 - s).toDouble() : s.toDouble();

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

    // Markers + dots per string (mirrored for left-handed).
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var s = 0; s < strings; s++) {
      final x = left + _slot(s) * colGap;
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
      old.shape.label != shape.label ||
      old.ink != ink ||
      old.mirror != mirror;
}
