import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../model/live_frame.dart';
import 'input_level_meter.dart';

/// The slim status strip at the top of the Live screen: a listening indicator,
/// the input-level meter, and the detected tempo + tuning reference.
class LiveStatusBar extends StatelessWidget {
  const LiveStatusBar({super.key, required this.frame, this.a4 = 440});

  final LiveFrame frame;

  /// Concert-pitch reference A4 to display (the user's setting), Hz.
  final int a4;

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
        InputLevelMeter(level: frame.inputLevel),
        const Spacer(),
        Flexible(
          child: Text(
            '${frame.bpm.round()} BPM · A=$a4',
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: labelStyle,
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
