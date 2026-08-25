import 'package:flutter/material.dart';

import 'ss_strum_glyph.dart';

/// One slot in an [SsBeatGrid] — a beat/subdivision label, optionally
/// carrying a strum mark.
@immutable
final class SsBeatGridSlot {
  const SsBeatGridSlot({
    required this.label,
    this.isAccent = false,
    this.direction,
    this.confidenceTier = 0,
    this.strumSemanticLabel,
  });

  /// The beat label ("1", "&", …).
  final String label;

  /// Downbeat / accented slots render their label bolder.
  final bool isAccent;

  /// The strum landing on this slot, if any.
  final SsStrumDirection? direction;

  /// 0 = low, 1 = mid, 2 = high — drives the strum glyph shape.
  final int confidenceTier;

  final String? strumSemanticLabel;
}

/// The Stage timeline slot's rolling beat grid — "1 & 2 & 3 & 4 &" with a
/// small strum glyph above any slot that carries one. The active slot is
/// highlighted via [activeIndex].
final class SsBeatGrid extends StatelessWidget {
  const SsBeatGrid({
    super.key,
    required this.slots,
    required this.activeColor,
    required this.accentColor,
    required this.mutedColor,
    required this.strumColor,
    this.activeIndex,
  });

  final List<SsBeatGridSlot> slots;
  final int? activeIndex;

  /// Label colour for the currently active slot.
  final Color activeColor;

  /// Label colour for a downbeat (accented) slot that is not active.
  final Color accentColor;

  /// Label colour for a plain, inactive slot.
  final Color mutedColor;

  /// Strum-glyph colour (the glyph's own confidence tier still drives shape).
  final Color strumColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < slots.length; i++)
          Expanded(child: _slot(slots[i], i == activeIndex)),
      ],
    );
  }

  Widget _slot(SsBeatGridSlot slot, bool active) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 22,
          child: slot.direction == null
              ? null
              : Center(
                  child: SsStrumGlyph(
                    direction: slot.direction!,
                    confidenceTier: slot.confidenceTier,
                    color: strumColor,
                    size: 13,
                    semanticLabel: slot.strumSemanticLabel,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          slot.label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: slot.isAccent ? FontWeight.w700 : FontWeight.w400,
            fontSize: 12,
            color: active
                ? activeColor
                : (slot.isAccent ? accentColor : mutedColor),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
