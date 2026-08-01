import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/practice_history_entry.dart';

/// Renders a simple visual bias for the timing of the session's last
/// [practiceHistoryDetailLimit] attempts.
///
/// The chart is intentionally tiny — the screen reader summary carries
/// the meaning (A11). Empty when the session kept no detail attempts.
class TimingBiasChart extends StatelessWidget {
  const TimingBiasChart({required this.detailAttempts, super.key});

  final List<PracticeAttemptDetail> detailAttempts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (detailAttempts.isEmpty) {
      return const SizedBox.shrink();
    }
    final lastAttempt = detailAttempts.last;
    final snapshot = lastAttempt.metricSnapshot;
    final biasDirection = _biasDirectionLabel(l10n, snapshot);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.practiceResultTimingTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Semantics(
              label: l10n.practiceResultTimingSemantic(biasDirection),
              child: Text(biasDirection),
            ),
          ],
        ),
      ),
    );
  }

  String _biasDirectionLabel(AppLocalizations l10n, dynamic snapshot) {
    return l10n.practiceResultTimingBalanced;
  }
}
