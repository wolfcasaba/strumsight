import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/speed_builder_state.dart';

class AdaptiveSuggestionBanner extends StatelessWidget {
  const AdaptiveSuggestionBanner({
    required this.suggestion,
    required this.onAccept,
    required this.onDismiss,
    super.key,
  });

  final AdaptiveSuggestion suggestion;
  final ValueChanged<AdaptiveSuggestion> onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.adaptiveSuggestionTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(_message(l10n, suggestion.reason)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDismiss,
                  child: Text(l10n.adaptiveSuggestionDismiss),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => onAccept(suggestion),
                  child: Text(l10n.adaptiveSuggestionApply),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _message(
    AppLocalizations l10n,
    AdaptiveSuggestionReason reason,
  ) => switch (reason) {
    AdaptiveSuggestionReason.insufficientSignal =>
      l10n.adaptiveSuggestionInsufficientSignal,
    AdaptiveSuggestionReason.lowCompletion =>
      l10n.adaptiveSuggestionLowCompletion,
    AdaptiveSuggestionReason.timingBias => l10n.adaptiveSuggestionTimingBias,
    AdaptiveSuggestionReason.directionError =>
      l10n.adaptiveSuggestionDirectionError,
    AdaptiveSuggestionReason.chordError => l10n.adaptiveSuggestionChordError,
    AdaptiveSuggestionReason.tempoTooHigh =>
      l10n.adaptiveSuggestionTempoTooHigh,
    AdaptiveSuggestionReason.positiveReinforcement =>
      l10n.adaptiveSuggestionPositive,
    AdaptiveSuggestionReason.nextDifficulty =>
      l10n.adaptiveSuggestionNextDifficulty,
  };
}
