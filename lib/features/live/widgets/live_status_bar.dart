import 'package:flutter/material.dart';

import '../../../core/design_system/public.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../model/live_frame.dart';

/// The slim status strip at the top of the Live screen: a listening
/// indicator and the detected tempo + tuning reference. The input-level
/// meter moved to the Stage feedback slot ([SsSignalQualityIndicator],
/// E13-R18) so signal-quality feedback lives with the rest of it.
class LiveStatusBar extends StatelessWidget {
  const LiveStatusBar({
    super.key,
    required this.frame,
    this.a4 = 440,
    this.capo = 0,
  });

  final LiveFrame frame;

  /// Concert-pitch reference A4 to display (the user's setting), Hz.
  final int a4;

  /// Capo fret (0 = none). Shown so a transposed chord label isn't confusing.
  final int capo;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    final success = AppColors.successOn(Theme.of(context).brightness);
    final labelStyle = TextStyle(
      fontFamily: 'Poppins',
      fontSize: 11,
      letterSpacing: 0.5,
      color: palette.muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Row(
      children: [
        if (frame.listening) ...[
          _Dot(color: success),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              l10n.liveListening.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle.copyWith(color: success),
            ),
          ),
        ],
        const Spacer(),
        Flexible(
          child: SsTempoDisplay(
            bpm: frame.bpm,
            tuningLabel: 'A=$a4',
            capoLabel: capo > 0 ? l10n.liveCapo(capo) : null,
            color: palette.muted,
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
