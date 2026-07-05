import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../model/strum.dart';
import 'strum_arrow.dart';

/// The rolling beat counter "1 & 2 & 3 & 4 &" with a small strum mark above
/// each slot that carries one. The current slot is highlighted.
class BeatCounter extends StatelessWidget {
  const BeatCounter({super.key, required this.bar, this.activeIndex});

  final List<BeatSlot> bar;
  final int? activeIndex;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        for (var i = 0; i < bar.length; i++)
          Expanded(child: _slot(bar[i], i == activeIndex, palette)),
      ],
    );
  }

  Widget _slot(BeatSlot slot, bool active, AppPalette palette) {
    final s = slot.strum;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 22,
          child: s == null
              ? null
              : Center(
                  child: StrumArrow(
                    direction: s.direction,
                    confidence: s.confidence,
                    size: 13,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          slot.label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: slot.isDownbeat ? FontWeight.w700 : FontWeight.w400,
            fontSize: 12,
            color: active
                ? palette.ink
                : (slot.isDownbeat
                    ? palette.ink.withValues(alpha: 0.7)
                    : palette.muted),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
