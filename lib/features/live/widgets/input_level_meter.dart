import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';

/// A tiny 5-bar microphone input-level meter (0..1).
class InputLevelMeter extends StatelessWidget {
  const InputLevelMeter({
    super.key,
    required this.level,
    this.bars = 5,
    this.height = 12,
  });

  /// 0..1.
  final double level;
  final int bars;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final clamped = level.clamp(0.0, 1.0);
    return Semantics(
      label: 'Input level',
      value: '${(clamped * 100).round()}%',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < bars; i++) ...[
            Container(
              width: 3,
              height: height * (0.4 + 0.6 * (i + 1) / bars),
              decoration: BoxDecoration(
                color: (i + 1) / bars <= clamped
                    ? AppColors.primary
                    : palette.track,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            if (i < bars - 1) const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }
}
