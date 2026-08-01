import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/speed_builder_state.dart';

class SpeedBuilderProgress extends StatelessWidget {
  const SpeedBuilderProgress({
    required this.state,
    this.currentLoop,
    this.totalLoops,
    super.key,
  });

  final SpeedBuilderState state;
  final int? currentLoop;
  final int? totalLoops;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final policy = state.policy;
    final nextBpm = (state.currentTempo.bpm + policy.stepBpm).clamp(
      policy.startBpm.bpm,
      policy.targetBpm.bpm,
    );
    final stable = state.highestStableTempo;
    final stableLabel = stable == null
        ? l10n.speedBuilderNoStableBpm
        : '${_formatBpm(stable.bpm)} BPM';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.speedBuilderTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Text(
                  l10n.speedBuilderCurrentBpm(
                    _formatBpm(state.currentTempo.bpm),
                  ),
                ),
                Text(
                  l10n.speedBuilderTargetBpm(_formatBpm(policy.targetBpm.bpm)),
                ),
                Text(
                  l10n.speedBuilderPassStreak(
                    state.successStreak,
                    policy.requiredConsecutivePasses,
                  ),
                ),
                Text(l10n.speedBuilderNextStep(_formatBpm(nextBpm))),
                Text(
                  l10n.speedBuilderAttempt(
                    (state.attempts.length + 1).clamp(1, policy.maxAttempts),
                    policy.maxAttempts,
                  ),
                ),
                Text(l10n.speedBuilderHighestStable(stableLabel)),
                if (currentLoop != null && totalLoops != null)
                  Text(l10n.speedBuilderLoop(currentLoop!, totalLoops!)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatBpm(num bpm) =>
      bpm == bpm.roundToDouble() ? bpm.toInt().toString() : bpm.toString();
}
