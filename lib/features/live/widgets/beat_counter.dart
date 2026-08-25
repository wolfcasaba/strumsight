import 'package:flutter/material.dart';

import '../../../core/design_system/public.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../model/beat_slot.dart';

/// The rolling beat counter "1 & 2 & 3 & 4 &" with a small strum mark above
/// each slot that carries one. The current slot is highlighted. A thin
/// feature-layer adapter over [SsBeatGrid] (E13-R18): it owns the
/// `BeatSlot`/`Strum` model translation, [SsBeatGrid] owns the rendering.
class BeatCounter extends StatelessWidget {
  const BeatCounter({super.key, required this.bar, this.activeIndex});

  final List<BeatSlot> bar;
  final int? activeIndex;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);

    return SsBeatGrid(
      activeColor: palette.ink,
      accentColor: palette.ink.withValues(alpha: 0.7),
      mutedColor: palette.muted,
      strumColor: palette.ink,
      activeIndex: activeIndex,
      slots: [
        for (final slot in bar)
          SsBeatGridSlot(
            label: slot.label,
            isAccent: slot.isDownbeat,
            direction: slot.strum == null
                ? null
                : (slot.strum!.isDown
                      ? SsStrumDirection.down
                      : SsStrumDirection.up),
            confidenceTier: slot.strum == null
                ? 0
                : AppColors.confidenceTier(slot.strum!.confidence),
            strumSemanticLabel: slot.strum == null
                ? null
                : '${slot.label} · ${slot.strum!.isDown ? l10n.strumDown : l10n.strumUp}',
          ),
      ],
    );
  }
}
