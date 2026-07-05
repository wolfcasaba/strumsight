import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../model/strum.dart';

/// A small pill under the hero arrow: e.g. "DOWN · 94%", coloured by the
/// confidence ramp. Renders nothing when there is no strum yet.
class ConfidencePill extends StatelessWidget {
  const ConfidencePill({super.key, required this.strum});

  final Strum? strum;

  @override
  Widget build(BuildContext context) {
    final s = strum;
    if (s == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final color = AppColors.confidence(s.confidence);
    final dir = s.isDown ? l10n.strumDown : l10n.strumUp;
    final pct = (s.confidence * 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Text(
        '${dir.toUpperCase()} · $pct%',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 1,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
