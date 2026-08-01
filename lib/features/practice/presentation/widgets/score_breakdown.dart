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
/// the rest). Each cell renders either a normalised percentage, or the
/// localised "not enough data" string when the dimension is recorded but
/// has too few samples to score.
///
/// `PracticeMetricDimensionNotApplicable` is the documented "this
/// dimension does not exist for this mode" signal (ADR 0084 §Döntés 10)
/// — the cell is removed from the tree, not rendered as a placeholder.
/// The single source of truth is the dimension's subtype, so the widget
/// produces `findsNothing` for the not-applicable case without the caller
/// having to filter (m1).
class ScoreBreakdown extends StatelessWidget {
  const ScoreBreakdown({required this.dimensions, super.key});

  /// Already-filtered list of `(label, dimension)` records. A `dimension`
  /// that is `null` or `PracticeMetricDimensionNotApplicable` is omitted
  /// from the tree — there is no "Not scored" row.
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
              if (row.dimension != null &&
                  row.dimension is! PracticeMetricDimensionNotApplicable)
                _row(context, row, l10n),
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
      PracticeMetricDimensionInsufficientData() =>
        l10n.practiceResultInsufficientData,
      // Unreachable: the build filter removes NotApplicable before _row
      // runs. The fall-through keeps the switch exhaustive and would
      // surface as a `null` text widget if a regression ever reaches here.
      PracticeMetricDimensionNotApplicable() => '',
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
