import 'package:flutter/material.dart';

import 'ss_guitar_glyphs.dart';
import 'ss_icons.dart';

/// The unified icon widget: resolves [name] through [SsIcons.resolveByName],
/// applies the [SsIconSize] Stage contract, and enforces the
/// interactive/decorative semantics split (ADR 0411 §4) through two
/// factories rather than a single toggle — a caller cannot build an icon
/// that is only partly interactive.
final class SsIcon extends StatelessWidget {
  /// A decorative icon — excluded from the semantics tree entirely (ADR 0411
  /// §4), so it adds no noise for a screen-reader user.
  const SsIcon.decorative({
    super.key,
    required this.name,
    this.size = SsIconSize.base,
    this.stage = false,
    this.color,
  }) : semanticLabel = null,
       tooltip = null;

  /// An interactive icon. [semanticLabel] and [tooltip] are hívó-oldali
  /// (caller-supplied) and required non-empty (ADR 0411 §4) — the design
  /// system never localizes them itself.
  SsIcon.interactive({
    super.key,
    required this.name,
    required String semanticLabel,
    required String tooltip,
    this.size = SsIconSize.base,
    this.stage = false,
    this.color,
  }) : semanticLabel = _requireNonEmpty(semanticLabel, 'semanticLabel'),
       tooltip = _requireNonEmpty(tooltip, 'tooltip');

  /// The catalog key resolved through [SsIcons.resolveByName] — a
  /// [SsGuitarGlyphName.name], a Material key, or any other string, which
  /// falls back to the visible ADR 0411 §6 mark (A4).
  final String name;

  final double size;

  /// When true, [size] is clamped into the inclusive Stage range before
  /// render (D5) — a below-range request never reaches the paint call.
  final bool stage;

  final Color? color;
  final String? semanticLabel;
  final String? tooltip;

  static String _requireNonEmpty(String value, String field) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(
        value,
        field,
        'must not be empty for an interactive SsIcon',
      );
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final resolution = SsIcons.resolveByName(name);
    final resolvedSize = stage ? SsIconSize.resolveForStage(size) : size;
    final resolvedColor = color ?? Theme.of(context).colorScheme.onSurface;

    final Widget glyph = switch (resolution) {
      SsResolvedMaterialIcon(:final data) => Icon(
        data,
        size: resolvedSize,
        color: resolvedColor,
      ),
      SsResolvedGuitarGlyph(:final name) => CustomPaint(
        size: Size.square(resolvedSize),
        painter: SsGuitarGlyphs.painterFor(
          name,
          color: resolvedColor,
          size: resolvedSize,
        ),
      ),
      SsFallbackIcon() => CustomPaint(
        size: Size.square(resolvedSize),
        painter: _SsIconFallbackPainter(
          color: resolvedColor,
          size: resolvedSize,
        ),
      ),
    };

    final label = semanticLabel;
    if (label != null) {
      return Tooltip(
        message: tooltip!,
        excludeFromSemantics: true,
        child: Semantics(
          label: label,
          image: true,
          excludeSemantics: true,
          child: glyph,
        ),
      );
    }
    return ExcludeSemantics(child: glyph);
  }
}

/// The painted "missing glyph" mark (ADR 0411 §6) — a boxed cross, never a
/// zero-size box, so an unresolved [SsIcon.name] is visibly wrong instead of
/// silently absent. Its stroke still derives from
/// [SsGuitarGlyphs.strokeWidthFor], the one named ratio (ADR 0411 §2).
final class _SsIconFallbackPainter extends CustomPainter {
  _SsIconFallbackPainter({required this.color, required this.size})
    : strokeWidth = SsGuitarGlyphs.strokeWidthFor(size);

  final Color color;
  final double size;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final rect = Rect.fromLTWH(
      0,
      0,
      canvasSize.width,
      canvasSize.height,
    ).deflate(strokeWidth);
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, paint);
    canvas.drawLine(rect.topLeft, rect.bottomRight, paint);
    canvas.drawLine(rect.topRight, rect.bottomLeft, paint);
  }

  @override
  bool shouldRepaint(covariant _SsIconFallbackPainter old) =>
      old.color != color || old.size != size;
}
