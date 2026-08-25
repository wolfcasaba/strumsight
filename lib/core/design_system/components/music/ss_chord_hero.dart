import 'package:flutter/material.dart';

import 'ss_strum_glyph.dart';

/// The Stage hero slot's glanceable, read-from-across-the-room current-chord
/// readout (Ch13 §9.9). The label scales down to fit via [FittedBox] (never
/// a fixed height, so it never overflows a short viewport — §5.3), and the
/// latest strum direction, when known, renders beside it as an [SsStrumGlyph]
/// so direction and confidence read without colour alone.
///
/// Deliberately palette-driven ([textColor]/[glyphColor]) rather than reading
/// a design-system typography theme extension — see the round handoff for
/// why (`AppTheme`, the app's actual runtime theme, does not register one).
final class SsChordHero extends StatelessWidget {
  const SsChordHero({
    super.key,
    required this.chordLabel,
    required this.textColor,
    this.direction,
    this.glyphColor,
    this.confidenceTier = 0,
    this.directionSemanticLabel,
    this.placeholder = '-',
    this.semanticLabel,
  });

  /// The currently sounding chord's label, already transposed for capo.
  /// Null renders [placeholder] (no chord detected yet).
  final String? chordLabel;

  final Color textColor;

  /// The latest strum's direction, or null to hide the glyph entirely.
  final SsStrumDirection? direction;

  /// Colour for the direction glyph — required when [direction] is set.
  final Color? glyphColor;

  /// 0 = low, 1 = mid, 2 = high — drives the glyph shape.
  final int confidenceTier;

  final String? directionSemanticLabel;

  final String placeholder;

  /// Semantics label for the chord text itself; defaults to [chordLabel] or
  /// [placeholder]. Passing an explicit empty label lets a caller silence a
  /// placeholder that is already announced elsewhere.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final label = chordLabel ?? placeholder;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Semantics(
            label: semanticLabel ?? label,
            excludeSemantics: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w800,
                  fontSize: 96,
                  height: 0.9,
                  letterSpacing: -3,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
        if (direction != null) ...[
          const SizedBox(width: 16),
          SsStrumGlyph(
            direction: direction!,
            confidenceTier: confidenceTier,
            color: glyphColor ?? textColor,
            size: 48,
            semanticLabel: directionSemanticLabel,
          ),
        ],
      ],
    );
  }
}
