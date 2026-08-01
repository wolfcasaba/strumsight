import 'package:flutter/material.dart';

import '../../../../core/music/strum.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/model/practice_metrics.dart';
import '../../domain/model/practice_verdict.dart';

/// Verdict-driven inline feedback rendered above the highway.
///
/// The widget owns no scoring logic — it consumes the [PracticeVerdict] the
/// host emits and renders the matching [TimingGrade] / [DirectionOutcome]
/// copy. The combo is read from [PracticeMetrics.maxCombo] (R10: the
/// `currentCombo` field does not exist on the metrics surface).
class PracticeFeedback extends StatelessWidget {
  const PracticeFeedback({
    required this.verdict,
    required this.metrics,
    super.key,
  });

  final PracticeVerdict? verdict;
  final PracticeMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final v = verdict;
    final m = metrics;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.practiceFeedbackTimingLabel,
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            if (v == null)
              Text(l10n.practiceFeedbackNoVerdict)
            else
              Row(
                children: [
                  Icon(
                    _gradeIcon(v),
                    color: _gradeColor(theme, v),
                    semanticLabel: _gradeSemanticLabel(l10n, v),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _gradeLabel(l10n, v),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Text(
              l10n.practiceFeedbackDirectionLabel,
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            if (v == null || v.expectedDirection == null)
              Text(l10n.practiceFeedbackDirectionNone)
            else
              Row(
                children: [
                  Icon(
                    v.expectedDirection == StrumDirection.down
                        ? Icons.arrow_downward
                        : Icons.arrow_upward,
                    semanticLabel: v.expectedDirection == StrumDirection.down
                        ? l10n.strumDown
                        : l10n.strumUp,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _directionLabel(l10n, v),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  l10n.practiceFeedbackComboLabel,
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(width: 8),
                Text(
                  m == null ? '0' : '${m.maxCombo}',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static IconData _gradeIcon(PracticeVerdict v) {
    switch (v.timingGrade) {
      case TimingGrade.perfect:
        return Icons.star;
      case TimingGrade.good:
        return Icons.check_circle;
      case TimingGrade.early:
      case TimingGrade.late:
        return Icons.timer;
      case TimingGrade.missed:
        return Icons.close;
      case TimingGrade.notApplicable:
        return Icons.remove;
    }
  }

  static Color _gradeColor(ThemeData theme, PracticeVerdict v) {
    switch (v.timingGrade) {
      case TimingGrade.perfect:
        return Colors.amber;
      case TimingGrade.good:
        return Colors.green;
      case TimingGrade.early:
      case TimingGrade.late:
        return Colors.orange;
      case TimingGrade.missed:
        return theme.colorScheme.error;
      case TimingGrade.notApplicable:
        return theme.colorScheme.outline;
    }
  }

  static String _gradeSemanticLabel(AppLocalizations l10n, PracticeVerdict v) {
    return _gradeLabel(l10n, v);
  }

  static String _gradeLabel(AppLocalizations l10n, PracticeVerdict v) {
    switch (v.timingGrade) {
      case TimingGrade.perfect:
        return l10n.learnPerfect;
      case TimingGrade.good:
        return l10n.learnGood;
      case TimingGrade.early:
        return l10n.learnEarly;
      case TimingGrade.late:
        return l10n.learnLate;
      case TimingGrade.missed:
        return l10n.learnMiss;
      case TimingGrade.notApplicable:
        return l10n.practiceFeedbackTimingNotApplicable;
    }
  }

  static String _directionLabel(AppLocalizations l10n, PracticeVerdict v) {
    switch (v.directionOutcome) {
      case DirectionOutcome.correct:
        return l10n.practiceFeedbackDirectionCorrect;
      case DirectionOutcome.wrong:
        final expected = v.expectedDirection == StrumDirection.down
            ? l10n.strumDown
            : l10n.strumUp;
        return l10n.practiceFeedbackDirectionWrong(expected);
      case DirectionOutcome.notApplicable:
        return l10n.practiceFeedbackDirectionNone;
    }
  }
}
