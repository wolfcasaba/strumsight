import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/exercise_prescription.dart';
import '../../domain/model/plan_enums.dart';
import '../../domain/model/practice_block.dart';

/// Renders one [PracticeBlock] as an editable card.
///
/// The card is a presentation projection only — its `onTap` and `onDurationChanged`
/// callbacks are wired by the screen to the [PlanPreviewController]. The
/// widget itself never calls the controller or validator; this keeps the
/// rendering path offline and stateless (ADR 0264 §2).
class PlanBlockCard extends StatelessWidget {
  const PlanBlockCard({
    required this.block,
    required this.onTap,
    required this.onDurationChanged,
    super.key,
  });

  final PracticeBlock block;

  /// Tapped to open the reason sheet. The card passes the block's reason
  /// codes through [onReasonRequested] in the parent screen.
  final VoidCallback onTap;

  /// Called when the learner adjusts the active duration slider. A null
  /// value disables editing (used by tests and by the read-only state).
  final ValueChanged<Duration>? onDurationChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prescription = block.prescription;
    final theme = Theme.of(context);
    return Card(
      key: Key('plan-block-${block.id.value}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _localizedBlockKind(l10n, block.kind),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    _formatDuration(prescription.activeDuration),
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_localizedCandidate(prescription, l10n)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  for (final code in block.reasonCodes)
                    Chip(
                      key: Key('plan-block-${block.id.value}-reason-$code'),
                      label: Text(code),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              if (onDurationChanged != null) ...[
                const SizedBox(height: 8),
                _DurationSlider(
                  blockId: block.id.value,
                  activeDuration: prescription.activeDuration,
                  minimum: prescription.supportedDurations.minimum,
                  maximum: prescription.supportedDurations.maximum,
                  onChanged: onDurationChanged!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DurationSlider extends StatelessWidget {
  const _DurationSlider({
    required this.blockId,
    required this.activeDuration,
    required this.minimum,
    required this.maximum,
    required this.onChanged,
  });

  final String blockId;
  final Duration activeDuration;
  final Duration minimum;
  final Duration maximum;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    final minMicros = minimum.inMicroseconds;
    final maxMicros = maximum.inMicroseconds;
    final span = maxMicros - minMicros;
    if (span <= 0) {
      return const SizedBox.shrink();
    }
    final currentMicros = activeDuration.inMicroseconds.clamp(
      minMicros,
      maxMicros,
    );
    final value = (currentMicros - minMicros) / span;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_formatDuration(activeDuration)),
        Slider(
          key: Key('plan-block-$blockId-duration-slider'),
          value: value,
          onChanged: (next) {
            final micros = minMicros + (next * span).round();
            onChanged(Duration(microseconds: micros));
          },
        ),
      ],
    );
  }
}

String _localizedBlockKind(AppLocalizations l10n, BlockKind kind) =>
    switch (kind) {
      BlockKind.readiness => l10n.planPreviewBlockReadiness,
      BlockKind.warmup => l10n.planPreviewBlockWarmup,
      BlockKind.assessment => l10n.planPreviewBlockAssessment,
      BlockKind.primaryFocus => l10n.planPreviewBlockPrimaryFocus,
      BlockKind.secondaryFocus => l10n.planPreviewBlockSecondaryFocus,
      BlockKind.maintenance => l10n.planPreviewBlockMaintenance,
      BlockKind.song => l10n.planPreviewBlockSong,
      BlockKind.freePlay => l10n.planPreviewBlockFreePlay,
      BlockKind.reflection => l10n.planPreviewBlockReflection,
      BlockKind.rest => l10n.planPreviewBlockRest,
      BlockKind.cooldown => l10n.planPreviewBlockCooldown,
    };

String _localizedCandidate(
  ExercisePrescription prescription,
  AppLocalizations l10n,
) => '${prescription.exerciseId} (${prescription.source.code})';

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  if (seconds == 0) {
    return '${minutes}m';
  }
  return '${minutes}m${seconds.toString().padLeft(2, '0')}s';
}
