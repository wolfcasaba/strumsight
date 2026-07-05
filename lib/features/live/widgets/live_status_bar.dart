import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../model/live_frame.dart';
import 'input_level_meter.dart';

/// The slim status strip at the top of the Live screen: a listening indicator,
/// the input-level meter, and the detected tempo + tuning reference.
class LiveStatusBar extends StatelessWidget {
  const LiveStatusBar({super.key, required this.frame});

  final LiveFrame frame;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
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
          _Dot(color: AppColors.confidenceHigh),
          const SizedBox(width: 6),
          Text(
            l10n.liveListening.toUpperCase(),
            style: labelStyle.copyWith(color: AppColors.confidenceHigh),
          ),
        ],
        const Spacer(),
        InputLevelMeter(level: frame.inputLevel),
        const Spacer(),
        Text(
          '${frame.bpm.round()} BPM · A=${frame.tuningHz.round()}',
          style: labelStyle,
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
