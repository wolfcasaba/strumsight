import 'package:flutter/material.dart';

import '../../../../core/music/strum.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/model/compiled_practice_target.dart';

/// One-bar pattern preview for the Strum Pattern mode. Renders every
/// [CompiledTargetEvent] of the first bar as a down/up/rest cell — and
/// **only** the first bar (the brief asks for a one-bar preview).
///
/// Rest slots and identical-direction neighbours are distinct cells
/// (ADR 0080 D9): no visual dedup is applied.
class PracticePatternPreview extends StatelessWidget {
  const PracticePatternPreview({
    required this.target,
    required this.barIndex,
    super.key,
  });

  final CompiledPracticeTarget target;
  final int barIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final barEvents = target.events
        .where((event) => event.barIndex == barIndex)
        .toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.practicePatternPreviewLabel,
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            if (barEvents.isEmpty)
              Text(l10n.practicePatternPreviewEmpty)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final event in barEvents) _Slot(event: event)],
              ),
          ],
        ),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.event});
  final CompiledTargetEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isRest = event.direction == null;
    final color = isRest
        ? theme.colorScheme.outline
        : (event.direction == StrumDirection.down
              ? AppColors.primary
              : AppColors.confidenceHigh);
    final label = isRest
        ? l10n.strumRest
        : (event.direction == StrumDirection.down
              ? l10n.strumDown
              : l10n.strumUp);
    final icon = isRest
        ? Icons.remove
        : (event.direction == StrumDirection.down
              ? Icons.arrow_downward
              : Icons.arrow_upward);
    return Semantics(
      label: label,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: isRest ? 0.12 : 0.22),
          border: Border.all(color: color, width: 1),
        ),
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }
}
