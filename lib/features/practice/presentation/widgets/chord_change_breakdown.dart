import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/chord_pair_stats.dart';

/// Renders the measured evidence for each directed chord pair.
class ChordChangeBreakdown extends StatelessWidget {
  const ChordChangeBreakdown({
    required this.pairStats,
    this.slowestPair,
    super.key,
  });

  final List<ChordPairStats> pairStats;
  final ChordPairStats? slowestPair;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ordered = pairStats.toList()
      ..sort((left, right) => compareChordPairs(left.pair, right.pair));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.practiceChordChangeBreakdown,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (ordered.isEmpty)
              Text(l10n.practiceChordChangeNoStats)
            else
              for (final stats in ordered) _PairTile(stats: stats),
            if (slowestPair != null &&
                slowestPair!.medianRecognizedChangeDelay != null) ...[
              const SizedBox(height: 12),
              Text(
                l10n.practiceChordChangeSlowest(slowestPair!.pair.key),
                style: theme.textTheme.labelLarge,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PairTile extends StatelessWidget {
  const _PairTile({required this.stats});

  final ChordPairStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final median = stats.medianRecognizedChangeDelay;
    final semanticLabel = l10n.practiceChordChangePairSemantic(
      stats.pair.key,
      stats.attempts,
      stats.correctChanges,
      median?.inMilliseconds.toString() ?? l10n.practiceChordChangeNoStats,
    );
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${stats.pair.from} → ${stats.pair.to}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(l10n.practiceChordChangePairAttempts(stats.attempts)),
            Text(l10n.practiceChordChangePairCorrect(stats.correctChanges)),
            Text(l10n.practiceChordChangePairWrong(stats.wrongChordCount)),
            Text(
              l10n.practiceChordChangePairNoDetection(stats.noDetectionCount),
            ),
            Text(l10n.practiceChordChangePairUnstable(stats.unstableCount)),
            Text(
              l10n.practiceChordChangePairInsufficient(
                stats.insufficientSignalCount,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              median == null
                  ? l10n.practiceChordChangeNoStats
                  : l10n.practiceChordChangeMedian(median.inMilliseconds),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (stats.labelMappingIsLossy)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.practiceChordChangeMappingLimited,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
