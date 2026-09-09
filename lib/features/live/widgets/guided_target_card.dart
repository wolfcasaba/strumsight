import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';

/// The Guided-mode TARGET: the chord the player is being asked to play
/// (E14-R37, ADR 0550 D3).
///
/// This is deliberately NOT the stage's hero. The hero slot is the
/// **detection** slot — what the app claims to have heard — and a target is
/// the opposite kind of statement: what the app is asking for. Rendering a
/// target where a detection lives would let a lesson's expectation read as a
/// recognition result, which is the exact confusion ADR 0544 removed from
/// the DSP path; this round removes it from the screen too.
///
/// Three separations keep the two apart and are pinned by
/// `test/features/live/screens/live_stage_mode_test.dart`:
///  1. the card is always labelled with [AppLocalizations.liveGuidedTarget]
///     ("Target"), never with a recognition word;
///  2. it renders in the stage's `feedback` slot, never in `hero`;
///  3. its semantics say "target chord X", so a screen-reader user is told
///     the role before the value.
class GuidedTargetCard extends StatelessWidget {
  const GuidedTargetCard({super.key, required this.chordLabel});

  /// The expected chord, already transposed for display by the caller.
  final String chordLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return Semantics(
      label: l10n.liveGuidedTargetSemantics(chordLabel),
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('live-guided-target'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.my_location, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.liveGuidedTarget.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: palette.muted,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                chordLabel,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
