import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/practice_day.dart';
import 'plan_block_card.dart';

/// Renders one [PracticeDay] as a card containing its blocks.
///
/// The day card composes [PlanBlockCard]s and lets the screen wire each
/// block's `onDurationChanged` to the [PlanPreviewController]. The card is
/// strictly a presentation projection: it does not touch any state.
class PlanDayCard extends StatelessWidget {
  const PlanDayCard({
    required this.day,
    required this.onReasonRequested,
    required this.onBlockDurationChanged,
    super.key,
  });

  final PracticeDay day;

  /// Forwarded to each block's onTap; the screen pops the reason sheet.
  final ValueChanged<PracticeBlock> onReasonRequested;

  /// Forwarded to each block's duration slider.
  final void Function(String blockId, Duration newDuration)
      onBlockDurationChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      key: Key('plan-day-${day.id.value}'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _localizedDate(l10n, day.localDate),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  _formatDuration(day.timeBudget),
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final block in day.blocks)
              PlanBlockCard(
                block: block,
                onTap: () => onReasonRequested(block),
                onDurationChanged: (next) =>
                    onBlockDurationChanged(block.id.value, next),
              ),
          ],
        ),
      ),
    );
  }
}

String _localizedDate(AppLocalizations l10n, LocalDate date) {
  // The screen does not import a date formatter to keep the widget offline
  // and dependency-light; a stable ISO-style line is fine for the preview
  // since the localized week label is composed from ARB keys.
  final weekdayLabel = _weekdayLabel(l10n, date);
  return '$weekdayLabel · ${date.year}-${_pad(date.month)}-${_pad(date.day)}';
}

String _weekdayLabel(AppLocalizations l10n, LocalDate date) {
  final mondayBasedIndex = _mondayBasedIndex(date);
  return switch (mondayBasedIndex) {
    0 => l10n.planPreviewMonday,
    1 => l10n.planPreviewTuesday,
    2 => l10n.planPreviewWednesday,
    3 => l10n.planPreviewThursday,
    4 => l10n.planPreviewFriday,
    5 => l10n.planPreviewSaturday,
    _ => l10n.planPreviewSunday,
  };
}

int _mondayBasedIndex(LocalDate date) {
  // Zeller's congruence, Monday=0 .. Sunday=6.
  var month = date.month;
  var year = date.year;
  if (month < 3) {
    month += 12;
    year -= 1;
  }
  final k = year % 100;
  final j = year ~/ 100;
  final h = (date.day +
          ((13 * (month + 1)) ~/ 5) +
          k +
          (k ~/ 4) +
          (j ~/ 4) -
          (2 * j)) %
      7;
  // h: 0=Saturday, 1=Sunday, 2=Monday, ..., 6=Friday
  return ((h + 5) % 7);
}

String _pad(int value) => value.toString().padLeft(2, '0');

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final restMinutes = minutes % 60;
  if (restMinutes == 0) return '${hours}h';
  return '${hours}h${restMinutes}m';
}
