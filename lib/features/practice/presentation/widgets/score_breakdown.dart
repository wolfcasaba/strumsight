import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/practice_metric_snapshot.dart';

/// One row of the breakdown table — `(label, dimension)`.
typedef ScoreBreakdownRow = ({
  String label,
  PracticeMetricDimension? dimension,
});

/// Per-dimension score breakdown panel.
///
/// Renders only the cells the caller passed in (A1: the screen is the
/// single source of truth for what is applicable — `findsNothing` for
/// the rest). Each cell renders either a normalised percentage, the
/// localised "not enough data" string, or the localised "not scored"
/// fallback (ADR 0084 §Döntés 10).
class ScoreBreakdown extends StatelessWidget {
  const ScoreBreakdown({required this.dimensions, super.key});

  /// Already-filtered list of `(label, dimension)` records.
  final List<ScoreBreakdownRow> dimensions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.practiceResultBreakdownTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final row in dimensions)
              if (row.dimension != null) _row(context, row, l10n),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    ScoreBreakdownRow row,
    AppLocalizations l10n,
  ) {
    final dimension = row.dimension!;
    final label = row.label;
    final text = switch (dimension) {
      PracticeMetricDimensionAvailable(:final value) =>
        '${(value * 100).round()}%',
      PracticeMetricDimensionNotApplicable() => l10n.practiceResultNotScored,
      PracticeMetricDimensionInsufficientData() =>
        l10n.practiceResultInsufficientData,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Semantics(
              label: l10n.practiceResultDimensionSemantic(label, text),
              child: Text(label),
            ),
          ),
          Text(text),
        ],
      ),
    );
  }
}
