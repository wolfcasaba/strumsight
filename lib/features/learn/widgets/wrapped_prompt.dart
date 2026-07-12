import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// The post-win "share my week" prompt (chunk 017 rec #5's auto-prompt half,
/// r153): after a GOOD run (≥ [threshold] accuracy) the finish dialog offers
/// the weekly Wrapped card — the moment of pride is the moment people share.
/// Deliberately a quiet inline row, not a modal: no spam, one tap away.
class WrappedPrompt extends StatelessWidget {
  const WrappedPrompt({
    super.key,
    required this.accuracy,
    required this.onOpen,
  });

  static const double threshold = 0.8;

  final double accuracy;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (accuracy < threshold) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextButton.icon(
        onPressed: onOpen,
        icon: const Icon(Icons.calendar_month, size: 18),
        label: Text(l10n.wrappedShareTooltip),
      ),
    );
  }
}
