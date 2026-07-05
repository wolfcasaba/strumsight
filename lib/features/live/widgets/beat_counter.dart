import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        for (var i = 0; i < bar.length; i++)
          Expanded(child: _slot(bar[i], i == activeIndex, palette, l10n)),
      ],
    );
  }

  Widget _slot(
    BeatSlot slot,
    bool active,
    AppPalette palette,
    AppLocalizations l10n,
  ) {
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
                    semanticLabel:
                        '${slot.label} · ${s.isDown ? l10n.strumDown : l10n.strumUp}',
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
