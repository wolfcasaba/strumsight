import 'package:flutter/material.dart';

/// The Learning Mode fingering diagram (Ch13 §9.9, ADR 0282): a 6-string ×
/// 4-fret grid with ○/× markers above the nut and dots on the fretted
/// positions. Purely presentational — the fingering, handedness and every
/// colour arrive from the caller; the design system cannot read a feature
/// provider (E13-R02 boundary), so left-handed mirroring is a plain `bool`.
///
/// [readingOrder] is the SAME string→slot mapping the painter uses to place
/// each string, exposed so a caller can build a text alternative that can
/// never independently drift from the drawing (ADR 0282 §1/§2): mirror one,
/// and the other is mirrored by construction, not by a second copy of the
/// logic.
final class SsChordDiagram extends StatelessWidget {
  const SsChordDiagram({
    super.key,
    required this.frets,
    required this.ink,
    required this.dotColor,
    this.baseFret = 0,
    this.baseFretLabel,
    this.mirrored = false,
    this.label,
    this.size = 96,
  });

  /// 6 entries, low-E (6th) → high-E (1st). `-1` = muted (×), `0` = open (○),
  /// `>0` = fret pressed.
  final List<int> frets;

  final Color ink;
  final Color dotColor;

  /// First fret of the 4-fret window (0 = at the nut). >0 for a movable/barre
  /// shape sliding the window down.
  final int baseFret;

  /// The [baseFret] window badge text (e.g. "4fr"), already composed by the
  /// caller — the design system does not own this string (no l10n layer
  /// here; ADR 0424 §2.3 keeps user-facing text out of this tree). Ignored
  /// when [baseFret] is 0.
  final String? baseFretLabel;

  /// Left-handed: draw high-E on the left (reverse the string order).
  final bool mirrored;

  /// Shown above the grid when non-null (the design system does not own the
  /// label's typography choice beyond this default — callers needing a
  /// different treatment can pass null and render their own).
  final String? label;

  final double size;

  /// Horizontal slot for the string at index [stringIndex] (0 = low-E/6th),
  /// honouring [mirrored]. The painter positions every string at this slot.
  static int slotFor(int stringIndex, {required bool mirrored}) =>
      mirrored ? 5 - stringIndex : stringIndex;

  /// [frets] reordered left → right exactly as drawn, honouring [mirrored].
  /// Feeds a caller's spoken/visible fingering description from the SAME
  /// mapping the grid painter uses — a mirrored drawing always mirrors its
  /// text too, by construction (ADR 0282 §1/§2).
  static List<int> readingOrder(List<int> frets, {required bool mirrored}) {
    final bySlot = List<int>.filled(frets.length, 0);
    for (var s = 0; s < frets.length; s++) {
      bySlot[slotFor(s, mirrored: mirrored)] = frets[s];
    }
    return bySlot;
  }

  @override
  Widget build(BuildContext context) {
    Widget grid = CustomPaint(
      size: Size(size, size * 1.05),
      painter: _SsChordDiagramPainter(frets, ink, dotColor, mirrored, baseFret),
    );
    // A movable/barre shape shows its window's starting fret (e.g. "4fr").
    if (baseFret > 0 && baseFretLabel != null) {
      grid = Stack(
        clipBehavior: Clip.none,
        children: [
          grid,
          Positioned(
            top: size * 0.18,
            left: mirrored ? null : -2,
            right: mirrored ? -2 : null,
            child: Text(
              baseFretLabel!,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: ink.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      );
    }
    if (label == null) return grid;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label!,
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w700,
            fontSize: 13,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        grid,
      ],
    );
  }
}

class _SsChordDiagramPainter extends CustomPainter {
  _SsChordDiagramPainter(
    this.frets,
    this.ink,
    this.dotColor,
    this.mirrored,
    this.baseFret,
  );

  final List<int> frets;
  final Color ink;
  final Color dotColor;
  final bool mirrored;
  final int baseFret;

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
    final dot = Paint()..color = dotColor;

    // Strings (vertical) and frets (horizontal).
    for (var s = 0; s < strings; s++) {
      final x = left + s * colGap;
      canvas.drawLine(Offset(x, topPad), Offset(x, topPad + gridH), line);
    }
    for (var f = 0; f <= _frets; f++) {
      final y = topPad + f * rowGap;
      // The thick nut only exists at the top of an OPEN-position window; a
      // shifted (base-fret) window has an ordinary fret line there.
      canvas.drawLine(
        Offset(left, y),
        Offset(left + gridW, y),
        (f == 0 && baseFret == 0) ? nut : line,
      );
    }

    // Markers + dots per string (mirrored for left-handed).
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var s = 0; s < strings; s++) {
      final x = left + SsChordDiagram.slotFor(s, mirrored: mirrored) * colGap;
      final fret = frets[s];
      if (fret <= 0) {
        // ○ (open) or × (muted) above the nut.
        tp
          ..text = TextSpan(
            text: fret == 0 ? '○' : '×',
            style: TextStyle(color: ink.withValues(alpha: 0.8), fontSize: 12),
          )
          ..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, 0));
      } else {
        // Position within the (possibly shifted) window.
        final y = topPad + (fret - baseFret - 0.5) * rowGap;
        canvas.drawCircle(Offset(x, y), colGap * 0.28, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SsChordDiagramPainter old) =>
      old.frets != frets ||
      old.ink != ink ||
      old.dotColor != dotColor ||
      old.mirrored != mirrored ||
      old.baseFret != baseFret;
}
